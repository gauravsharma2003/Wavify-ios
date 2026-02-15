//
//  StemDecomposer.swift
//  Wavify
//
//  Real-time stem decomposition using mid-side analysis + biquad filtering.
//  Decomposes stereo audio into three stems: bass, vocals, instruments.
//
//  Mid = (L + R) / 2  →  center-panned content (vocals, bass, kick)
//  Side = (L - R) / 2  →  wide-panned content (guitars, synths, reverb)
//
//  Bass: low-pass filter on mid signal (< 250Hz)
//  Vocals: mid minus bass (250Hz+ center content)
//  Instruments: side signal (wide stereo content)
//

import Foundation
import Accelerate

final class StemDecomposer {

    // MARK: - Ring Buffer Targets

    /// Bass stem output (interleaved stereo: mono bass written as L=mid, R=mid)
    let bassBuffer: CircularBuffer
    /// Vocal stem output (interleaved stereo: mono vocal written as L=mid, R=mid)
    let vocalBuffer: CircularBuffer
    /// Instrument stem output (interleaved stereo: L=side, R=-side)
    let instrumentBuffer: CircularBuffer

    /// Also write full mix to the normal ring buffer (for analysis/fallback)
    let fullMixBuffer: CircularBuffer?

    // MARK: - DSP

    /// Low-pass filter at 250Hz for bass isolation (owns filter state)
    private let bassFilter = BiquadFilter()

    // MARK: - Pre-allocated Scratch Buffers

    private var midBuffer: UnsafeMutablePointer<Float>?
    private var sideBuffer: UnsafeMutablePointer<Float>?
    private var bassSignal: UnsafeMutablePointer<Float>?
    private var interleavedOut: UnsafeMutablePointer<Float>?
    private var scratchCapacity: Int = 0

    // MARK: - Analysis

    /// Running RMS accumulators for mono detection
    private(set) var midRMSAccumulator: Double = 0
    private(set) var sideRMSAccumulator: Double = 0
    private(set) var analysisFrameCount: Int = 0

    // MARK: - Init

    init(bassBuffer: CircularBuffer,
         vocalBuffer: CircularBuffer,
         instrumentBuffer: CircularBuffer,
         fullMixBuffer: CircularBuffer? = nil,
         sampleRate: Double = 44100) {
        self.bassBuffer = bassBuffer
        self.vocalBuffer = vocalBuffer
        self.instrumentBuffer = instrumentBuffer
        self.fullMixBuffer = fullMixBuffer

        // Configure low-pass at 250Hz (Butterworth)
        let coeffs = BiquadCoefficientCalculator.lowPass(cutoff: 250, sampleRate: sampleRate)
        bassFilter.setCoefficients(coeffs)
        // Force immediate application (no interpolation from bypass)
        bassFilter.reset()
    }

    deinit {
        midBuffer?.deallocate()
        sideBuffer?.deallocate()
        bassSignal?.deallocate()
        interleavedOut?.deallocate()
    }

    // MARK: - Decompose

    /// Decompose planar stereo audio into 3 stems and write to ring buffers.
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

        // 3. Bass isolation: low-pass filter on mid signal
        //    Copy mid → bass, then filter in place
        memcpy(bass, mid, frameCount * MemoryLayout<Float>.size)
        bassFilter.processMono(buffer: bass, frameCount: frameCount)

        // 4. Vocals: mid - bass (center content above 250Hz)
        //    Reuse mid buffer: mid = mid - bass
        var negOne: Float = -1.0
        vDSP_vsma(bass, 1, &negOne, mid, 1, mid, 1, vDSP_Length(frameCount))

        // 5. Write bass stem (mono → stereo: L=bass, R=bass)
        let sampleCount = frameCount * 2
        for i in 0..<frameCount {
            interleaved[i * 2] = bass[i]
            interleaved[i * 2 + 1] = bass[i]
        }
        bassBuffer.write(interleaved, count: sampleCount)

        // 6. Write vocal stem (mono → stereo: L=vocal, R=vocal)
        for i in 0..<frameCount {
            interleaved[i * 2] = mid[i]       // mid now contains vocals (mid - bass)
            interleaved[i * 2 + 1] = mid[i]
        }
        vocalBuffer.write(interleaved, count: sampleCount)

        // 7. Write instrument stem (stereo: L=side, R=-side)
        for i in 0..<frameCount {
            interleaved[i * 2] = side[i]
            interleaved[i * 2 + 1] = -side[i]
        }
        instrumentBuffer.write(interleaved, count: sampleCount)

        // 8. Optionally write full mix to normal ring buffer (for non-stem path)
        if let fullMix = fullMixBuffer {
            for i in 0..<frameCount {
                interleaved[i * 2] = left[i]
                interleaved[i * 2 + 1] = right[i]
            }
            fullMix.write(interleaved, count: sampleCount)
        }
    }

    // MARK: - Analysis Results

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
    }

    /// Reset filter state (call when switching tracks)
    func resetFilters() {
        bassFilter.reset()
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
}
