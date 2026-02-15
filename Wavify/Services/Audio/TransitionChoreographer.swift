//
//  TransitionChoreographer.swift
//  Wavify
//
//  Controls 6 stem volumes with staggered timing for premium crossfade transitions.
//  Each stem fades independently with equal-power curves, creating a musical transition
//  where instruments and bass crossfade first, then vocals linger and blend.
//
//  Fade profiles (fraction of total transition duration):
//    A_instruments: fadeOut 0.00–0.40  |  B_bass:        fadeIn 0.10–0.50
//    A_bass:        fadeOut 0.05–0.50  |  B_instruments: fadeIn 0.20–0.60
//    A_vocals:      fadeOut 0.15–0.75  |  B_vocals:      fadeIn 0.35–0.85
//

import Foundation

@MainActor
final class TransitionChoreographer {

    // MARK: - Fade Profile

    /// Defines the start and end of a fade as fractions of total duration
    struct FadeWindow {
        let start: Double
        let end: Double

        /// Returns 0.0–1.0 progress within this window, or nil if outside
        func progress(at globalProgress: Double) -> Double? {
            guard globalProgress >= start else { return nil }
            guard globalProgress <= end else { return 1.0 }
            return (globalProgress - start) / (end - start)
        }
    }

    // MARK: - Staggered Fade Profiles

    // Outgoing track (A) fades
    static let fadeOut_instruments = FadeWindow(start: 0.00, end: 0.40)
    static let fadeOut_bass        = FadeWindow(start: 0.05, end: 0.50)
    static let fadeOut_vocals      = FadeWindow(start: 0.15, end: 0.75)

    // Incoming track (B) fades
    static let fadeIn_bass         = FadeWindow(start: 0.10, end: 0.50)
    static let fadeIn_instruments  = FadeWindow(start: 0.20, end: 0.60)
    static let fadeIn_vocals       = FadeWindow(start: 0.35, end: 0.85)

    // MARK: - State

    private var fadeTimer: DispatchSourceTimer?
    private var fadeStartTime: Date?
    private var fadeDuration: Double = 6.0
    private(set) var isActive = false

    // MARK: - Callbacks

    /// Called at 60Hz with 6 stem volumes: (A_bass, A_vocal, A_inst, B_bass, B_vocal, B_inst)
    var onStemVolumesUpdated: ((StemVolumes) -> Void)?
    /// Called when the transition is complete
    var onCompleted: (() -> Void)?

    struct StemVolumes {
        let outBass: Float
        let outVocal: Float
        let outInstrument: Float
        let inBass: Float
        let inVocal: Float
        let inInstrument: Float
    }

    // MARK: - Start / Stop

    func start(duration: Double) {
        stop()

        fadeDuration = duration
        fadeStartTime = Date()
        isActive = true

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.resume()
        fadeTimer = timer
    }

    func stop() {
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeStartTime = nil
        isActive = false
    }

    // MARK: - Tick

    private func tick() {
        guard isActive, let startTime = fadeStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / fadeDuration)

        let volumes = computeVolumes(at: progress)
        onStemVolumesUpdated?(volumes)

        if progress >= 1.0 {
            stop()
            onCompleted?()
        }
    }

    // MARK: - Volume Computation

    func computeVolumes(at progress: Double) -> StemVolumes {
        // Outgoing: equal-power fadeout  cos(p * π/2)
        let outInst  = Self.equalPowerOut(Self.fadeOut_instruments.progress(at: progress))
        let outBass  = Self.equalPowerOut(Self.fadeOut_bass.progress(at: progress))
        let outVocal = Self.equalPowerOut(Self.fadeOut_vocals.progress(at: progress))

        // Incoming: equal-power fadein  sin(p * π/2)
        var inBass  = Self.equalPowerIn(Self.fadeIn_bass.progress(at: progress))
        var inInst  = Self.equalPowerIn(Self.fadeIn_instruments.progress(at: progress))
        let inVocal = Self.equalPowerIn(Self.fadeIn_vocals.progress(at: progress))

        // Bass ducking: when both bass stems are audible, reduce each by ~3dB
        if outBass > 0.1 && inBass > 0.1 {
            let duckFactor: Float = 0.707 // -3dB
            // Only duck the incoming to avoid artifacts on the outgoing
            inBass *= duckFactor
        }

        // Instrument ducking (lighter)
        if outInst > 0.1 && inInst > 0.1 {
            let duckFactor: Float = 0.85 // ~-1.4dB
            inInst *= duckFactor
        }

        return StemVolumes(
            outBass: outBass,
            outVocal: outVocal,
            outInstrument: outInst,
            inBass: inBass,
            inVocal: inVocal,
            inInstrument: inInst
        )
    }

    // MARK: - Equal Power Curves

    /// Equal-power fade out: cos(progress * π/2)
    private static func equalPowerOut(_ windowProgress: Double?) -> Float {
        guard let p = windowProgress else { return 1.0 } // Before window = full volume
        return Float(cos(min(1.0, p) * .pi / 2))
    }

    /// Equal-power fade in: sin(progress * π/2)
    private static func equalPowerIn(_ windowProgress: Double?) -> Float {
        guard let p = windowProgress else { return 0.0 } // Before window = silent
        return Float(sin(min(1.0, p) * .pi / 2))
    }
}
