//
//  CrossfadeEngine.swift
//  Wavify
//
//  Central coordinator for crossfade transitions between tracks.
//  State machine: idle → preloading → ready → fading → completing → idle
//

import Foundation
import AVFoundation
import UIKit

@MainActor
final class CrossfadeEngine {

    // MARK: - State Machine

    enum State: String {
        case idle
        case preloading
        case ready
        case fading
        case completing
    }

    private(set) var state: State = .idle

    // MARK: - Configuration

    private let settings = CrossfadeSettings.shared
    /// How many seconds before the end to start preloading the next track
    private let preloadLeadTime: Double = 20.0

    // MARK: - Components

    private let slot = CrossfadePlayerSlot()

    // MARK: - Fade Timer

    private var fadeTimer: DispatchSourceTimer?
    private var fadeStartTime: Date?
    private var fadeDuration: Double = 6.0

    // MARK: - Background Task

    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Tracking

    private var preloadedSong: Song?
    private var preloadedDuration: Double = 0
    private var hasTriggeredPreload = false
    private var hasTriggeredFade = false

    // MARK: - Callbacks (wired by AudioPlayer)

    /// Ask AudioPlayer for the next song to crossfade into
    var onPreloadNeeded: (() -> Song?)?
    /// Ask AudioPlayer to fetch a playback URL for the song
    var onFetchPlaybackURL: ((Song) async throws -> (URL, Double))?
    /// Notify AudioPlayer that crossfade completed — hand off to PlaybackService
    /// Parameters: (song, player, playerItem, expectedDuration)
    var onCrossfadeCompleted: ((Song, AVPlayer, AVPlayerItem, Double) -> Void)?

    // MARK: - Monitoring

    /// Called from the time observer. Triggers preload and fade based on position.
    func startMonitoring(currentTime: Double, duration: Double) {
        guard settings.isEnabled else { return }
        guard duration > 0 else { return }

        fadeDuration = settings.fadeDuration

        // Skip crossfade for short tracks (less than 3x fade duration)
        guard duration >= fadeDuration * 3 else { return }

        let remaining = duration - currentTime

        // Trigger preload at preloadLeadTime before end
        if remaining <= preloadLeadTime && !hasTriggeredPreload && state == .idle {
            hasTriggeredPreload = true
            triggerPreload()
        }

        // Trigger fade at fadeDuration before end
        if remaining <= fadeDuration && !hasTriggeredFade && state == .ready {
            hasTriggeredFade = true
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
                    self.state = .ready
                    Logger.log("Crossfade: \(nextSong.title) ready for fade", category: .playback)
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

    // MARK: - Fade

    private func triggerFade() {
        guard state == .ready else { return }
        state = .fading

        // Begin background task to keep fade running if app is backgrounded
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "CrossfadeTransition") { [weak self] in
            self?.cancelCrossfade()
        }

        // Start the incoming track playing
        slot.play()

        Logger.log("Crossfade: starting \(fadeDuration)s fade", category: .playback)

        fadeStartTime = Date()

        // 60Hz timer on a background queue
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.fadeTimerTick()
            }
        }
        timer.resume()
        fadeTimer = timer
    }

    private func fadeTimerTick() {
        guard state == .fading, let startTime = fadeStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / fadeDuration)

        // Equal-power crossfade curves
        let outGain = Float(cos(progress * .pi / 2))
        let inGain = Float(sin(progress * .pi / 2))

        AudioEngineService.shared.setCrossfadeVolumes(outGain: outGain, inGain: inGain)

        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    // MARK: - Complete

    private func completeCrossfade() {
        guard state == .fading else { return }
        state = .completing

        // Stop fade timer
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeStartTime = nil

        Logger.log("Crossfade: fade complete, swapping slots", category: .playback)

        // Swap active slot in AudioEngineService
        AudioEngineService.shared.swapActiveSlot()
        AudioEngineService.shared.resetToSingleTrack()

        // Hand off the now-active player to PlaybackService
        if let song = preloadedSong, let (player, item) = slot.handOffPlayer() {
            onCrossfadeCompleted?(song, player, item, preloadedDuration)
        }

        // Flush the old (now standby) ring buffer
        AudioEngineService.shared.flushStandby()

        // End background task
        endBackgroundTask()

        resetToIdle()
    }

    // MARK: - Cancel

    /// Cancel any in-progress crossfade and reset to normal single-track playback
    func cancelCrossfade() {
        guard state != .idle else { return }

        Logger.log("Crossfade: cancelling (was \(state.rawValue))", category: .playback)

        // Stop fade timer
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeStartTime = nil

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
        if state == .preloading || state == .ready {
            Logger.log("Crossfade: queue changed, cancelling preload", category: .playback)
            cancelCrossfade()
        }
    }

    /// Whether the engine is actively in a fade transition
    var isFading: Bool {
        state == .fading || state == .completing
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
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}
