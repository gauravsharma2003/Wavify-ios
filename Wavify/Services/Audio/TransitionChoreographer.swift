//
//  TransitionChoreographer.swift
//  Wavify
//
//  Controls 8 stem volumes + vocal bloom with staggered timing for premium crossfade transitions.
//  Each stem fades independently with equal-power curves, creating a musical transition
//  where drums drop first, atmosphere narrows, bass crosses smoothly, and vocals linger
//  with widening stereo image.
//
//  Supports 3 transition styles (Smooth, DJ Mix, Drop) with different fade window timings.
//

import Foundation

@MainActor
final class TransitionChoreographer {

    // MARK: - Fade Window

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

    // MARK: - Fade Profile

    /// A complete set of fade windows for all 8 stems
    struct FadeProfile {
        let outDrums: FadeWindow
        let outAtmosphere: FadeWindow
        let outBass: FadeWindow
        let outVocals: FadeWindow
        let inBass: FadeWindow
        let inAtmosphere: FadeWindow
        let inDrums: FadeWindow
        let inVocals: FadeWindow
    }

    // MARK: - Preset Profiles

    static let smoothProfile = FadeProfile(
        outDrums:      FadeWindow(start: 0.00, end: 0.35),
        outAtmosphere: FadeWindow(start: 0.05, end: 0.45),
        outBass:       FadeWindow(start: 0.08, end: 0.55),
        outVocals:     FadeWindow(start: 0.15, end: 0.75),
        inBass:        FadeWindow(start: 0.10, end: 0.55),
        inAtmosphere:  FadeWindow(start: 0.20, end: 0.65),
        inDrums:       FadeWindow(start: 0.25, end: 0.65),
        inVocals:      FadeWindow(start: 0.35, end: 0.85)
    )

    static let djMixProfile = FadeProfile(
        outDrums:      FadeWindow(start: 0.00, end: 0.25),
        outAtmosphere: FadeWindow(start: 0.05, end: 0.35),
        outBass:       FadeWindow(start: 0.10, end: 0.40),
        outVocals:     FadeWindow(start: 0.10, end: 0.55),
        inBass:        FadeWindow(start: 0.15, end: 0.50),
        inAtmosphere:  FadeWindow(start: 0.20, end: 0.55),
        inDrums:       FadeWindow(start: 0.30, end: 0.55),
        inVocals:      FadeWindow(start: 0.45, end: 0.80)
    )

    static let dropProfile = FadeProfile(
        outDrums:      FadeWindow(start: 0.00, end: 0.20),
        outAtmosphere: FadeWindow(start: 0.00, end: 0.25),
        outBass:       FadeWindow(start: 0.00, end: 0.25),
        outVocals:     FadeWindow(start: 0.05, end: 0.35),
        inBass:        FadeWindow(start: 0.40, end: 0.55),
        inAtmosphere:  FadeWindow(start: 0.38, end: 0.55),
        inDrums:       FadeWindow(start: 0.35, end: 0.50),
        inVocals:      FadeWindow(start: 0.45, end: 0.70)
    )

    static func profile(for style: TransitionStyle) -> FadeProfile {
        switch style {
        case .auto:   return smoothProfile  // CrossfadeEngine overrides dynamically
        case .smooth: return smoothProfile
        case .djMix:  return djMixProfile
        case .drop:   return dropProfile
        }
    }

    /// The active fade profile used by computeVolumes()
    var activeProfile: FadeProfile = TransitionChoreographer.smoothProfile

    /// Optional override for incoming drums fade start (beat-aligned transitions)
    var incomingDrumStartOverride: Double?

    // MARK: - Stagger Intensity

    /// Controls how much stagger is applied (0.0 = aligned/simple, 1.0 = full stagger)
    /// Set by CrossfadeEngine based on stereo width detection
    var staggerIntensity: Float = 1.0

    // MARK: - State

    private var fadeTimer: DispatchSourceTimer?
    private var fadeStartTime: Date?
    private var fadeDuration: Double = 6.0
    private(set) var isActive = false

    // MARK: - Callbacks

    /// Called at 60Hz with 9 stem volumes
    var onStemVolumesUpdated: ((StemVolumes) -> Void)?
    /// Called when the transition is complete
    var onCompleted: (() -> Void)?

    struct StemVolumes {
        let outDrums: Float
        let outBass: Float
        let outVocal: Float
        let outAtmosphere: Float
        let inDrums: Float
        let inBass: Float
        let inVocal: Float
        let inAtmosphere: Float
        let outVocalBloom: Float   // Vocal stereo width (0=mono, 1=wide)
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

    // MARK: - Effective Windows

    /// Interpolate a FadeWindow toward aligned (0.0→1.0) based on stagger intensity
    private func effectiveWindow(_ window: FadeWindow) -> FadeWindow {
        let t = Double(staggerIntensity)
        // At intensity=0: all windows become 0.0→1.0 (aligned/simple crossfade)
        // At intensity=1: full stagger as defined
        let start = window.start * t
        let end = window.end * t + 1.0 * (1.0 - t)
        return FadeWindow(start: start, end: end)
    }

    // MARK: - Volume Computation

    func computeVolumes(at progress: Double) -> StemVolumes {
        let p = activeProfile

        // Apply drum start override if set (beat-aligned incoming drums)
        let inDrumsWindow: FadeWindow
        if let override = incomingDrumStartOverride {
            inDrumsWindow = FadeWindow(start: override, end: p.inDrums.end)
        } else {
            inDrumsWindow = p.inDrums
        }

        // Apply stagger intensity to fade windows
        let effOut_drums = effectiveWindow(p.outDrums)
        let effOut_atmos = effectiveWindow(p.outAtmosphere)
        let effOut_bass  = effectiveWindow(p.outBass)
        let effOut_vocal = effectiveWindow(p.outVocals)
        let effIn_bass   = effectiveWindow(p.inBass)
        let effIn_atmos  = effectiveWindow(p.inAtmosphere)
        let effIn_drums  = effectiveWindow(inDrumsWindow)
        let effIn_vocal  = effectiveWindow(p.inVocals)

        // Outgoing: equal-power fadeout  cos(p * π/2)
        var outDrums = Self.equalPowerOut(effOut_drums.progress(at: progress))
        var outAtmos = Self.equalPowerOut(effOut_atmos.progress(at: progress))
        var outBass  = Self.equalPowerOut(effOut_bass.progress(at: progress))
        let outVocal = Self.equalPowerOut(effOut_vocal.progress(at: progress))

        // Incoming: equal-power fadein  sin(p * π/2)
        var inBass  = Self.equalPowerIn(effIn_bass.progress(at: progress))
        var inAtmos = Self.equalPowerIn(effIn_atmos.progress(at: progress))
        var inDrums = Self.equalPowerIn(effIn_drums.progress(at: progress))
        let inVocal = Self.equalPowerIn(effIn_vocal.progress(at: progress))

        // Energy-preserving complementary bass scaling
        let totalBassEnergy = outBass * outBass + inBass * inBass
        if totalBassEnergy > 0.01 {
            let scale = 1.0 / sqrt(totalBassEnergy)
            if scale < 1.0 {
                outBass *= scale
                inBass *= scale
            }
        }

        // Energy preservation for atmosphere
        let totalAtmosEnergy = outAtmos * outAtmos + inAtmos * inAtmos
        if totalAtmosEnergy > 0.01 {
            let scale = 1.0 / sqrt(totalAtmosEnergy)
            if scale < 1.0 {
                outAtmos *= scale
                inAtmos *= scale
            }
        }

        // Energy preservation for drums
        let totalDrumsEnergy = outDrums * outDrums + inDrums * inDrums
        if totalDrumsEnergy > 0.01 {
            let scale = 1.0 / sqrt(totalDrumsEnergy)
            if scale < 1.0 {
                outDrums *= scale
                inDrums *= scale
            }
        }

        // Vocal bloom: ramps faster than vocal fade (1.5× speed), clamped to [0,1]
        let vocalFadeProgress = effOut_vocal.progress(at: progress) ?? 0.0
        let outVocalBloom = Float(min(1.0, vocalFadeProgress * 1.5))

        return StemVolumes(
            outDrums: outDrums,
            outBass: outBass,
            outVocal: outVocal,
            outAtmosphere: outAtmos,
            inDrums: inDrums,
            inBass: inBass,
            inVocal: inVocal,
            inAtmosphere: inAtmos,
            outVocalBloom: outVocalBloom
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
