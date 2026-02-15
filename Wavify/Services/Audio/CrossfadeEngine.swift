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
    /// How many seconds before the end to start preloading the next track
    private let preloadLeadTime: Double = 20.0

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

        // Trigger preload at preloadLeadTime before end
        if remaining <= preloadLeadTime && !hasTriggeredPreload && state == .idle {
            hasTriggeredPreload = true
            triggerPreload()
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

        // Use beat-aligned fade time if available, otherwise standard timing
        let effectiveFadeTime = beatAlignedFadeTime ?? fadeDuration

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

            // Beat alignment: snap fade trigger to nearest downbeat
            if activeDecomp.beatTracker.isConfident {
                let idealTriggerTime = self.trackDuration - self.fadeDuration
                if let downbeat = activeDecomp.beatTracker.nearestDownbeat(to: idealTriggerTime, tolerance: 2.0) {
                    let alignedRemaining = self.trackDuration - downbeat
                    self.beatAlignedFadeTime = alignedRemaining
                    Logger.log("Crossfade: beat-aligned fade at \(String(format: "%.1f", alignedRemaining))s remaining (BPM: \(String(format: "%.0f", activeDecomp.beatTracker.estimatedBPM)), ideal: \(String(format: "%.1f", self.fadeDuration))s)", category: .playback)
                }
            }

            self.state = .ready

            // Start standby player early so stem buffers fill before the fade triggers
            // volumeMixerB is at 0.0, so this is silent
            if !self.slot.isPlaying {
                self.slot.play()
            }

            Logger.log("Crossfade: \(nextSong.title) ready for fade", category: .playback)
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

        // Set the active fade profile from user's transition style preference
        choreographer.activeProfile = TransitionChoreographer.profile(for: settings.transitionStyle)

        Logger.log("Crossfade: starting \(fadeDuration)s premium stem fade (\(settings.transitionStyle.rawValue))", category: .playback)

        let engine = AudioEngineService.shared

        // Enable stem decomposition on the active (outgoing) track's tap
        // This is done via PlaybackService's tap — we need to configure it
        // For now, the active decomposer was set up during analysis

        // Activate stem mode in the engine (mutes normal mixers)
        engine.activateStemMode()

        // Configure choreographer
        let gainCorrection = incomingGainCorrection
        choreographer.onStemVolumesUpdated = { [weak self] volumes in
            guard let self = self, self.state == .stemFading else { return }

            // Drive vocal width bloom on the outgoing decomposer
            self.activeDecomposer?.vocalWidthBloom = volumes.outVocalBloom

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

        choreographer.start(duration: fadeDuration)
    }

    // MARK: - Complete

    private func completeCrossfade() {
        guard state == .fading || state == .stemFading else { return }
        let wasStemMode = state == .stemFading
        state = .completing

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
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}
