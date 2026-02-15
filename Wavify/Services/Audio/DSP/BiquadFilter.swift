//
//  BiquadFilter.swift
//  Wavify
//
//  Professional-grade biquad filter implementation for parametric EQ
//  Based on Robert Bristow-Johnson's Audio EQ Cookbook
//

import Foundation
import Accelerate

// MARK: - Biquad Coefficients

/// Normalized biquad filter coefficients
/// Transfer function: H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
struct BiquadCoefficients: Equatable {
    var b0: Double = 1.0
    var b1: Double = 0.0
    var b2: Double = 0.0
    var a1: Double = 0.0
    var a2: Double = 0.0
    
    /// Coefficients for bypass (unity gain, no filtering)
    static let bypass = BiquadCoefficients(b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)
    
    /// Check if this represents a bypass filter
    var isBypass: Bool {
        abs(b0 - 1.0) < 0.0001 &&
        abs(b1) < 0.0001 &&
        abs(b2) < 0.0001 &&
        abs(a1) < 0.0001 &&
        abs(a2) < 0.0001
    }
    
    /// Convert to Float array for single-precision processing
    var asFloatArray: [Float] {
        [Float(b0), Float(b1), Float(b2), Float(a1), Float(a2)]
    }
    
    /// Linear interpolation between coefficients for smooth transitions
    func interpolated(to target: BiquadCoefficients, factor: Double) -> BiquadCoefficients {
        BiquadCoefficients(
            b0: b0 + (target.b0 - b0) * factor,
            b1: b1 + (target.b1 - b1) * factor,
            b2: b2 + (target.b2 - b2) * factor,
            a1: a1 + (target.a1 - a1) * factor,
            a2: a2 + (target.a2 - a2) * factor
        )
    }
}

// MARK: - Coefficient Calculator

/// Calculates biquad filter coefficients for various EQ band types
enum BiquadCoefficientCalculator {
    
    /// Calculate coefficients for a parametric (peaking) EQ band
    static func peaking(frequency: Double, sampleRate: Double, gainDB: Double, q: Double = 1.0) -> BiquadCoefficients {
        guard abs(gainDB) > 0.01 else { return .bypass }
        
        // Clamp gain to prevent extreme values
        let clampedGain = max(-12.0, min(12.0, gainDB))
        
        let A = pow(10.0, clampedGain / 40.0)
        let w0 = 2.0 * .pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * q)
        
        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosW0
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha / A
        
        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
    
    /// Calculate coefficients for a low-shelf filter
    static func lowShelf(frequency: Double, sampleRate: Double, gainDB: Double, q: Double = 0.707) -> BiquadCoefficients {
        guard abs(gainDB) > 0.01 else { return .bypass }
        
        let clampedGain = max(-12.0, min(12.0, gainDB))
        
        let A = pow(10.0, clampedGain / 40.0)
        let w0 = 2.0 * .pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * q)
        let sqrtA = sqrt(A)
        let twoSqrtAAlpha = 2.0 * sqrtA * alpha
        
        let b0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha)
        let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0)
        let b2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha)
        let a0 = (A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha
        let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0)
        let a2 = (A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha
        
        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
    
    /// Calculate coefficients for a high-shelf filter
    static func highShelf(frequency: Double, sampleRate: Double, gainDB: Double, q: Double = 0.707) -> BiquadCoefficients {
        guard abs(gainDB) > 0.01 else { return .bypass }
        
        let clampedGain = max(-12.0, min(12.0, gainDB))
        
        let A = pow(10.0, clampedGain / 40.0)
        let w0 = 2.0 * .pi * frequency / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * q)
        let sqrtA = sqrt(A)
        let twoSqrtAAlpha = 2.0 * sqrtA * alpha
        
        let b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha)
        let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0)
        let b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha)
        let a0 = (A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha
        let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0)
        let a2 = (A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha
        
        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
    
    /// Calculate coefficients for a low-pass filter (Butterworth when Q = 0.7071)
    /// Used by StemDecomposer for bass isolation
    static func lowPass(cutoff: Double, sampleRate: Double, q: Double = 0.7071) -> BiquadCoefficients {
        let w0 = 2.0 * .pi * cutoff / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * q)

        let b1 = 1.0 - cosW0
        let b0 = b1 / 2.0
        let b2 = b0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha

        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }

    /// Calculate coefficients for a 10-band EQ
    static func calculateEQCoefficients(
        bands: [(frequency: Float, gain: Float)],
        sampleRate: Double
    ) -> [BiquadCoefficients] {
        bands.enumerated().map { index, band in
            let frequency = Double(band.frequency)
            let gainDB = Double(band.gain)
            
            switch index {
            case 0:  // 32 Hz - Low shelf
                return lowShelf(frequency: frequency, sampleRate: sampleRate, gainDB: gainDB, q: 0.6)
            case 1:  // 64 Hz - Low shelf (gentler)
                return lowShelf(frequency: frequency, sampleRate: sampleRate, gainDB: gainDB, q: 0.707)
            case 8:  // 8 kHz - High shelf (gentler)
                return highShelf(frequency: frequency, sampleRate: sampleRate, gainDB: gainDB, q: 0.707)
            case 9:  // 16 kHz - High shelf
                return highShelf(frequency: frequency, sampleRate: sampleRate, gainDB: gainDB, q: 0.6)
            default: // Mid bands - Peaking EQ
                return peaking(frequency: frequency, sampleRate: sampleRate, gainDB: gainDB, q: 1.2)
            }
        }
    }
}

// MARK: - Single Biquad Filter

/// A single biquad filter with state for stereo processing
final class BiquadFilter {
    // Filter state (delay lines) for left and right channels
    private var z1L: Float = 0
    private var z2L: Float = 0
    private var z1R: Float = 0
    private var z2R: Float = 0
    
    // Current and target coefficients for smooth transitions
    private var currentCoeffs: BiquadCoefficients = .bypass
    private var targetCoeffs: BiquadCoefficients = .bypass
    private var interpolationProgress: Float = 1.0
    
    // Denormal prevention constant
    private let denormalPrevention: Float = 1.0e-25
    
    /// Update target coefficients (will interpolate smoothly)
    func setCoefficients(_ coeffs: BiquadCoefficients) {
        if targetCoeffs != coeffs {
            targetCoeffs = coeffs
            interpolationProgress = 0.0
        }
    }
    
    /// Reset filter state
    func reset() {
        z1L = 0; z2L = 0
        z1R = 0; z2R = 0
        currentCoeffs = targetCoeffs
        interpolationProgress = 1.0
    }
    
    /// Process a mono buffer in-place (used by StemDecomposer for mid/side signals)
    func processMono(buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        if currentCoeffs.isBypass && targetCoeffs.isBypass { return }

        let interpStep: Float = 0.002

        for i in 0..<frameCount {
            if interpolationProgress < 1.0 {
                interpolationProgress = min(1.0, interpolationProgress + interpStep)
                currentCoeffs = currentCoeffs.interpolated(
                    to: targetCoeffs,
                    factor: Double(interpolationProgress)
                )
            }

            let b0 = Float(currentCoeffs.b0)
            let b1 = Float(currentCoeffs.b1)
            let b2 = Float(currentCoeffs.b2)
            let a1 = Float(currentCoeffs.a1)
            let a2 = Float(currentCoeffs.a2)

            let input = buffer[i]
            let output = b0 * input + z1L
            z1L = b1 * input - a1 * output + z2L + denormalPrevention
            z2L = b2 * input - a2 * output
            buffer[i] = output
        }

        if abs(z1L) < 1.0e-15 { z1L = 0 }
        if abs(z2L) < 1.0e-15 { z2L = 0 }
    }

    /// Process interleaved stereo buffer in-place
    func process(buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        // Skip if bypass
        if currentCoeffs.isBypass && targetCoeffs.isBypass {
            return
        }
        
        // Interpolation step per sample (smooth over ~10ms at 44.1kHz)
        let interpStep: Float = 0.002
        
        for i in 0..<frameCount {
            // Update coefficient interpolation
            if interpolationProgress < 1.0 {
                interpolationProgress = min(1.0, interpolationProgress + interpStep)
                currentCoeffs = currentCoeffs.interpolated(
                    to: targetCoeffs,
                    factor: Double(interpolationProgress)
                )
            }
            
            let b0 = Float(currentCoeffs.b0)
            let b1 = Float(currentCoeffs.b1)
            let b2 = Float(currentCoeffs.b2)
            let a1 = Float(currentCoeffs.a1)
            let a2 = Float(currentCoeffs.a2)
            
            // Left channel (even index)
            let leftIdx = i * 2
            let inputL = buffer[leftIdx]
            let outputL = b0 * inputL + z1L
            z1L = b1 * inputL - a1 * outputL + z2L + denormalPrevention
            z2L = b2 * inputL - a2 * outputL
            buffer[leftIdx] = outputL
            
            // Right channel (odd index)
            let rightIdx = i * 2 + 1
            let inputR = buffer[rightIdx]
            let outputR = b0 * inputR + z1R
            z1R = b1 * inputR - a1 * outputR + z2R + denormalPrevention
            z2R = b2 * inputR - a2 * outputR
            buffer[rightIdx] = outputR
        }
        
        // Flush denormals from state
        if abs(z1L) < 1.0e-15 { z1L = 0 }
        if abs(z2L) < 1.0e-15 { z2L = 0 }
        if abs(z1R) < 1.0e-15 { z1R = 0 }
        if abs(z2R) < 1.0e-15 { z2R = 0 }
    }
}

// MARK: - 10-Band EQ Processor

/// Complete 10-band equalizer processor with smooth transitions
final class TenBandEQProcessor {
    /// Individual filters for each band
    private var filters: [BiquadFilter]
    
    /// Output gain (for headroom management)
    private var outputGain: Float = 1.0
    private var targetOutputGain: Float = 1.0
    
    /// Lock for thread-safe updates
    private let lock = NSLock()
    
    init() {
        filters = (0..<10).map { _ in BiquadFilter() }
    }
    
    /// Update EQ coefficients with automatic gain compensation
    func updateCoefficients(_ newCoefficients: [BiquadCoefficients], gains: [Float] = []) {
        guard newCoefficients.count == 10 else { return }
        
        // Calculate output gain reduction based on total positive gain
        var newOutputGain: Float = 1.0
        if !gains.isEmpty {
            // Sum of positive gains gives worst-case cumulative boost
            let totalPositiveGain = gains.filter { $0 > 0 }.reduce(0, +)
            if totalPositiveGain > 0 {
                // Reduce output by ~60% of total positive gain (conservative)
                let reductionDB = totalPositiveGain * 0.6
                newOutputGain = pow(10.0, -reductionDB / 20.0)
            }
        }
        
        lock.lock()
        for (index, coeffs) in newCoefficients.enumerated() {
            filters[index].setCoefficients(coeffs)
        }
        targetOutputGain = max(0.3, min(1.0, newOutputGain)) // Clamp between -10dB and 0dB
        lock.unlock()
    }
    
    /// Process audio buffer through all EQ bands
    func process(buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        let totalSamples = frameCount * 2
        
        // Get current target output gain
        lock.lock()
        let targetGain = targetOutputGain
        lock.unlock()
        
        // Smooth output gain changes
        let gainStep: Float = 0.0005
        
        // Process through all 10 filters
        for filter in filters {
            filter.process(buffer: buffer, frameCount: frameCount)
        }
        
        // Apply output gain with smoothing and soft limiting
        for i in 0..<totalSamples {
            // Smooth gain transition
            if outputGain < targetGain {
                outputGain = min(targetGain, outputGain + gainStep)
            } else if outputGain > targetGain {
                outputGain = max(targetGain, outputGain - gainStep)
            }
            
            // Apply gain
            var sample = buffer[i] * outputGain
            
            // Soft saturation (gentle compression starting at -3dB)
            let threshold: Float = 0.707
            let absSample = abs(sample)
            if absSample > threshold {
                let sign: Float = sample >= 0 ? 1 : -1
                let excess = absSample - threshold
                // Soft knee using sqrt for gentle saturation
                sample = sign * (threshold + (1.0 - threshold) * (1.0 - 1.0 / (1.0 + excess * 2.0)))
            }
            
            // Final safety clamp
            buffer[i] = max(-0.99, min(0.99, sample))
        }
    }
    
    /// Reset all filter states
    func reset() {
        lock.lock()
        for filter in filters {
            filter.reset()
        }
        outputGain = targetOutputGain
        lock.unlock()
    }
}
