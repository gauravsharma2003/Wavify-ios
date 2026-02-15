//
//  SchroederReverb.swift
//  Wavify
//
//  Schroeder reverb (4 parallel comb + 2 series allpass) for vocal dissolution.
//  Applied to outgoing vocals during crossfade — wet/dry inversely tied to vocal fade.
//  BPM-adaptive decay prevents smearing across beats. ~27KB pre-allocated memory.
//

import Foundation

final class SchroederReverb {

    // 4 parallel comb filters at prime-number delay lengths (samples @ 44100Hz)
    private let combDelays = [1557, 1617, 1491, 1422]
    private var combBuffers: [UnsafeMutablePointer<Float>]
    private var combWritePos: [Int] = [0, 0, 0, 0]
    private var combFeedback: Float = 0.84  // ~1.2s decay

    // 2 series allpass filters for diffusion
    private let allpassDelays = [225, 556]
    private var allpassBuffers: [UnsafeMutablePointer<Float>]
    private var allpassWritePos: [Int] = [0, 0]
    private let allpassGain: Float = 0.5

    init() {
        // Allocate comb buffers
        combBuffers = combDelays.map { delay in
            let buf = UnsafeMutablePointer<Float>.allocate(capacity: delay)
            buf.initialize(repeating: 0, count: delay)
            return buf
        }

        // Allocate allpass buffers
        allpassBuffers = allpassDelays.map { delay in
            let buf = UnsafeMutablePointer<Float>.allocate(capacity: delay)
            buf.initialize(repeating: 0, count: delay)
            return buf
        }
    }

    deinit {
        for (i, delay) in combDelays.enumerated() {
            _ = delay
            combBuffers[i].deallocate()
        }
        for (i, delay) in allpassDelays.enumerated() {
            _ = delay
            allpassBuffers[i].deallocate()
        }
    }

    /// Process a single sample through the reverb. Zero-allocation.
    func process(_ input: Float) -> Float {
        // 4 parallel comb filters
        var combSum: Float = 0
        for i in 0..<4 {
            let buf = combBuffers[i]
            let delay = combDelays[i]
            let readPos = combWritePos[i]
            let delayed = buf[readPos]
            let newSample = input + delayed * combFeedback
            buf[readPos] = newSample
            combWritePos[i] = (readPos + 1) % delay
            combSum += delayed
        }
        combSum *= 0.25

        // 2 series allpass filters for diffusion
        var output = combSum
        for i in 0..<2 {
            let buf = allpassBuffers[i]
            let delay = allpassDelays[i]
            let readPos = allpassWritePos[i]
            let delayed = buf[readPos]
            let newSample = output + delayed * allpassGain
            buf[readPos] = newSample
            output = delayed - output * allpassGain
            allpassWritePos[i] = (readPos + 1) % delay
        }

        return output
    }

    /// Set decay time in seconds. Adjusts comb feedback: g = exp(-3 * avgDelay / (T * sampleRate))
    func setDecayTime(_ seconds: Float) {
        let avgDelay: Float = 1521.75  // average of combDelays
        let sampleRate: Float = 44100.0
        let g = expf(-3.0 * avgDelay / (max(seconds, 0.1) * sampleRate))
        combFeedback = min(0.95, max(0.5, g))
    }

    /// Reset all delay lines to silence
    func reset() {
        for i in 0..<4 {
            combBuffers[i].initialize(repeating: 0, count: combDelays[i])
            combWritePos[i] = 0
        }
        for i in 0..<2 {
            allpassBuffers[i].initialize(repeating: 0, count: allpassDelays[i])
            allpassWritePos[i] = 0
        }
        combFeedback = 0.84
    }
}
