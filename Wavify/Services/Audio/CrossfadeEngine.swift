//
//  CrossfadeEngine.swift
//  Wavify
//
//  Central coordinator for crossfade transitions between tracks.
//  State machine: idle → preloading → analyzing → ready → fading/stemFading → completing → idle
//
//  When premium crossfade is enabled, uses stem-based transitions (StemDecomposer +
//  TransitionChoreographer) for musical crossfades where instruments/bass crossfade first
//  and vocals linger and blend. Falls back to simple equal-power crossfade for mono content.
//

import Foundation
import AVFoundation
import UIKit

@MainActor
@Observable
final class CrossfadeEngine {

    // MARK: - State Machine

    enum State: String {
        case idle
        case preloading
        case analyzing      // Premium: computing side/mid ratio to decide stem vs. simple
        case ready
        case fading         // Simple equal-power crossfade
        case stemFading     // Premium stem-based crossfade
        case completing
    }

    private(set) var state: State = .idle

    // MARK: - Configuration

    private let settings = CrossfadeSettings.shared
    /// How many seconds before the end to start preloading the next track.
    /// Sized for the worst-case bars-based fade (8 bars at 60 BPM = 32s) plus
    /// a safety margin so stream fetch + analysis comfortably finish in time.
    private let preloadLeadTime: Double = 36.0

    // MARK: - Components

    private let slot = CrossfadePlayerSlot()
    private let choreographer = TransitionChoreographer()

    // MARK: - Stem Decomposition

    /// Decomposers for outgoing (active) and incoming (standby) tracks
    private var activeDecomposer: StemDecomposer?
    private var standbyDecomposer: StemDecomposer?

    /// Whether the current transition is using stem mode
    private var usingStemMode = false

    /// Side/mid ratio thresholds for graduated stereo detection
    private let monoThreshold: Double = 0.02      // Below → simple crossfade
    private let fullStereoThreshold: Double = 0.15 // Above → full stagger

    /// Gain correction to normalize incoming track loudness to match outgoing
    private var incomingGainCorrection: Float = 1.0

    // MARK: - Fade Timer (Simple mode)

    private var fadeTimer: DispatchSourceTimer?
    private var fadeStartTime: Date?
    private var fadeDuration: Double = 6.0

    // MARK: - Background Task

    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Tracking

    private(set) var preloadedSong: Song?
    private var preloadedDuration: Double = 0
    private var hasTriggeredPreload = false
    private var hasTriggeredFade = false

    // MARK: - Smart Transition

    /// Whether an early transition was triggered by vocal drop detection
    private var earlyTransitionTriggered = false
    /// Minimum playback time before allowing smart early transition
    private let smartTransitionMinPlayback: Double = 30.0

    // MARK: - Beat Alignment

    /// Beat-aligned fade trigger time (computed after analysis)
    private var beatAlignedFadeTime: Double?
    /// Total track duration (saved for beat alignment calculations)
    private var trackDuration: Double = 0

    // MARK: - Energy Profiling (Feature 1)

    enum EnergyProfile: String {
        case highToHigh, highToLow, lowToHigh, lowToLow
    }

    private var autoEnergyProfile: EnergyProfile?
    private var adjustedFadeDuration: Double?

    // MARK: - Beatmatch (Feature 2a)

    /// Whether this transition applied tempo-matching to the incoming track
    private var didApplyBeatmatch: Bool = false
    /// Rate applied to the standby slot (1.0 = no stretch)
    private var beatmatchRate: Float = 1.0
    /// Outgoing BPM at analysis time (used for post-handoff rate ramp duration)
    private var outgoingBPM: Float = 0
    /// BPM seen at analysis; used to detect rubato drift before trigger
    private var analysisBPM: Float = 0

    // MARK: - Taste Learning (Feature 3)

    private let learner = TransitionLearner()
    private var currentTransitionKey: (energy: String, profile: String)?

    // MARK: - Callbacks (wired by AudioPlayer)

    /// Ask AudioPlayer for the next song to crossfade into
    var onPreloadNeeded: (() -> Song?)?
    /// Ask AudioPlayer to fetch a playback URL for the song
    var onFetchPlaybackURL: ((Song) async throws -> (URL, Double))?
    /// Notify AudioPlayer that crossfade completed — hand off to PlaybackService
    /// Parameters: (song, player, playerItem, expectedDuration)
    var onCrossfadeCompleted: ((Song, AVPlayer, AVPlayerItem, Double) -> Void)?
    /// Get the active (outgoing) track's tap context for stem decomposition
    var onGetActiveTapContext: (() -> AudioTapContext?)?

    // MARK: - Monitoring

    /// Called from the time observer. Triggers preload and fade based on position.
    func startMonitoring(currentTime: Double, duration: Double) {
        guard settings.isEnabled else { return }
        guard duration > 0 else { return }

        fadeDuration = settings.fadeDuration
        trackDuration = duration

        // Skip crossfade for short tracks (less than 3x fade duration)
        guard duration >= fadeDuration * 3 else { return }

        let remaining = duration - currentTime

        // Cancel crossfade if position moved back outside the crossfade zone (e.g. after seek/previous)
        if remaining > preloadLeadTime && state != .idle {
            Logger.log("Crossfade: position outside crossfade zone (\(String(format: "%.1f", remaining))s remaining), cancelling", category: .playback)
            cancelCrossfade()
            return
        }

        // Suppress preload while the post-handoff rate ramp is still drifting
        // back to 1.0 — kicking off another beatmatch decision against a
        // not-yet-normalised tempo would corrupt the ratio calculation.
        if AudioEngineService.shared.rampInProgress && state == .idle {
            return
        }

        // Trigger preload at preloadLeadTime before end
        if remaining <= preloadLeadTime && !hasTriggeredPreload && state == .idle {
            hasTriggeredPreload = true
            triggerPreload()
        }

        // Rubato guard: if the outgoing BPM has drifted significantly since
        // analysis (e.g. ritard outro), recompute the bars-based duration so
        // the fade window still matches musical bars.
        if state == .ready, settings.isPremium, analysisBPM > 0,
           let activeBT = activeDecomposer?.beatTracker, activeBT.isConfident {
            let currentBPM = activeBT.estimatedBPM
            if currentBPM > 0 {
                let drift = abs(Double(currentBPM - analysisBPM)) / Double(analysisBPM)
                if drift > 0.05 {
                    let barsBasedDuration = (60.0 / Double(currentBPM)) * 4.0 * Double(settings.fadeBars)
                    let clamped = min(16.0, max(4.0, barsBasedDuration))
                    adjustedFadeDuration = clamped
                    analysisBPM = currentBPM
                    Logger.log("Crossfade: rubato detected (\(String(format: "%.1f%%", drift * 100)) BPM drift), recomputed duration to \(String(format: "%.1f", clamped))s @ \(String(format: "%.0f", currentBPM)) BPM", category: .playback)
                }
            }
        }

        // Smart early transition: detect vocal drop-off in the approach window
        if state == .ready && settings.isPremium && !hasTriggeredFade && !earlyTransitionTriggered
            && currentTime > smartTransitionMinPlayback {
            let idealFadeTime = duration - fadeDuration
            let earlyWindowStart = idealFadeTime - 10.0
            if currentTime >= earlyWindowStart && currentTime < idealFadeTime {
                if activeDecomposer?.isVocalDropDetected == true {
                    earlyTransitionTriggered = true
                    hasTriggeredFade = true
                    Logger.log("Crossfade: smart transition triggered at \(String(format: "%.1f", currentTime))s (vocal drop detected, ideal was \(String(format: "%.1f", idealFadeTime))s)", category: .playback)
                    triggerFade()
                    return
                }
            }
        }

        // Use beat-aligned fade time if available, then adjusted duration, then default
        let baseFadeTime = adjustedFadeDuration ?? fadeDuration
        let effectiveFadeTime = beatAlignedFadeTime ?? baseFadeTime

        // Trigger fade at effectiveFadeTime before end
        if remaining <= effectiveFadeTime && !hasTriggeredFade && (state == .ready) {
            hasTriggeredFade = true
            if let beatTime = beatAlignedFadeTime {
                Logger.log("Crossfade: beat-aligned trigger at \(String(format: "%.1f", currentTime))s (ideal: \(String(format: "%.1f", duration - fadeDuration))s)", category: .playback)
                _ = beatTime // suppress unused warning
            }
            triggerFade()
        }
    }

    // MARK: - Preload

    private func triggerPreload() {
        guard let nextSong = onPreloadNeeded?() else {
            state = .idle
            hasTriggeredPreload = false
            return
        }

        // Don't crossfade into the same song (loop one)
        if let currentSong = preloadedSong, currentSong.id == nextSong.id {
            state = .idle
            return
        }

        state = .preloading
        preloadedSong = nextSong

        Logger.log("Crossfade: preloading \(nextSong.title)", category: .playback)

        Task {
            do {
                guard let fetchURL = onFetchPlaybackURL else {
                    resetToIdle()
                    return
                }

                let (url, expectedDuration) = try await fetchURL(nextSong)
                self.preloadedDuration = expectedDuration
                let targetBuffer = AudioEngineService.shared.standbyRingBuffer

                slot.onReady = { [weak self] in
                    guard let self = self, self.state == .preloading else { return }
                    self.beginAnalysis(nextSong: nextSong)
                }

                slot.onFailed = { [weak self] error in
                    Logger.warning("Crossfade: preload failed — \(error?.localizedDescription ?? "unknown")", category: .playback)
                    self?.resetToIdle()
                }

                slot.load(url: url, expectedDuration: expectedDuration, song: nextSong, ringBuffer: targetBuffer)
            } catch {
                Logger.warning("Crossfade: failed to fetch URL — \(error.localizedDescription)", category: .playback)
                resetToIdle()
            }
        }
    }

    // MARK: - Analysis (Premium)

    private func beginAnalysis(nextSong: Song) {
        guard settings.isPremium else {
            // Simple mode — skip analysis, go straight to ready
            state = .ready
            Logger.log("Crossfade: \(nextSong.title) ready for simple fade", category: .playback)
            return
        }

        state = .analyzing
        Logger.log("Crossfade: analyzing \(nextSong.title) for stem separation", category: .playback)

        // Create decomposers for both active and standby tracks
        let engine = AudioEngineService.shared
        let activeStemBufs = engine.activeStemBuffers
        let standbyStemBufs = engine.standbyStemBuffers

        // Active track decomposer (outgoing — writes to active stem buffers)
        let activeDecomp = StemDecomposer(
            bassBuffer: activeStemBufs.bass,
            vocalBuffer: activeStemBufs.vocal,
            instrumentBuffer: activeStemBufs.atmos,
            drumsBuffer: activeStemBufs.drums,
            fullMixBuffer: engine.activeRingBuffer
        )

        // Standby track decomposer (incoming — writes to standby stem buffers)
        let standbyDecomp = StemDecomposer(
            bassBuffer: standbyStemBufs.bass,
            vocalBuffer: standbyStemBufs.vocal,
            instrumentBuffer: standbyStemBufs.atmos,
            drumsBuffer: standbyStemBufs.drums,
            fullMixBuffer: engine.standbyRingBuffer
        )

        self.activeDecomposer = activeDecomp
        self.standbyDecomposer = standbyDecomp

        // Configure the standby slot's tap to use stem decomposition
        if let tapContext = slot.tapContext {
            tapContext.stemDecomposer = standbyDecomp
            tapContext.stemMode = true
        }

        // Configure the active (outgoing) tap for stem decomposition
        // fullMixBuffer ensures normal ring buffer continues receiving data
        if let activeTapCtx = onGetActiveTapContext?() {
            activeTapCtx.stemDecomposer = activeDecomp
            activeTapCtx.stemMode = true
        } else {
            // Can't access active tap — fall back to simple crossfade
            Logger.warning("Crossfade: no active tap context, falling back to simple", category: .playback)
            usingStemMode = false
            if let tapCtx = slot.tapContext { tapCtx.stemMode = false; tapCtx.stemDecomposer = nil }
            self.activeDecomposer = nil
            self.standbyDecomposer = nil
            self.state = .ready
            return
        }

        // Wait briefly for analysis data to accumulate (~200ms worth of audio)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard self.state == .analyzing else { return }

            // Compute loudness normalization using A-weighted RMS in dB domain
            let activeRMS = activeDecomp.aWeightedRMS
            let standbyRMS = standbyDecomp.aWeightedRMS
            if standbyRMS > 0.001 && activeRMS > 0.001 {
                let activeDB = 20.0 * log10(activeRMS)
                let standbyDB = 20.0 * log10(standbyRMS)
                let diffDB = min(6.0, max(-6.0, activeDB - standbyDB))
                self.incomingGainCorrection = Float(pow(10.0, diffDB / 20.0))
                Logger.log("Crossfade: loudness correction \(String(format: "%.2f", self.incomingGainCorrection)) (active: \(String(format: "%.1f", activeDB))dB, standby: \(String(format: "%.1f", standbyDB))dB, diff: \(String(format: "%.1f", diffDB))dB)", category: .playback)
            } else {
                self.incomingGainCorrection = 1.0
            }

            // Check the standby decomposer's side/mid ratio with graduated detection
            let ratio = standbyDecomp.sideMidRatio
            if ratio < self.monoThreshold {
                // Too mono for stem mode — fall back to simple crossfade
                usingStemMode = false
                if let tapContext = slot.tapContext {
                    tapContext.stemMode = false
                    tapContext.stemDecomposer = nil
                }
                if let activeTapCtx = self.onGetActiveTapContext?() {
                    activeTapCtx.stemMode = false
                    activeTapCtx.stemDecomposer = nil
                }
                self.activeDecomposer = nil
                self.standbyDecomposer = nil
                Logger.log("Crossfade: mono content detected (ratio: \(String(format: "%.3f", ratio))), using simple fade", category: .playback)
            } else {
                usingStemMode = true
                // Graduated stagger intensity based on stereo width
                let intensity = Float((ratio - self.monoThreshold) / (self.fullStereoThreshold - self.monoThreshold))
                self.choreographer.staggerIntensity = min(1.0, max(0.0, intensity))
                Logger.log("Crossfade: stem mode enabled (side/mid ratio: \(String(format: "%.3f", ratio)), stagger: \(String(format: "%.2f", self.choreographer.staggerIntensity)))", category: .playback)
            }

            // Energy profiling: classify initial energy from drum+bass RMS
            let activeEnergy = activeDecomp.averageDrumBassEnergy
            let standbyEnergy = standbyDecomp.averageDrumBassEnergy
            let energyThreshold = 0.126  // ≈ -18dB linear
            let activeHigh = activeEnergy > energyThreshold
            let standbyHigh = standbyEnergy > energyThreshold

            let profile: EnergyProfile
            if activeHigh && standbyHigh {
                profile = .highToHigh
            } else if activeHigh && !standbyHigh {
                profile = .highToLow
            } else if !activeHigh && standbyHigh {
                profile = .lowToHigh
            } else {
                profile = .lowToLow
            }
            self.autoEnergyProfile = profile

            // Set adjusted fade duration (2× for high→low transitions)
            var durationMultiplier = 1.0
            if profile == .highToLow {
                durationMultiplier = 2.0
            }
            self.adjustedFadeDuration = self.fadeDuration * durationMultiplier

            Logger.log("Crossfade: energy profile \(profile.rawValue) (active: \(String(format: "%.3f", activeEnergy)), standby: \(String(format: "%.3f", standbyEnergy)), duration: \(String(format: "%.1f", self.adjustedFadeDuration ?? self.fadeDuration))s)", category: .playback)

            // Key detection: detect keys and adjust duration by compatibility
            let activeKey = activeDecomp.detectedKey
            let standbyKey = standbyDecomp.detectedKey
            if activeKey.confidence > 0.7 && standbyKey.confidence > 0.7 {
                let interval = ChromaKeyDetector.interval(from: activeKey.key, to: standbyKey.key)
                let compat = ChromaKeyDetector.compatibility(interval: interval)
                let keyMultiplier: Double
                switch compat {
                case "compatible": keyMultiplier = 1.25
                case "clashing":   keyMultiplier = 0.75
                default:           keyMultiplier = 1.0
                }
                self.adjustedFadeDuration = min(15.0, max(4.0, (self.adjustedFadeDuration ?? self.fadeDuration) * keyMultiplier))

                let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                let activeKeyName = "\(keyNames[activeKey.key % 12])\(activeKey.key < 12 ? " maj" : " min")"
                let standbyKeyName = "\(keyNames[standbyKey.key % 12])\(standbyKey.key < 12 ? " maj" : " min")"
                Logger.log("Crossfade: key detection — active: \(activeKeyName) (conf: \(String(format: "%.2f", activeKey.confidence))), standby: \(standbyKeyName) (conf: \(String(format: "%.2f", standbyKey.confidence))), interval: \(interval) (\(compat)), adjusted duration: \(String(format: "%.1f", self.adjustedFadeDuration ?? self.fadeDuration))s", category: .playback)
            }

            // Bars-based fade duration (Premium + outgoing BPM confident).
            // Overrides energy/key-derived duration when conditions are met. A
            // 4-bar fade at 60 BPM is 16s; clamp into a sane range so unusual
            // tempos don't produce too-short or too-long fades.
            if self.settings.isPremium, activeDecomp.beatTracker.isConfident {
                let bpm = Double(activeDecomp.beatTracker.estimatedBPM)
                if bpm > 0 {
                    let barsBasedDuration = (60.0 / bpm) * 4.0 * Double(self.settings.fadeBars)
                    let clamped = min(16.0, max(4.0, barsBasedDuration))
                    self.adjustedFadeDuration = clamped
                    self.analysisBPM = activeDecomp.beatTracker.estimatedBPM
                    self.outgoingBPM = activeDecomp.beatTracker.estimatedBPM
                    Logger.log("Crossfade: bars-based duration \(String(format: "%.1f", clamped))s (\(self.settings.fadeBars) bars @ \(String(format: "%.0f", bpm)) BPM)", category: .playback)
                }
            }

            // Beat alignment: snap fade trigger to the nearest 4-bar grid
            // boundary (falling back to any downbeat if no 4-bar boundary fits
            // within tolerance). Replaces the previous 2s tolerance with ~1
            // bar so the snap is musically meaningful instead of opportunistic.
            if activeDecomp.beatTracker.isConfident {
                let baseDuration = self.adjustedFadeDuration ?? self.fadeDuration
                let idealTriggerTime = self.trackDuration - baseDuration
                let beatPeriod = 60.0 / Double(activeDecomp.beatTracker.estimatedBPM)
                let barTolerance = beatPeriod * 4.0  // one bar
                let snap = activeDecomp.beatTracker.nearestFourBarBoundary(to: idealTriggerTime, tolerance: barTolerance)
                    ?? activeDecomp.beatTracker.nearestDownbeat(to: idealTriggerTime, tolerance: beatPeriod * 2.0)
                if let downbeat = snap {
                    let alignedRemaining = self.trackDuration - downbeat
                    self.beatAlignedFadeTime = alignedRemaining
                    Logger.log("Crossfade: beat-aligned fade at \(String(format: "%.1f", alignedRemaining))s remaining (BPM: \(String(format: "%.0f", activeDecomp.beatTracker.estimatedBPM)), ideal: \(String(format: "%.1f", baseDuration))s)", category: .playback)
                }
            }

            self.state = .ready

            // Start standby player early so stem buffers fill before the fade triggers
            // volumeMixerB is at 0.0, so this is silent
            if !self.slot.isPlaying {
                self.slot.play()
            }

            Logger.log("Crossfade: \(nextSong.title) ready for fade", category: .playback)

            // Schedule beatmatch + phase alignment evaluation. The standby
            // player needs at least ~1s of silent playback for its BeatTracker
            // to stabilise, which is why this runs after .ready (not inline
            // with the 300ms analysis sleep).
            let weakActive = activeDecomp
            let weakStandby = standbyDecomp
            Task { [weak self] in
                guard let self = self else { return }
                await self.evaluateBeatmatchAndAlign(activeDecomp: weakActive, standbyDecomp: weakStandby)
            }
        }
    }

    // MARK: - Beatmatch + Phase Alignment

    /// Wait for the standby BeatTracker to stabilise, decide whether to
    /// tempo-match the incoming track to the outgoing, and seek-align its
    /// next downbeat with the outgoing's. Tolerant of state changes: bails
    /// out cleanly if the transition was cancelled or already past .ready.
    private func evaluateBeatmatchAndAlign(activeDecomp: StemDecomposer, standbyDecomp: StemDecomposer) async {
        // Poll for standby tracker confidence (cap at 2s wall time)
        var waitedMs = 0
        while waitedMs < 2000 && state == .ready && !standbyDecomp.beatTracker.isConfident {
            try? await Task.sleep(for: .milliseconds(100))
            waitedMs += 100
        }

        guard state == .ready else {
            Logger.log("Crossfade: beatmatch skipped — state \(state.rawValue), not .ready", category: .playback)
            return
        }
        guard settings.isPremium else { return }
        guard activeDecomp.beatTracker.isConfident, standbyDecomp.beatTracker.isConfident else {
            Logger.log("Crossfade: beatmatch skipped — tracker not confident (active=\(activeDecomp.beatTracker.isConfident), standby=\(standbyDecomp.beatTracker.isConfident))", category: .playback)
            return
        }

        let outBPM = activeDecomp.beatTracker.estimatedBPM
        let inBPM = standbyDecomp.beatTracker.estimatedBPM
        guard outBPM > 0, inBPM > 0 else { return }

        let ratio = Double(outBPM) / Double(inBPM)
        guard ratio >= 0.92, ratio <= 1.08 else {
            Logger.log("Crossfade: beatmatch skipped — ratio \(String(format: "%.3f", ratio)) out of [0.92, 1.08] (out=\(String(format: "%.1f", outBPM)), in=\(String(format: "%.1f", inBPM)))", category: .playback)
            return
        }

        // Apply rate to the standby slot. All 5 time-pitch units on that slot
        // (full + 4 stems) lock to this rate so the fade is uniform.
        beatmatchRate = Float(ratio)
        AudioEngineService.shared.setStandbyRate(beatmatchRate)
        didApplyBeatmatch = true
        Logger.log("Crossfade: beatmatch enabled, rate=\(String(format: "%.3f", beatmatchRate)), out=\(String(format: "%.1f", outBPM)) in=\(String(format: "%.1f", inBPM))", category: .playback)

        // ---- Phase alignment ----
        // We want both tracks' next downbeats to coincide in wall-clock at the
        // fade trigger. Outgoing plays at natural rate; incoming plays at
        // beatmatchRate. Solving the wall-clock equation gives a seek offset
        // (in incoming track time) to apply via the silent standby player.
        let baseDuration = adjustedFadeDuration ?? fadeDuration
        let triggerOutNow = trackDuration - (beatAlignedFadeTime ?? baseDuration)
        let outBeatPeriod = 60.0 / Double(outBPM)
        let inBeatPeriod = 60.0 / Double(inBPM)
        let outTarget = triggerOutNow + baseDuration / 2.0

        let outDownOpt = activeDecomp.beatTracker.nearestFourBarBoundary(to: outTarget, tolerance: outBeatPeriod * 4.0)
            ?? activeDecomp.beatTracker.nearestDownbeat(to: outTarget, tolerance: outBeatPeriod * 2.0)
        guard let outDown = outDownOpt, outDown > triggerOutNow else {
            Logger.log("Crossfade: phase-align skipped — no outgoing downbeat near target", category: .playback)
            return
        }

        let dtWallOut = outDown - triggerOutNow
        let inNow = slot.currentTimeSeconds
        let inTargetTrack = inNow + dtWallOut * Double(beatmatchRate)
        let inDownOpt = standbyDecomp.beatTracker.nearestDownbeat(to: inTargetTrack, tolerance: inBeatPeriod * 2.0)
        guard let inDown = inDownOpt else {
            Logger.log("Crossfade: phase-align skipped — no incoming downbeat near target", category: .playback)
            return
        }

        // seekOffset (incoming track time): + = seek forward, - = seek backward.
        // Equivalent to (current dt_in_track) - (desired dt_in_track).
        var seekOffset = (inDown - inNow) - (dtWallOut * Double(beatmatchRate))
        // Normalise to the nearest beat (avoid seeking a full bar)
        while seekOffset > inBeatPeriod / 2.0 { seekOffset -= inBeatPeriod }
        while seekOffset < -inBeatPeriod / 2.0 { seekOffset += inBeatPeriod }

        if abs(seekOffset) > inBeatPeriod / 8.0 {
            Logger.log("Crossfade: phase aligning by \(String(format: "%+.3f", seekOffset))s (dt_wall_out=\(String(format: "%.2f", dtWallOut))s)", category: .playback)
            await slot.seekForPhaseAlign(by: seekOffset)
        } else {
            Logger.log("Crossfade: phase already within ⅛-beat tolerance (\(String(format: "%+.3f", seekOffset))s)", category: .playback)
        }
    }

    // MARK: - Fade

    private func triggerFade() {
        guard state == .ready else { return }

        // Begin background task to keep fade running if app is backgrounded
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "CrossfadeTransition") { [weak self] in
            self?.cancelCrossfade()
        }

        // Start the incoming track playing (may already be playing from pre-fill)
        if !slot.isPlaying {
            slot.play()
        }

        if usingStemMode && settings.isPremium {
            triggerStemFade()
        } else {
            triggerSimpleFade()
        }
    }

    // MARK: - Simple Fade

    private func triggerSimpleFade() {
        state = .fading

        Logger.log("Crossfade: starting \(fadeDuration)s simple fade", category: .playback)

        fadeStartTime = Date()

        // 60Hz timer on a background queue
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.simpleTimerTick()
            }
        }
        timer.resume()
        fadeTimer = timer
    }

    private func simpleTimerTick() {
        guard state == .fading, let startTime = fadeStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / fadeDuration)

        // Equal-power crossfade curves
        let outGain = Float(cos(progress * .pi / 2))
        let inGain = Float(sin(progress * .pi / 2)) * incomingGainCorrection

        AudioEngineService.shared.setCrossfadeVolumes(outGain: outGain, inGain: inGain)

        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    // MARK: - Stem Fade (Premium)

    private func triggerStemFade() {
        state = .stemFading

        // Feature 1: Auto-select fade profile from energy classification
        var selectedProfile: TransitionChoreographer.FadeProfile
        var selectedProfileName: String

        if settings.transitionStyle == .auto {
            // Refine energy classification with full accumulated data
            if let activeDecomp = activeDecomposer, let standbyDecomp = standbyDecomposer {
                let activeEnergy = activeDecomp.averageDrumBassEnergy
                let standbyEnergy = standbyDecomp.averageDrumBassEnergy
                let energyThreshold = 0.126
                let activeHigh = activeEnergy > energyThreshold
                let standbyHigh = standbyEnergy > energyThreshold

                let refined: EnergyProfile
                if activeHigh && standbyHigh {
                    refined = .highToHigh
                } else if activeHigh && !standbyHigh {
                    refined = .highToLow
                } else if !activeHigh && standbyHigh {
                    refined = .lowToHigh
                } else {
                    refined = .lowToLow
                }
                autoEnergyProfile = refined

                // Map energy profile → default fade profile
                switch refined {
                case .highToHigh:
                    selectedProfile = TransitionChoreographer.djMixProfile
                    selectedProfileName = "djMix"
                case .highToLow:
                    selectedProfile = TransitionChoreographer.smoothProfile
                    selectedProfileName = "smooth"
                case .lowToHigh:
                    selectedProfile = TransitionChoreographer.dropProfile
                    selectedProfileName = "drop"
                case .lowToLow:
                    selectedProfile = TransitionChoreographer.smoothProfile
                    selectedProfileName = "smooth"
                }

                // Feature 3: Query taste learning for alternative
                if let alternative = learner.shouldUseAlternative(energy: refined.rawValue, proposedProfile: selectedProfileName) {
                    Logger.log("Crossfade: taste learning overriding \(selectedProfileName) for \(refined.rawValue)", category: .playback)
                    selectedProfile = alternative
                    // Determine name from alternative profile (for tracking)
                    if alternative.outDrums.end == TransitionChoreographer.djMixProfile.outDrums.end {
                        selectedProfileName = "djMix"
                    } else if alternative.outDrums.end == TransitionChoreographer.dropProfile.outDrums.end {
                        selectedProfileName = "drop"
                    } else {
                        selectedProfileName = "smooth"
                    }
                }

                currentTransitionKey = (energy: refined.rawValue, profile: selectedProfileName)
            } else {
                selectedProfile = TransitionChoreographer.smoothProfile
                selectedProfileName = "smooth"
            }
        } else {
            selectedProfile = TransitionChoreographer.profile(for: settings.transitionStyle)
            selectedProfileName = settings.transitionStyle.rawValue
        }

        // Feature 5: Adaptive fade curve adjustments (computed once)
        if let activeDecomp = activeDecomposer, let standbyDecomp = standbyDecomposer {
            var adjOutVocals = selectedProfile.outVocals
            var adjInDrums = selectedProfile.inDrums
            var adjOutBass = selectedProfile.outBass
            var adjInBass = selectedProfile.inBass

            // Adjustment 1: Outgoing vocals already quiet → shorten outVocals window
            let recentVocal = activeDecomp.recentVocalRMS
            let avgVocal = activeDecomp.averageVocalRMS
            if avgVocal > 0.001 && recentVocal < avgVocal * 0.5 {
                let shortenedEnd = adjOutVocals.start + (adjOutVocals.end - adjOutVocals.start) * 0.7
                adjOutVocals = TransitionChoreographer.FadeWindow(start: adjOutVocals.start, end: shortenedEnd)
                Logger.log("Crossfade: adaptive — outgoing vocals quiet, shortening vocal window", category: .playback)
            }

            // Adjustment 2: Incoming drums low energy → delay inDrums start
            if standbyDecomp.recentDrumBassEnergy < 0.05 {
                let delayedStart = min(adjInDrums.end - 0.05, adjInDrums.start + 0.15)
                adjInDrums = TransitionChoreographer.FadeWindow(start: delayedStart, end: adjInDrums.end)
                Logger.log("Crossfade: adaptive — incoming drums quiet, delaying drum entry", category: .playback)
            }

            // Adjustment 3: Bass frequency overlap → tighten bass crossover
            if activeDecomp.averageDrumBassEnergy > 0.05 && standbyDecomp.averageDrumBassEnergy > 0.05 {
                let outBassMid = (adjOutBass.start + adjOutBass.end) / 2
                let inBassMid = (adjInBass.start + adjInBass.end) / 2
                let tighten = 0.3
                adjOutBass = TransitionChoreographer.FadeWindow(
                    start: adjOutBass.start + (outBassMid - adjOutBass.start) * tighten,
                    end: adjOutBass.end - (adjOutBass.end - outBassMid) * tighten
                )
                adjInBass = TransitionChoreographer.FadeWindow(
                    start: adjInBass.start + (inBassMid - adjInBass.start) * tighten,
                    end: adjInBass.end - (adjInBass.end - inBassMid) * tighten
                )
                Logger.log("Crossfade: adaptive — both tracks have bass, tightening crossover", category: .playback)
            }

            // Construct adjusted profile
            selectedProfile = TransitionChoreographer.FadeProfile(
                outDrums: selectedProfile.outDrums,
                outAtmosphere: selectedProfile.outAtmosphere,
                outBass: adjOutBass,
                outVocals: adjOutVocals,
                inBass: adjInBass,
                inAtmosphere: selectedProfile.inAtmosphere,
                inDrums: adjInDrums,
                inVocals: selectedProfile.inVocals
            )
        }

        choreographer.activeProfile = selectedProfile

        let effectiveDuration = adjustedFadeDuration ?? fadeDuration
        Logger.log("Crossfade: starting \(String(format: "%.1f", effectiveDuration))s premium stem fade (\(selectedProfileName))", category: .playback)

        let engine = AudioEngineService.shared

        // Activate stem mode in the engine (mutes normal mixers)
        engine.activateStemMode()

        // Configure choreographer
        let gainCorrection = incomingGainCorrection
        choreographer.onStemVolumesUpdated = { [weak self] volumes in
            guard let self = self, self.state == .stemFading else { return }

            // Drive vocal width bloom on the outgoing decomposer
            self.activeDecomposer?.vocalWidthBloom = volumes.outVocalBloom

            // Feature 2: Drive vocal reverb mix on outgoing decomposer
            self.activeDecomposer?.vocalReverbMix = (1.0 - volumes.outVocal) * 0.6

            // Apply loudness normalization to incoming stems
            let corrected = TransitionChoreographer.StemVolumes(
                outDrums: volumes.outDrums,
                outBass: volumes.outBass,
                outVocal: volumes.outVocal,
                outAtmosphere: volumes.outAtmosphere,
                inDrums: volumes.inDrums * gainCorrection,
                inBass: volumes.inBass * gainCorrection,
                inVocal: volumes.inVocal * gainCorrection,
                inAtmosphere: volumes.inAtmosphere * gainCorrection,
                outVocalBloom: volumes.outVocalBloom
            )
            engine.setStemVolumes(corrected)
        }

        choreographer.onCompleted = { [weak self] in
            self?.completeCrossfade()
        }

        choreographer.start(duration: effectiveDuration)
    }

    // MARK: - Complete

    private func completeCrossfade() {
        guard state == .fading || state == .stemFading else { return }
        let wasStemMode = state == .stemFading
        state = .completing

        // Feature 3: Record successful completion for taste learning
        if let key = currentTransitionKey {
            learner.recordCompletion(energy: key.energy, profile: key.profile)
        }

        // Stop timers
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeStartTime = nil
        choreographer.stop()

        Logger.log("Crossfade: fade complete, swapping slots", category: .playback)

        let engine = AudioEngineService.shared

        // Deactivate stem mode if it was active
        if wasStemMode {
            // Disable stem decomposition on taps
            if let tapContext = slot.tapContext {
                tapContext.stemMode = false
                tapContext.stemDecomposer = nil
            }
            if let activeTapCtx = onGetActiveTapContext?() {
                activeTapCtx.stemMode = false
                activeTapCtx.stemDecomposer = nil
            }
            activeDecomposer = nil
            standbyDecomposer = nil
            usingStemMode = false

            engine.deactivateStemMode()
        }

        // Swap active slot in AudioEngineService
        engine.swapActiveSlot()
        engine.resetToSingleTrack()

        // Post-handoff rate ramp: when beatmatch was applied, the just-promoted
        // active slot is playing at the matched (non-natural) rate. Ramp it
        // back to 1.0 over 8 bars at the outgoing tempo so listeners experience
        // a smooth tempo bridge instead of a snap.
        if didApplyBeatmatch, outgoingBPM > 0 {
            let beatPeriod = 60.0 / Double(outgoingBPM)
            let rampBars = 8.0
            let rampDuration = beatPeriod * 4.0 * rampBars
            engine.rampSlotRateToNormal(slot: engine.activeSlot, over: rampDuration)
        }

        // Hand off the now-active player to PlaybackService
        if let song = preloadedSong, let (player, item) = slot.handOffPlayer() {
            onCrossfadeCompleted?(song, player, item, preloadedDuration)
        }

        // Flush the old (now standby) ring buffer
        engine.flushStandby()

        // End background task
        endBackgroundTask()

        resetToIdle()
    }

    // MARK: - Cancel

    /// Cancel any in-progress crossfade and reset to normal single-track playback
    func cancelCrossfade() {
        guard state != .idle else { return }

        Logger.log("Crossfade: cancelling (was \(state.rawValue))", category: .playback)

        // Feature 3: Record skip for taste learning (only during active fade)
        if (state == .stemFading || state == .fading), let key = currentTransitionKey {
            learner.recordSkip(energy: key.energy, profile: key.profile)
        }

        // Stop timers
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeStartTime = nil
        choreographer.stop()

        // Disable stem mode if active
        if usingStemMode || state == .stemFading {
            if let tapContext = slot.tapContext {
                tapContext.stemMode = false
                tapContext.stemDecomposer = nil
            }
            if let activeTapCtx = onGetActiveTapContext?() {
                activeTapCtx.stemMode = false
                activeTapCtx.stemDecomposer = nil
            }
            activeDecomposer = nil
            standbyDecomposer = nil
            usingStemMode = false
            AudioEngineService.shared.deactivateStemMode()
        }

        // Stop and clean up the slot
        slot.cleanup()

        // Reset volumes to single-track
        AudioEngineService.shared.resetToSingleTrack()

        // Reset any in-flight rate ramp or applied beatmatch rate so the next
        // transition starts from a clean tempo state.
        if didApplyBeatmatch || AudioEngineService.shared.rampInProgress {
            AudioEngineService.shared.resetSlotRates()
        }

        // Flush standby buffer
        AudioEngineService.shared.flushStandby()

        endBackgroundTask()
        resetToIdle()
    }

    /// Called when the queue changes (reorder, remove, etc.)
    func queueDidChange() {
        if state == .preloading || state == .ready || state == .analyzing {
            Logger.log("Crossfade: queue changed, cancelling preload", category: .playback)
            cancelCrossfade()
        }
    }

    /// Whether the engine is actively in a fade transition
    var isFading: Bool {
        state == .fading || state == .stemFading || state == .completing
    }

    /// Whether any crossfade activity is in progress
    var isActive: Bool {
        state != .idle
    }

    // MARK: - Private Helpers

    private func resetToIdle() {
        state = .idle
        preloadedSong = nil
        preloadedDuration = 0
        hasTriggeredPreload = false
        hasTriggeredFade = false
        usingStemMode = false
        incomingGainCorrection = 1.0
        earlyTransitionTriggered = false
        beatAlignedFadeTime = nil
        trackDuration = 0
        choreographer.incomingDrumStartOverride = nil
        autoEnergyProfile = nil
        adjustedFadeDuration = nil
        currentTransitionKey = nil
        didApplyBeatmatch = false
        beatmatchRate = 1.0
        outgoingBPM = 0
        analysisBPM = 0
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}
