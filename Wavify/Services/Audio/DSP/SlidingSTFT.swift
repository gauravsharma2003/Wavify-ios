//
//  SlidingSTFT.swift
//  Wavify
//
//  Real-time STFT + Harmonic-Percussive Source Separation (HPSS).
//  Operates on mono (mid) signal, producing harmonic and percussive outputs hop-by-hop.
//
//  Architecture:
//    fftSize=2048, hopSize=512 → ~11.6ms per hop at 44100Hz
//    medianLength=17 frames → ~200ms temporal window
//    Latency: (17/2) × 512 = 4096 samples ≈ 93ms
//
//  Pipeline per hop:
//    1. Hann window → Forward FFT
//    2. Magnitude + phase extraction
//    3. Ring buffer of 17 magnitude frames
//    4. Horizontal median (time) → harmonic magnitude
//    5. Vertical median (frequency, adaptive length) → percussive magnitude
//    6. Wiener soft masks: H²/(H²+P²), P²/(H²+P²)
//    7. Apply masks → Inverse FFT × 2 → Overlap-add synthesis
//

import Foundation
import Accelerate

final class SlidingSTFT {

    // MARK: - Constants

    let fftSize: Int = 2048
    let hopSize: Int = 512
    let numBins: Int = 1025          // fftSize/2 + 1
    let medianLength: Int = 17

    /// HPSS latency in samples: (medianLength/2) × hopSize
    var latencySamples: Int { (medianLength / 2) * hopSize }

    // MARK: - FFT Setup

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    // MARK: - Pre-allocated Buffers

    // Hann window (computed once at init)
    private let hannWindow: UnsafeMutablePointer<Float>

    // Input accumulation
    private let inputAccum: UnsafeMutablePointer<Float>      // fftSize samples
    private var inputAccumCount: Int = 0

    // FFT workspace (split complex)
    private let fftRealPart: UnsafeMutablePointer<Float>     // fftSize/2
    private let fftImagPart: UnsafeMutablePointer<Float>     // fftSize/2

    // Magnitude + phase of current frame
    private let magnitude: UnsafeMutablePointer<Float>       // numBins
    private let phase: UnsafeMutablePointer<Float>           // numBins

    // Magnitude history ring buffer: medianLength × numBins
    private let magHistory: UnsafeMutablePointer<Float>
    private var historyWritePos: Int = 0
    private var historyCount: Int = 0

    // Median scratch buffers
    private let medianScratch: UnsafeMutablePointer<Float>   // medianLength

    // Harmonic + percussive magnitudes
    private let harmonicMag: UnsafeMutablePointer<Float>     // numBins
    private let percussiveMag: UnsafeMutablePointer<Float>   // numBins

    // Wiener masks
    private let hMask: UnsafeMutablePointer<Float>           // numBins
    private let pMask: UnsafeMutablePointer<Float>           // numBins

    // Masked complex spectra (split complex for IFFT)
    private let hReal: UnsafeMutablePointer<Float>           // fftSize/2
    private let hImag: UnsafeMutablePointer<Float>           // fftSize/2
    private let pReal: UnsafeMutablePointer<Float>           // fftSize/2
    private let pImag: UnsafeMutablePointer<Float>           // fftSize/2

    // IFFT time-domain output (before overlap-add)
    private let hTimeDomain: UnsafeMutablePointer<Float>     // fftSize
    private let pTimeDomain: UnsafeMutablePointer<Float>     // fftSize

    // Overlap-add buffers (fftSize samples each, accumulate across hops)
    private let harmonicOLA: UnsafeMutablePointer<Float>     // fftSize
    private let percussiveOLA: UnsafeMutablePointer<Float>   // fftSize

    // Output buffers (hopSize samples each, ready for pull)
    private let harmonicOut: UnsafeMutablePointer<Float>     // hopSize
    private let percussiveOut: UnsafeMutablePointer<Float>   // hopSize
    private var outputReady: Bool = false

    // Synthesis window for overlap-add normalization
    private let synthesisNorm: UnsafeMutablePointer<Float>   // fftSize

    // Previous magnitude for spectral flux
    private let prevMagnitude: UnsafeMutablePointer<Float>   // numBins

    // MARK: - Chromagram Accumulation

    /// 12-bin chroma accumulator (C through B), accumulated across hops
    private let chromaAccumulator: UnsafeMutablePointer<Float>  // 12 bins
    private var chromaHopCount: Int = 0

    // MARK: - Adaptive Vertical Median Regions

    // Bin boundaries for adaptive vertical median lengths
    // Bass: 0–250Hz → bins 0–11, verticalLength=5
    // Mid: 250Hz–4kHz → bins 12–186, verticalLength=17
    // High: 4kHz+ → bins 187–1024, verticalLength=23
    private let bassEndBin: Int = 12
    private let midEndBin: Int = 187
    private let verticalLengthBass: Int = 5
    private let verticalLengthMid: Int = 17
    private let verticalLengthHigh: Int = 23

    // MARK: - State

    /// Whether enough history has accumulated for HPSS
    var isWarmedUp: Bool { historyCount >= medianLength }

    /// Spectral flux of the most recent hop (onset detection, free byproduct)
    private(set) var lastSpectralFlux: Float = 0

    /// Normalized 12-element chroma profile (sum = 1.0)
    var chromaProfile: [Float] {
        guard chromaHopCount > 0 else { return [Float](repeating: 0, count: 12) }
        var result = [Float](repeating: 0, count: 12)
        var sum: Float = 0
        for i in 0..<12 {
            result[i] = chromaAccumulator[i]
            sum += result[i]
        }
        if sum > 0 {
            for i in 0..<12 { result[i] /= sum }
        }
        return result
    }

    // MARK: - Init / Deinit

    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        let half = fftSize / 2

        // Allocate all buffers
        hannWindow = .allocate(capacity: fftSize)
        inputAccum = .allocate(capacity: fftSize)
        fftRealPart = .allocate(capacity: half)
        fftImagPart = .allocate(capacity: half)
        magnitude = .allocate(capacity: numBins)
        phase = .allocate(capacity: numBins)
        magHistory = .allocate(capacity: medianLength * numBins)
        medianScratch = .allocate(capacity: max(medianLength, verticalLengthHigh))
        harmonicMag = .allocate(capacity: numBins)
        percussiveMag = .allocate(capacity: numBins)
        hMask = .allocate(capacity: numBins)
        pMask = .allocate(capacity: numBins)
        hReal = .allocate(capacity: half)
        hImag = .allocate(capacity: half)
        pReal = .allocate(capacity: half)
        pImag = .allocate(capacity: half)
        hTimeDomain = .allocate(capacity: fftSize)
        pTimeDomain = .allocate(capacity: fftSize)
        harmonicOLA = .allocate(capacity: fftSize)
        percussiveOLA = .allocate(capacity: fftSize)
        harmonicOut = .allocate(capacity: hopSize)
        percussiveOut = .allocate(capacity: hopSize)
        synthesisNorm = .allocate(capacity: fftSize)
        prevMagnitude = .allocate(capacity: numBins)
        chromaAccumulator = .allocate(capacity: 12)

        // Zero out all buffers
        inputAccum.initialize(repeating: 0, count: fftSize)
        magHistory.initialize(repeating: 0, count: medianLength * numBins)
        harmonicOLA.initialize(repeating: 0, count: fftSize)
        percussiveOLA.initialize(repeating: 0, count: fftSize)
        harmonicOut.initialize(repeating: 0, count: hopSize)
        percussiveOut.initialize(repeating: 0, count: hopSize)
        prevMagnitude.initialize(repeating: 0, count: numBins)
        chromaAccumulator.initialize(repeating: 0, count: 12)

        // Compute Hann window
        vDSP_hann_window(hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // Compute synthesis normalization: sum of squared windows at each position
        // For Hann window with 75% overlap (hopSize = fftSize/4), the sum is constant
        // With our 50% overlap we need to normalize by the sum of squared windows
        computeSynthesisNorm()
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        hannWindow.deallocate()
        inputAccum.deallocate()
        fftRealPart.deallocate()
        fftImagPart.deallocate()
        magnitude.deallocate()
        phase.deallocate()
        magHistory.deallocate()
        medianScratch.deallocate()
        harmonicMag.deallocate()
        percussiveMag.deallocate()
        hMask.deallocate()
        pMask.deallocate()
        hReal.deallocate()
        hImag.deallocate()
        pReal.deallocate()
        pImag.deallocate()
        hTimeDomain.deallocate()
        pTimeDomain.deallocate()
        harmonicOLA.deallocate()
        percussiveOLA.deallocate()
        harmonicOut.deallocate()
        percussiveOut.deallocate()
        synthesisNorm.deallocate()
        prevMagnitude.deallocate()
        chromaAccumulator.deallocate()
    }

    // MARK: - Public API

    /// Feed mono samples. Returns the number of complete hops produced.
    func process(input: UnsafePointer<Float>, frameCount: Int) -> Int {
        var hopsProduced = 0
        var offset = 0

        while offset < frameCount {
            // How many samples we can still accept into the accumulator
            let remaining = hopSize - inputAccumCount
            let available = min(remaining, frameCount - offset)

            // Copy input into accumulator (shifting position)
            // The accumulator holds the latest fftSize samples but we only
            // need to fill hopSize new samples before processing
            memcpy(inputAccum.advanced(by: fftSize - hopSize + inputAccumCount),
                   input.advanced(by: offset),
                   available * MemoryLayout<Float>.size)
            inputAccumCount += available
            offset += available

            // Process when we have a full hop
            if inputAccumCount >= hopSize {
                processOneHop()
                hopsProduced += 1
                inputAccumCount = 0

                // Shift the accumulator: move last (fftSize - hopSize) samples to front
                memmove(inputAccum,
                        inputAccum.advanced(by: hopSize),
                        (fftSize - hopSize) * MemoryLayout<Float>.size)
            }
        }

        return hopsProduced
    }

    /// Pull harmonic output for the most recent hop (hopSize samples)
    func pullHarmonic(into buffer: UnsafeMutablePointer<Float>) {
        memcpy(buffer, harmonicOut, hopSize * MemoryLayout<Float>.size)
    }

    /// Pull percussive output for the most recent hop (hopSize samples)
    func pullPercussive(into buffer: UnsafeMutablePointer<Float>) {
        memcpy(buffer, percussiveOut, hopSize * MemoryLayout<Float>.size)
    }

    /// Reset all state
    func reset() {
        inputAccumCount = 0
        historyWritePos = 0
        historyCount = 0
        outputReady = false
        lastSpectralFlux = 0

        inputAccum.initialize(repeating: 0, count: fftSize)
        magHistory.initialize(repeating: 0, count: medianLength * numBins)
        harmonicOLA.initialize(repeating: 0, count: fftSize)
        percussiveOLA.initialize(repeating: 0, count: fftSize)
        harmonicOut.initialize(repeating: 0, count: hopSize)
        percussiveOut.initialize(repeating: 0, count: hopSize)
        prevMagnitude.initialize(repeating: 0, count: numBins)
        chromaAccumulator.initialize(repeating: 0, count: 12)
        chromaHopCount = 0
    }

    // MARK: - Core Processing

    private func processOneHop() {
        // 1. Apply Hann window to the accumulated fftSize samples
        let windowed = UnsafeMutablePointer<Float>.allocate(capacity: fftSize)
        defer { windowed.deallocate() }
        vDSP_vmul(inputAccum, 1, hannWindow, 1, windowed, 1, vDSP_Length(fftSize))

        // 2. Forward FFT (real-to-complex, packed format)
        let half = fftSize / 2
        var splitComplex = DSPSplitComplex(realp: fftRealPart, imagp: fftImagPart)

        // Convert real signal to split complex (even/odd interleave)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(half))
        }

        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // 3. Extract magnitude and phase for bins 0..<numBins
        //    Bin 0 (DC) and bin N/2 (Nyquist) are packed in real[0] and imag[0]
        //    For simplicity, we handle them specially.

        // DC component (bin 0)
        magnitude[0] = abs(fftRealPart[0])
        phase[0] = fftRealPart[0] >= 0 ? 0 : .pi

        // Nyquist component (bin numBins-1)
        magnitude[numBins - 1] = abs(fftImagPart[0])
        phase[numBins - 1] = fftImagPart[0] >= 0 ? 0 : .pi

        // Bins 1..<numBins-1 from split complex
        for k in 1..<(numBins - 1) {
            let re = fftRealPart[k]
            let im = fftImagPart[k]
            magnitude[k] = sqrtf(re * re + im * im)
            phase[k] = atan2f(im, re)
        }

        // 4. Compute spectral flux (half-wave rectified difference from previous frame)
        var flux: Float = 0
        for k in 0..<numBins {
            let diff = magnitude[k] - prevMagnitude[k]
            if diff > 0 { flux += diff }
        }
        lastSpectralFlux = flux
        memcpy(prevMagnitude, magnitude, numBins * MemoryLayout<Float>.size)

        // 4b. Accumulate chroma (fold magnitude bins into 12 pitch classes)
        for k in 0..<numBins {
            let freqHz = Float(k) * 44100.0 / Float(fftSize)
            guard freqHz >= 50 && freqHz <= 5000 else { continue }
            let midiNote = 12.0 * log2f(freqHz / 440.0) + 69.0
            let pitchClass = (Int(roundf(midiNote)) % 12 + 12) % 12
            chromaAccumulator[pitchClass] += magnitude[k]
        }
        chromaHopCount += 1

        // 5. Store magnitude in history ring buffer
        let historyOffset = historyWritePos * numBins
        memcpy(magHistory.advanced(by: historyOffset), magnitude, numBins * MemoryLayout<Float>.size)
        historyWritePos = (historyWritePos + 1) % medianLength
        if historyCount < medianLength { historyCount += 1 }

        // 6. HPSS: compute harmonic and percussive magnitudes
        if isWarmedUp {
            computeHPSS()
        } else {
            // Not enough history — pass through as harmonic (no percussion)
            memcpy(harmonicMag, magnitude, numBins * MemoryLayout<Float>.size)
            percussiveMag.initialize(repeating: 0, count: numBins)
        }

        // 7. Apply Wiener masks to original complex spectrum and IFFT

        // Reconstruct masked spectra for harmonic
        reconstructAndIFFT(maskedMag: harmonicMag,
                           phase: phase,
                           outputTime: hTimeDomain,
                           splitReal: hReal,
                           splitImag: hImag)

        // Reconstruct masked spectra for percussive
        reconstructAndIFFT(maskedMag: percussiveMag,
                           phase: phase,
                           outputTime: pTimeDomain,
                           splitReal: pReal,
                           splitImag: pImag)

        // 8. Apply synthesis window
        vDSP_vmul(hTimeDomain, 1, hannWindow, 1, hTimeDomain, 1, vDSP_Length(fftSize))
        vDSP_vmul(pTimeDomain, 1, hannWindow, 1, pTimeDomain, 1, vDSP_Length(fftSize))

        // 9. Overlap-add: shift existing OLA buffers left by hopSize, then add new frame
        // Shift left
        memmove(harmonicOLA,
                harmonicOLA.advanced(by: hopSize),
                (fftSize - hopSize) * MemoryLayout<Float>.size)
        // Zero the new region
        harmonicOLA.advanced(by: fftSize - hopSize).initialize(repeating: 0, count: hopSize)

        memmove(percussiveOLA,
                percussiveOLA.advanced(by: hopSize),
                (fftSize - hopSize) * MemoryLayout<Float>.size)
        percussiveOLA.advanced(by: fftSize - hopSize).initialize(repeating: 0, count: hopSize)

        // Add windowed IFFT output
        vDSP_vadd(harmonicOLA, 1, hTimeDomain, 1, harmonicOLA, 1, vDSP_Length(fftSize))
        vDSP_vadd(percussiveOLA, 1, pTimeDomain, 1, percussiveOLA, 1, vDSP_Length(fftSize))

        // 10. Output the first hopSize samples (normalized)
        for i in 0..<hopSize {
            let norm = synthesisNorm[i]
            harmonicOut[i] = norm > 1e-6 ? harmonicOLA[i] / norm : harmonicOLA[i]
            percussiveOut[i] = norm > 1e-6 ? percussiveOLA[i] / norm : percussiveOLA[i]
        }

        outputReady = true
    }

    // MARK: - HPSS Core

    private func computeHPSS() {
        let epsilon: Float = 1e-10

        for bin in 0..<numBins {
            // --- Horizontal median (across time frames) → harmonic ---
            // Gather this bin's magnitude across all history frames
            for t in 0..<medianLength {
                let idx = ((historyWritePos - medianLength + t + medianLength * 2) % medianLength) * numBins + bin
                medianScratch[t] = magHistory[idx]
            }
            harmonicMag[bin] = medianOfBuffer(medianScratch, count: medianLength)

            // --- Vertical median (across frequency bins) → percussive ---
            let vertLen: Int
            if bin < bassEndBin {
                vertLen = verticalLengthBass
            } else if bin < midEndBin {
                vertLen = verticalLengthMid
            } else {
                vertLen = verticalLengthHigh
            }

            let halfVert = vertLen / 2
            var vCount = 0
            for j in max(0, bin - halfVert)...min(numBins - 1, bin + halfVert) {
                medianScratch[vCount] = magnitude[j]
                vCount += 1
            }
            percussiveMag[bin] = medianOfBuffer(medianScratch, count: vCount)

            // --- Wiener soft masks ---
            let h2 = harmonicMag[bin] * harmonicMag[bin]
            let p2 = percussiveMag[bin] * percussiveMag[bin]
            let denom = h2 + p2 + epsilon
            hMask[bin] = h2 / denom
            pMask[bin] = p2 / denom

            // Apply masks to magnitude
            harmonicMag[bin] = magnitude[bin] * hMask[bin]
            percussiveMag[bin] = magnitude[bin] * pMask[bin]
        }
    }

    // MARK: - IFFT Reconstruction

    private func reconstructAndIFFT(
        maskedMag: UnsafePointer<Float>,
        phase: UnsafePointer<Float>,
        outputTime: UnsafeMutablePointer<Float>,
        splitReal: UnsafeMutablePointer<Float>,
        splitImag: UnsafeMutablePointer<Float>
    ) {
        let half = fftSize / 2

        // Reconstruct complex spectrum from magnitude + phase
        // DC bin
        splitReal[0] = maskedMag[0] * cosf(phase[0])
        // Nyquist packed in imag[0]
        splitImag[0] = maskedMag[numBins - 1] * cosf(phase[numBins - 1])

        for k in 1..<half {
            let mag = maskedMag[k]
            let ph = phase[k]
            splitReal[k] = mag * cosf(ph)
            splitImag[k] = mag * sinf(ph)
        }

        // Inverse FFT
        var splitComplex = DSPSplitComplex(realp: splitReal, imagp: splitImag)
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))

        // Convert split complex back to real signal
        outputTime.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
            vDSP_ztoc(&splitComplex, 1, complexPtr, 2, vDSP_Length(half))
        }

        // Scale by 1/(2*N) as required by vDSP FFT convention
        var scale = 1.0 / Float(fftSize * 2)
        vDSP_vsmul(outputTime, 1, &scale, outputTime, 1, vDSP_Length(fftSize))
    }

    // MARK: - Synthesis Normalization

    private func computeSynthesisNorm() {
        // Compute the sum of squared Hann windows at each position
        // for our overlap-add configuration (hopSize=512, fftSize=2048 → 4 overlapping windows)
        synthesisNorm.initialize(repeating: 0, count: fftSize)

        let numOverlaps = fftSize / hopSize  // 4 overlapping windows
        for overlap in 0..<numOverlaps {
            let shift = overlap * hopSize
            for i in 0..<fftSize {
                let windowIdx = (i + shift) % fftSize
                let w = hannWindow[windowIdx]
                // Only accumulate for the output region (first hopSize samples)
                if i < hopSize {
                    synthesisNorm[i] += w * w
                }
            }
        }

        // Ensure no division by zero
        for i in 0..<fftSize {
            if synthesisNorm[i] < 1e-6 { synthesisNorm[i] = 1.0 }
        }
    }

    // MARK: - Median Helper

    /// Compute the median of a buffer. Uses insertion sort for small N (≤23).
    private func medianOfBuffer(_ buffer: UnsafeMutablePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        if count == 1 { return buffer[0] }

        // In-place insertion sort (buffer is scratch, safe to mutate)
        for i in 1..<count {
            let key = buffer[i]
            var j = i - 1
            while j >= 0 && buffer[j] > key {
                buffer[j + 1] = buffer[j]
                j -= 1
            }
            buffer[j + 1] = key
        }

        return buffer[count / 2]
    }
}
