//
//  BeatTracker.swift
//  Wavify
//
//  Lightweight, allocation-free beat tracker for the real-time audio thread.
//  Consumes spectral flux from SlidingSTFT and estimates BPM + beat/downbeat positions.
//
//  Algorithm:
//    1. Adaptive threshold: running median of flux × 1.5
//    2. Peak-pick onsets with minimum inter-onset interval (~104ms)
//    3. IOI histogram (inter-onset intervals) mapped to BPM bins (60-260)
//    4. Beat period from histogram peak, downbeat every 4 beats
//
//  Memory: ~3KB total (all pre-allocated, no heap allocation after init)
//

import Foundation

final class BeatTracker {

    // MARK: - Constants

    /// Hop duration in seconds (512 samples at 44100Hz)
    private let hopDuration: Double = 512.0 / 44100.0  // ~11.6ms

    /// Minimum hops between onsets (~104ms, prevents double-triggering)
    private let minOnsetInterval: Int = 9

    // Ring buffer sizes
    private let fluxHistorySize = 64       // ~743ms of flux history
    private let onsetHistorySize = 128     // onset time tracking
    private let ioiHistogramSize = 200     // BPM bins 60-260

    /// Minimum BPM for histogram mapping
    private let minBPM: Double = 60.0
    /// Maximum BPM for histogram mapping
    private let maxBPM: Double = 260.0

    // MARK: - Pre-allocated Buffers

    /// Flux history ring buffer for adaptive threshold
    private let fluxHistory: UnsafeMutablePointer<Float>
    private var fluxWritePos: Int = 0
    private var fluxCount: Int = 0

    /// Scratch buffer for insertion-sort median computation
    private let medianScratch: UnsafeMutablePointer<Float>

    /// Onset hop indices ring buffer
    private let onsetHops: UnsafeMutablePointer<Int>
    private var onsetWritePos: Int = 0
    private var onsetCount: Int = 0

    /// IOI histogram: bins map to BPM range 60-260
    private let ioiHistogram: UnsafeMutablePointer<Int>

    // MARK: - State

    /// Current hop index (incremented each feedFlux call)
    private var currentHop: Int = 0

    /// Hop index of the last detected onset
    private var lastOnsetHop: Int = -100

    /// Beat phase counter (0-3, wraps at downbeat)
    private var beatPhaseCounter: Int = 0

    /// Hop index of the last tracked beat
    private var lastBeatHop: Int = 0

    /// Cached BPM estimate
    private var cachedBPM: Float = 0
    private var cachedBeatPeriodHops: Double = 0

    // MARK: - Init / Deinit

    init() {
        fluxHistory = .allocate(capacity: fluxHistorySize)
        fluxHistory.initialize(repeating: 0, count: fluxHistorySize)

        medianScratch = .allocate(capacity: fluxHistorySize)
        medianScratch.initialize(repeating: 0, count: fluxHistorySize)

        onsetHops = .allocate(capacity: onsetHistorySize)
        onsetHops.initialize(repeating: 0, count: onsetHistorySize)

        ioiHistogram = .allocate(capacity: ioiHistogramSize)
        ioiHistogram.initialize(repeating: 0, count: ioiHistogramSize)
    }

    deinit {
        fluxHistory.deallocate()
        medianScratch.deallocate()
        onsetHops.deallocate()
        ioiHistogram.deallocate()
    }

    // MARK: - Public API

    /// Feed one spectral flux value (call once per HPSS hop, ~11.6ms)
    func feedFlux(_ flux: Float) {
        // Store flux in ring buffer
        fluxHistory[fluxWritePos] = flux
        fluxWritePos = (fluxWritePos + 1) % fluxHistorySize
        if fluxCount < fluxHistorySize { fluxCount += 1 }

        // Compute adaptive threshold via running median
        let threshold = computeMedianFlux() * 1.5

        // Peak-pick: flux exceeds threshold and minimum interval since last onset
        let hopsSinceLastOnset = currentHop - lastOnsetHop
        if flux > threshold && hopsSinceLastOnset >= minOnsetInterval && fluxCount >= 4 {
            // Record onset
            let prevOnsetHop = lastOnsetHop
            lastOnsetHop = currentHop

            onsetHops[onsetWritePos] = currentHop
            onsetWritePos = (onsetWritePos + 1) % onsetHistorySize
            if onsetCount < onsetHistorySize { onsetCount += 1 }

            // Compute IOI and update histogram
            if prevOnsetHop >= 0 {
                let ioiHops = currentHop - prevOnsetHop
                let ioiSeconds = Double(ioiHops) * hopDuration
                if ioiSeconds > 0 {
                    let bpm = 60.0 / ioiSeconds
                    // Map to histogram bin
                    if bpm >= minBPM && bpm <= maxBPM {
                        let bin = Int((bpm - minBPM) / (maxBPM - minBPM) * Double(ioiHistogramSize - 1))
                        let clampedBin = max(0, min(ioiHistogramSize - 1, bin))
                        ioiHistogram[clampedBin] += 1
                    }
                }
            }

            // Update BPM estimate
            updateBPMEstimate()

            // Update beat phase tracking
            if cachedBeatPeriodHops > 0 {
                beatPhaseCounter = (beatPhaseCounter + 1) % 4
                lastBeatHop = currentHop
            }
        }

        currentHop += 1
    }

    /// Estimated BPM (0 if not enough data)
    var estimatedBPM: Float { cachedBPM }

    /// Whether the beat tracker has enough data for reliable estimates
    var isConfident: Bool { onsetCount >= 8 && cachedBPM > 0 }

    /// Find the nearest downbeat time to a target time, within tolerance
    /// - Parameters:
    ///   - targetTime: Target time in seconds (from track start)
    ///   - tolerance: Maximum distance from target in seconds
    /// - Returns: The nearest downbeat time, or nil if no confident estimate
    func nearestDownbeat(to targetTime: Double, tolerance: Double) -> Double? {
        guard isConfident, cachedBeatPeriodHops > 0 else { return nil }

        let beatPeriodSeconds = cachedBeatPeriodHops * hopDuration
        let downbeatPeriod = beatPeriodSeconds * 4.0  // 4 beats per downbeat

        guard downbeatPeriod > 0 else { return nil }

        // Find the nearest downbeat to the target time
        // Start from a known beat position and step by downbeat intervals
        let lastBeatTime = Double(lastBeatHop) * hopDuration
        let currentPhaseOffset = Double(beatPhaseCounter) * beatPeriodSeconds

        // Reference downbeat = last beat time minus phase offset
        let refDownbeat = lastBeatTime - currentPhaseOffset

        // Find nearest downbeat to target
        let beatsFromRef = round((targetTime - refDownbeat) / downbeatPeriod)
        let nearestDownbeatTime = refDownbeat + beatsFromRef * downbeatPeriod

        // Check if within tolerance
        if abs(nearestDownbeatTime - targetTime) <= tolerance {
            return nearestDownbeatTime
        }

        return nil
    }

    /// Find the nearest beat time to a target time, within tolerance
    func nearestBeat(to targetTime: Double, tolerance: Double) -> Double? {
        guard isConfident, cachedBeatPeriodHops > 0 else { return nil }

        let beatPeriodSeconds = cachedBeatPeriodHops * hopDuration
        guard beatPeriodSeconds > 0 else { return nil }

        let lastBeatTime = Double(lastBeatHop) * hopDuration
        let beatsFromRef = round((targetTime - lastBeatTime) / beatPeriodSeconds)
        let nearestBeatTime = lastBeatTime + beatsFromRef * beatPeriodSeconds

        if abs(nearestBeatTime - targetTime) <= tolerance {
            return nearestBeatTime
        }

        return nil
    }

    /// Reset all state
    func reset() {
        fluxHistory.initialize(repeating: 0, count: fluxHistorySize)
        fluxWritePos = 0
        fluxCount = 0

        medianScratch.initialize(repeating: 0, count: fluxHistorySize)

        onsetHops.initialize(repeating: 0, count: onsetHistorySize)
        onsetWritePos = 0
        onsetCount = 0

        ioiHistogram.initialize(repeating: 0, count: ioiHistogramSize)

        currentHop = 0
        lastOnsetHop = -100
        beatPhaseCounter = 0
        lastBeatHop = 0
        cachedBPM = 0
        cachedBeatPeriodHops = 0
    }

    // MARK: - Private

    /// Compute median of flux history using insertion sort
    private func computeMedianFlux() -> Float {
        guard fluxCount > 0 else { return 0 }

        // Copy to scratch buffer
        let count = fluxCount
        for i in 0..<count {
            medianScratch[i] = fluxHistory[i]
        }

        // Insertion sort
        for i in 1..<count {
            let key = medianScratch[i]
            var j = i - 1
            while j >= 0 && medianScratch[j] > key {
                medianScratch[j + 1] = medianScratch[j]
                j -= 1
            }
            medianScratch[j + 1] = key
        }

        return medianScratch[count / 2]
    }

    /// Update cached BPM from IOI histogram
    private func updateBPMEstimate() {
        var maxCount = 0
        var peakBin = -1

        for i in 0..<ioiHistogramSize {
            if ioiHistogram[i] > maxCount {
                maxCount = ioiHistogram[i]
                peakBin = i
            }
        }

        // Require at least 3 agreeing intervals
        guard maxCount >= 3, peakBin >= 0 else { return }

        let bpm = minBPM + (Double(peakBin) / Double(ioiHistogramSize - 1)) * (maxBPM - minBPM)
        cachedBPM = Float(bpm)
        cachedBeatPeriodHops = 60.0 / bpm / hopDuration
    }
}
