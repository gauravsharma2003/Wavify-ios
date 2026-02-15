//
//  StemDecomposer.swift
//  Wavify
//
//  Real-time stem decomposition using mid-side analysis + HPSS + biquad filtering.
//  Decomposes stereo audio into four stems: drums, bass, vocals, atmosphere.
//
//  Mid = (L + R) / 2  →  center-panned content (vocals, bass, kick, snare)
//  Side = (L - R) / 2  →  wide-panned content (guitars, synths, reverb)
//
//  HPSS splits the mid signal into harmonic (sustained) and percussive (transient):
//    Drums: percussive mid signal (kick, snare, hi-hats — center transients)
//    Bass: low-pass on harmonic mid (< 250Hz sustained content, no kick bleed)
//    Vocals: harmonic mid minus bass (250Hz+ center sustained content)
//    Atmosphere: side signal delayed to match HPSS latency (guitars, pads, stereo effects)
//

import Foundation
import Accelerate

final class StemDecomposer {

    // MARK: - Ring Buffer Targets

    /// Bass stem output (interleaved stereo: mono bass written as L=mid, R=mid)
    let bassBuffer: CircularBuffer
    /// Vocal stem output (interleaved stereo: mono vocal written as L=mid, R=mid)
    let vocalBuffer: CircularBuffer
    /// Atmosphere stem output (interleaved stereo: L=side, R=-side)
    let instrumentBuffer: CircularBuffer
    /// Drums stem output (interleaved stereo: mono drums written as L=mid, R=mid)
    let drumsBuffer: CircularBuffer?

    /// Also write full mix to the normal ring buffer (for analysis/fallback)
    let fullMixBuffer: CircularBuffer?

    // MARK: - DSP

    /// Low-pass filter at 250Hz for bass isolation — cascaded pair for 24dB/octave
    private let bassFilter = BiquadFilter()
    private let bassFilter2 = BiquadFilter()

    /// HPSS processor for harmonic-percussive separation on mid signal
    private let hpss = SlidingSTFT()

    /// Beat tracker consuming spectral flux from HPSS
    let beatTracker = BeatTracker()

    // MARK: - Pre-allocated Scratch Buffers

    private var midBuffer: UnsafeMutablePointer<Float>?
    private var sideBuffer: UnsafeMutablePointer<Float>?
    private var bassSignal: UnsafeMutablePointer<Float>?
    private var interleavedOut: UnsafeMutablePointer<Float>?
    private var scratchCapacity: Int = 0

    // HPSS output scratch buffers
    private var harmonicAccum: UnsafeMutablePointer<Float>?
    private var percussiveAccum: UnsafeMutablePointer<Float>?
    private var harmonicAccumCount: Int = 0
    private var percussiveAccumCount: Int = 0
    private var hpssCapacity: Int = 0

    // Side signal delay line (aligns side with HPSS output)
    private var sideDelayLine: UnsafeMutablePointer<Float>?
    private var sideDelayWritePos: Int = 0
    private let sideDelayLength: Int  // = HPSS latency in samples

    // Transient sharpening state
    private var drumEnvelope: Float = 0

    /// Vocal stereo width bloom (0=mono center, 1=wide). Driven by choreographer.
    var vocalWidthBloom: Float = 0

    /// Vocal reverb wet/dry mix (0=dry, 1=full reverb). Set by CrossfadeEngine at 60Hz.
    var vocalReverbMix: Float = 0

    /// Schroeder reverb for outgoing vocal dissolution
    private let reverb = SchroederReverb()

    // MARK: - Analysis

    /// Running RMS accumulators for mono detection
    private(set) var midRMSAccumulator: Double = 0
    private(set) var sideRMSAccumulator: Double = 0
    private(set) var analysisFrameCount: Int = 0

    /// A-weighted RMS: mid-frequency vocal energy (weighted higher for perceptual loudness)
    private var midFreqRMSAccumulator: Double = 0
    private var midFreqFrameCount: Int = 0

    // MARK: - Vocal Energy Monitoring

    /// Rolling window of per-block vocal RMS (215 entries ≈ 2.5s at one entry per HPSS hop)
    private let vocalWindowSize = 215
    private var vocalRMSWindow: UnsafeMutablePointer<Float>?
    private var vocalWindowWritePos: Int = 0
    private var vocalWindowCount: Int = 0

    /// Long-term vocal energy accumulator
    private var vocalRMSLongAccumulator: Double = 0
    private var vocalRMSLongFrameCount: Int = 0

    // MARK: - Drum+Bass Energy Monitoring

    /// Rolling window of per-block combined drum+bass RMS (215 entries ≈ 2.5s)
    private let drumBassWindowSize = 215
    private var drumBassEnergyWindow: UnsafeMutablePointer<Float>?
    private var drumBassWindowWritePos: Int = 0
    private var drumBassWindowCount: Int = 0

    /// Long-term drum+bass energy accumulator
    private var drumBassEnergyLongAccumulator: Double = 0
    private var drumBassEnergyLongFrameCount: Int = 0

    // MARK: - Init

    init(bassBuffer: CircularBuffer,
         vocalBuffer: CircularBuffer,
         instrumentBuffer: CircularBuffer,
         drumsBuffer: CircularBuffer? = nil,
         fullMixBuffer: CircularBuffer? = nil,
         sampleRate: Double = 44100) {
        self.bassBuffer = bassBuffer
        self.vocalBuffer = vocalBuffer
        self.instrumentBuffer = instrumentBuffer
        self.drumsBuffer = drumsBuffer
        self.fullMixBuffer = fullMixBuffer

        // HPSS latency: (medianLength/2) × hopSize
        self.sideDelayLength = hpss.latencySamples

        // Configure low-pass at 250Hz (Butterworth) — cascaded for 24dB/octave
        let coeffs = BiquadCoefficientCalculator.lowPass(cutoff: 250, sampleRate: sampleRate)
        bassFilter.setCoefficients(coeffs)
        bassFilter2.setCoefficients(coeffs)
        // Force immediate application (no interpolation from bypass)
        bassFilter.reset()
        bassFilter2.reset()

        // Allocate side delay line
        sideDelayLine = .allocate(capacity: sideDelayLength)
        sideDelayLine?.initialize(repeating: 0, count: sideDelayLength)

        // Allocate vocal energy rolling window
        vocalRMSWindow = .allocate(capacity: vocalWindowSize)
        vocalRMSWindow?.initialize(repeating: 0, count: vocalWindowSize)

        // Allocate drum+bass energy rolling window
        drumBassEnergyWindow = .allocate(capacity: drumBassWindowSize)
        drumBassEnergyWindow?.initialize(repeating: 0, count: drumBassWindowSize)
    }

    deinit {
        midBuffer?.deallocate()
        sideBuffer?.deallocate()
        bassSignal?.deallocate()
        interleavedOut?.deallocate()
        harmonicAccum?.deallocate()
        percussiveAccum?.deallocate()
        sideDelayLine?.deallocate()
        vocalRMSWindow?.deallocate()
        drumBassEnergyWindow?.deallocate()
    }

    // MARK: - Decompose

    /// Decompose planar stereo audio into 4 stems and write to ring buffers.
    /// Called from the tap callback on the real-time audio thread.
    func decompose(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
        ensureBuffers(frameCount: frameCount)

        guard let mid = midBuffer,
              let side = sideBuffer,
              let bass = bassSignal,
              let interleaved = interleavedOut else { return }

        // 1. Mid-side decomposition using vDSP
        //    mid  = (L + R) * 0.5
        //    side = (L - R) * 0.5
        var half: Float = 0.5
        vDSP_vadd(left, 1, right, 1, mid, 1, vDSP_Length(frameCount))
        vDSP_vsmul(mid, 1, &half, mid, 1, vDSP_Length(frameCount))

        vDSP_vsub(right, 1, left, 1, side, 1, vDSP_Length(frameCount))
        vDSP_vsmul(side, 1, &half, side, 1, vDSP_Length(frameCount))

        // 2. Accumulate RMS for mono detection
        var midSumSq: Float = 0
        var sideSumSq: Float = 0
        vDSP_svesq(mid, 1, &midSumSq, vDSP_Length(frameCount))
        vDSP_svesq(side, 1, &sideSumSq, vDSP_Length(frameCount))
        midRMSAccumulator += Double(midSumSq)
        sideRMSAccumulator += Double(sideSumSq)
        analysisFrameCount += frameCount

        // 3. Feed mid → HPSS
        if let drums = drumsBuffer {
            let hops = hpss.process(input: mid, frameCount: frameCount)

            // Feed spectral flux to beat tracker for each hop produced
            if hops > 0 {
                beatTracker.feedFlux(hpss.lastSpectralFlux)
            }

            if hops > 0 && hpss.isWarmedUp {
                // HPSS produced output — use 4-stem path
                decompose4Stem(
                    side: side,
                    frameCount: frameCount,
                    hopsProduced: hops,
                    interleaved: interleaved,
                    bass: bass,
                    drumsBuffer: drums
                )
            } else {
                // Not warmed up yet — fallback to 3-stem logic + silence drums
                decompose3StemFallback(
                    mid: mid,
                    side: side,
                    bass: bass,
                    interleaved: interleaved,
                    frameCount: frameCount,
                    drumsBuffer: drums
                )
            }
        } else {
            // No drums buffer — pure 3-stem mode (legacy)
            decompose3Stem(mid: mid, side: side, bass: bass, interleaved: interleaved, frameCount: frameCount)
        }

        // Write full mix to normal ring buffer (for non-stem path)
        if let fullMix = fullMixBuffer {
            let sampleCount = frameCount * 2
            for i in 0..<frameCount {
                interleaved[i * 2] = left[i]
                interleaved[i * 2 + 1] = right[i]
            }
            fullMix.write(interleaved, count: sampleCount)
        }
    }

    // MARK: - 4-Stem HPSS Path

    private func decompose4Stem(
        side: UnsafeMutablePointer<Float>,
        frameCount: Int,
        hopsProduced: Int,
        interleaved: UnsafeMutablePointer<Float>,
        bass: UnsafeMutablePointer<Float>,
        drumsBuffer: CircularBuffer
    ) {
        let hopSize = hpss.hopSize
        let totalHPSSFrames = hopsProduced * hopSize

        ensureHPSSBuffers(capacity: totalHPSSFrames)
        guard let harmonic = harmonicAccum, let percussive = percussiveAccum else { return }

        // Pull all hops worth of harmonic/percussive data
        // Note: SlidingSTFT only stores the most recent hop, so for multiple hops
        // we accumulate across process() calls. With typical frameCount (512-1024)
        // and hopSize=512, we usually get 1-2 hops per call.
        // For the last hop, pull the data:
        if hopsProduced == 1 {
            hpss.pullHarmonic(into: harmonic)
            hpss.pullPercussive(into: percussive)
        } else {
            // Multiple hops — we only have the last hop's output
            // Process each hop individually by pulling after each
            hpss.pullHarmonic(into: harmonic)
            hpss.pullPercussive(into: percussive)
        }

        let outputFrames = hopSize  // Process one hop at a time

        // Bass = cascaded low-pass on harmonic (sustained bass, no kick)
        memcpy(bass, harmonic, outputFrames * MemoryLayout<Float>.size)
        bassFilter.processMono(buffer: bass, frameCount: outputFrames)
        bassFilter2.processMono(buffer: bass, frameCount: outputFrames)

        // Vocals = harmonic - bass (clean vocals, no drums)
        // Reuse harmonic buffer: harmonic = harmonic - bass
        var negOne: Float = -1.0
        vDSP_vsma(bass, 1, &negOne, harmonic, 1, harmonic, 1, vDSP_Length(outputFrames))

        // Accumulate vocal RMS for A-weighted loudness
        var vocalSumSq: Float = 0
        vDSP_svesq(harmonic, 1, &vocalSumSq, vDSP_Length(outputFrames))
        midFreqRMSAccumulator += Double(vocalSumSq)
        midFreqFrameCount += outputFrames

        // Track per-block vocal RMS for smart transition detection
        let blockVocalRMS = sqrtf(vocalSumSq / Float(outputFrames))
        if let window = vocalRMSWindow {
            window[vocalWindowWritePos] = blockVocalRMS
            vocalWindowWritePos = (vocalWindowWritePos + 1) % vocalWindowSize
            if vocalWindowCount < vocalWindowSize { vocalWindowCount += 1 }
        }
        vocalRMSLongAccumulator += Double(vocalSumSq)
        vocalRMSLongFrameCount += outputFrames

        // Track combined drum+bass energy for energy profiling
        var drumSumSq: Float = 0
        vDSP_svesq(percussive, 1, &drumSumSq, vDSP_Length(outputFrames))
        var bassSumSq: Float = 0
        vDSP_svesq(bass, 1, &bassSumSq, vDSP_Length(outputFrames))
        let combinedRMS = sqrtf(drumSumSq / Float(outputFrames)) + sqrtf(bassSumSq / Float(outputFrames))
        if let window = drumBassEnergyWindow {
            window[drumBassWindowWritePos] = combinedRMS
            drumBassWindowWritePos = (drumBassWindowWritePos + 1) % drumBassWindowSize
            if drumBassWindowCount < drumBassWindowSize { drumBassWindowCount += 1 }
        }
        drumBassEnergyLongAccumulator += Double(combinedRMS)
        drumBassEnergyLongFrameCount += 1

        // Apply Schroeder reverb to outgoing vocals (dissolution effect)
        let reverbMix = vocalReverbMix
        if reverbMix > 0.001 {
            let bpm = beatTracker.estimatedBPM
            reverb.setDecayTime(min(0.8, Float(60.0 / max(bpm, 60) * 0.8)))
            let dryMix: Float = 1.0 - reverbMix * 0.5
            for i in 0..<outputFrames {
                let reverbSample = reverb.process(harmonic[i])
                harmonic[i] = harmonic[i] * dryMix + reverbSample * reverbMix
            }
        }

        // Drums = percussive with transient sharpening
        applyTransientSharpening(buffer: percussive, frameCount: outputFrames)

        // Atmosphere = delayed side signal (aligned to HPSS output)
        // We need to output hopSize frames of delayed side
        let delayedSide = UnsafeMutablePointer<Float>.allocate(capacity: outputFrames)
        defer { delayedSide.deallocate() }
        readDelayedSide(into: delayedSide, frameCount: outputFrames)

        // Feed current side into delay line
        feedSideDelay(side: side, frameCount: frameCount)

        // Write bass stem (mono → stereo)
        let sampleCount = outputFrames * 2
        for i in 0..<outputFrames {
            interleaved[i * 2] = bass[i]
            interleaved[i * 2 + 1] = bass[i]
        }
        bassBuffer.write(interleaved, count: sampleCount)

        // Write vocal stem (mono → stereo, with optional bloom widening)
        let bloom = vocalWidthBloom
        if bloom > 0 {
            // Add side signal bleed for stereo widening (max 30%)
            let bleedAmount = bloom * 0.3
            for i in 0..<outputFrames {
                interleaved[i * 2] = harmonic[i] + delayedSide[i] * bleedAmount
                interleaved[i * 2 + 1] = harmonic[i] - delayedSide[i] * bleedAmount
            }
        } else {
            for i in 0..<outputFrames {
                interleaved[i * 2] = harmonic[i]
                interleaved[i * 2 + 1] = harmonic[i]
            }
        }
        vocalBuffer.write(interleaved, count: sampleCount)

        // Write drums stem (mono → stereo)
        for i in 0..<outputFrames {
            interleaved[i * 2] = percussive[i]
            interleaved[i * 2 + 1] = percussive[i]
        }
        drumsBuffer.write(interleaved, count: sampleCount)

        // Write atmosphere stem (stereo: L=side, R=-side)
        for i in 0..<outputFrames {
            interleaved[i * 2] = delayedSide[i]
            interleaved[i * 2 + 1] = -delayedSide[i]
        }
        instrumentBuffer.write(interleaved, count: sampleCount)
    }

    // MARK: - 3-Stem Fallback (during HPSS warmup)

    private func decompose3StemFallback(
        mid: UnsafeMutablePointer<Float>,
        side: UnsafeMutablePointer<Float>,
        bass: UnsafeMutablePointer<Float>,
        interleaved: UnsafeMutablePointer<Float>,
        frameCount: Int,
        drumsBuffer: CircularBuffer
    ) {
        // Feed side into delay line (keeps accumulating for when HPSS warms up)
        feedSideDelay(side: side, frameCount: frameCount)

        // Standard 3-stem decomposition
        decompose3Stem(mid: mid, side: side, bass: bass, interleaved: interleaved, frameCount: frameCount)

        // Write silence to drums buffer
        let sampleCount = frameCount * 2
        let silence = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
        defer { silence.deallocate() }
        silence.initialize(repeating: 0, count: sampleCount)
        drumsBuffer.write(silence, count: sampleCount)
    }

    // MARK: - 3-Stem Legacy Path

    private func decompose3Stem(
        mid: UnsafeMutablePointer<Float>,
        side: UnsafeMutablePointer<Float>,
        bass: UnsafeMutablePointer<Float>,
        interleaved: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        // Bass isolation: cascaded low-pass filter on mid signal (24dB/octave)
        memcpy(bass, mid, frameCount * MemoryLayout<Float>.size)
        bassFilter.processMono(buffer: bass, frameCount: frameCount)
        bassFilter2.processMono(buffer: bass, frameCount: frameCount)

        // Vocals: mid - bass (center content above 250Hz)
        var negOne: Float = -1.0
        vDSP_vsma(bass, 1, &negOne, mid, 1, mid, 1, vDSP_Length(frameCount))

        // Accumulate vocal RMS for A-weighted loudness
        var vocalSumSq3: Float = 0
        vDSP_svesq(mid, 1, &vocalSumSq3, vDSP_Length(frameCount))
        midFreqRMSAccumulator += Double(vocalSumSq3)
        midFreqFrameCount += frameCount

        // Track per-block vocal RMS for smart transition detection
        let blockVocalRMS3 = sqrtf(vocalSumSq3 / Float(frameCount))
        if let window = vocalRMSWindow {
            window[vocalWindowWritePos] = blockVocalRMS3
            vocalWindowWritePos = (vocalWindowWritePos + 1) % vocalWindowSize
            if vocalWindowCount < vocalWindowSize { vocalWindowCount += 1 }
        }
        vocalRMSLongAccumulator += Double(vocalSumSq3)
        vocalRMSLongFrameCount += frameCount

        let sampleCount = frameCount * 2

        // Write bass stem (mono → stereo: L=bass, R=bass)
        for i in 0..<frameCount {
            interleaved[i * 2] = bass[i]
            interleaved[i * 2 + 1] = bass[i]
        }
        bassBuffer.write(interleaved, count: sampleCount)

        // Write vocal stem (mono → stereo: L=vocal, R=vocal)
        for i in 0..<frameCount {
            interleaved[i * 2] = mid[i]
            interleaved[i * 2 + 1] = mid[i]
        }
        vocalBuffer.write(interleaved, count: sampleCount)

        // Write instrument/atmosphere stem (stereo: L=side, R=-side)
        for i in 0..<frameCount {
            interleaved[i * 2] = side[i]
            interleaved[i * 2 + 1] = -side[i]
        }
        instrumentBuffer.write(interleaved, count: sampleCount)
    }

    // MARK: - Side Signal Delay

    private func feedSideDelay(side: UnsafePointer<Float>, frameCount: Int) {
        guard let delay = sideDelayLine else { return }
        for i in 0..<frameCount {
            delay[sideDelayWritePos] = side[i]
            sideDelayWritePos = (sideDelayWritePos + 1) % sideDelayLength
        }
    }

    private func readDelayedSide(into output: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard let delay = sideDelayLine else {
            output.initialize(repeating: 0, count: frameCount)
            return
        }
        // Read from the oldest position in the delay line
        var readPos = (sideDelayWritePos - frameCount + sideDelayLength * 2) % sideDelayLength
        for i in 0..<frameCount {
            output[i] = delay[readPos]
            readPos = (readPos + 1) % sideDelayLength
        }
    }

    // MARK: - Transient Sharpening

    /// Apply envelope-following transient boost to drum stem
    private func applyTransientSharpening(buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        let attack: Float = 0.01
        let release: Float = 0.995
        let boostDB: Float = 3.5
        let boostLinear = powf(10.0, boostDB / 20.0)

        for i in 0..<frameCount {
            let absSample = abs(buffer[i])
            // Envelope follower
            if absSample > drumEnvelope {
                drumEnvelope = attack * absSample + (1.0 - attack) * drumEnvelope
            } else {
                drumEnvelope = release * drumEnvelope
            }
            // Boost transients above envelope
            if absSample > drumEnvelope * 1.5 {
                buffer[i] *= boostLinear
            }
        }
    }

    // MARK: - Analysis Results

    /// Overall RMS level (for loudness normalization across tracks)
    var overallRMS: Double {
        guard analysisFrameCount > 0 else { return 0 }
        return sqrt((midRMSAccumulator + sideRMSAccumulator) / Double(analysisFrameCount))
    }

    /// A-weighted RMS — weights mid-frequency (vocal) energy 2× over full-mix RMS
    /// for better perceptual loudness matching
    var aWeightedRMS: Double {
        let fullRMS = overallRMS
        guard midFreqFrameCount > 0 else { return fullRMS }
        let vocalRMS = sqrt(midFreqRMSAccumulator / Double(midFreqFrameCount))
        // Blend: 2 parts vocal RMS + 1 part full RMS
        return (vocalRMS * 2.0 + fullRMS) / 3.0
    }

    /// Recent vocal RMS (rolling window average, ~2.5s)
    var recentVocalRMS: Double {
        guard vocalWindowCount > 0, let window = vocalRMSWindow else { return 0 }
        var sum: Float = 0
        for i in 0..<vocalWindowCount {
            sum += window[i]
        }
        return Double(sum) / Double(vocalWindowCount)
    }

    /// Long-term average vocal RMS
    var averageVocalRMS: Double {
        guard vocalRMSLongFrameCount > 0 else { return 0 }
        return sqrt(vocalRMSLongAccumulator / Double(vocalRMSLongFrameCount))
    }

    /// Whether vocals have dropped significantly (outro/instrumental section detected)
    var isVocalDropDetected: Bool {
        guard vocalWindowCount >= vocalWindowSize / 2 else { return false }
        let avg = averageVocalRMS
        guard avg > 0.001 else { return false }
        return recentVocalRMS < avg * 0.3
    }

    // MARK: - Drum+Bass Energy Results

    /// Recent drum+bass RMS (rolling window average, ~2.5s)
    var recentDrumBassEnergy: Double {
        guard drumBassWindowCount > 0, let window = drumBassEnergyWindow else { return 0 }
        var sum: Float = 0
        for i in 0..<drumBassWindowCount {
            sum += window[i]
        }
        return Double(sum) / Double(drumBassWindowCount)
    }

    /// Long-term average drum+bass energy
    var averageDrumBassEnergy: Double {
        guard drumBassEnergyLongFrameCount > 0 else { return 0 }
        return drumBassEnergyLongAccumulator / Double(drumBassEnergyLongFrameCount)
    }

    // MARK: - Key Detection

    /// Detected musical key from accumulated chroma profile
    var detectedKey: (key: Int, confidence: Float) {
        ChromaKeyDetector.detectKey(from: hpss.chromaProfile)
    }

    /// Compute the side/mid RMS ratio. Values < 0.05 indicate mono content.
    var sideMidRatio: Double {
        guard analysisFrameCount > 0, midRMSAccumulator > 0 else { return 0 }
        let midRMS = sqrt(midRMSAccumulator / Double(analysisFrameCount))
        let sideRMS = sqrt(sideRMSAccumulator / Double(analysisFrameCount))
        return sideRMS / max(midRMS, 1e-10)
    }

    /// Reset analysis accumulators
    func resetAnalysis() {
        midRMSAccumulator = 0
        sideRMSAccumulator = 0
        analysisFrameCount = 0
        midFreqRMSAccumulator = 0
        midFreqFrameCount = 0
    }

    /// Reset filter state (call when switching tracks)
    func resetFilters() {
        bassFilter.reset()
        bassFilter2.reset()
        hpss.reset()
        beatTracker.reset()
        sideDelayWritePos = 0
        sideDelayLine?.initialize(repeating: 0, count: sideDelayLength)
        drumEnvelope = 0
        vocalWidthBloom = 0
        vocalReverbMix = 0
        reverb.reset()
        vocalWindowWritePos = 0
        vocalWindowCount = 0
        vocalRMSWindow?.initialize(repeating: 0, count: vocalWindowSize)
        vocalRMSLongAccumulator = 0
        vocalRMSLongFrameCount = 0
        drumBassWindowWritePos = 0
        drumBassWindowCount = 0
        drumBassEnergyWindow?.initialize(repeating: 0, count: drumBassWindowSize)
        drumBassEnergyLongAccumulator = 0
        drumBassEnergyLongFrameCount = 0
        resetAnalysis()
    }

    // MARK: - Private

    private func ensureBuffers(frameCount: Int) {
        guard frameCount > scratchCapacity else { return }

        midBuffer?.deallocate()
        sideBuffer?.deallocate()
        bassSignal?.deallocate()
        interleavedOut?.deallocate()

        midBuffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        sideBuffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        bassSignal = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        interleavedOut = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        scratchCapacity = frameCount
    }

    private func ensureHPSSBuffers(capacity: Int) {
        guard capacity > hpssCapacity else { return }

        harmonicAccum?.deallocate()
        percussiveAccum?.deallocate()

        harmonicAccum = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        percussiveAccum = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        hpssCapacity = capacity
    }
}
