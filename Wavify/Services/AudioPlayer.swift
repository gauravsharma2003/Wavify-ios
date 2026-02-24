//
//  AudioPlayer.swift
//  Wavify
//
//  Coordinator for audio playback, delegating to focused services
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import Observation
import UIKit

// MARK: - Loop Mode

enum LoopMode: String, CaseIterable {
    case none = "No Loop"
    case one = "Loop One"
    case all = "Loop All"
    
    var icon: String {
        switch self {
        case .none: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
    
    func next() -> LoopMode {
        switch self {
        case .none: return .all
        case .all: return .one
        case .one: return .none
        }
    }
}

@MainActor
@Observable
class AudioPlayer {
    static let shared = AudioPlayer()
    
    // MARK: - Observable Properties (Public API unchanged)
    
    var isPlaying = false
    var currentSong: Song?
    var currentTime: Double = 0
    var duration: Double = 0
    var isLoading = false
    var isBuffering = false
    
    // Queue state (delegated to QueueManager)
    var queue: [Song] {
        get { queueManager.queue }
        set { queueManager.queue = newValue }
    }
    
    var currentIndex: Int {
        get { queueManager.currentIndex }
        set { queueManager.currentIndex = newValue }
    }
    
    var userQueue: [Song] {
        get { queueManager.userQueue }
        set { queueManager.userQueue = newValue }
    }
    
    var userQueueIds: Set<String> {
        queueManager.userQueueIds
    }
    
    var isPlayingFromAlbum: Bool {
        get { queueManager.isPlayingFromAlbum }
        set { queueManager.isPlayingFromAlbum = newValue }
    }
    
    // Shuffle/Loop state (delegated to ShuffleController)
    var isShuffleMode: Bool {
        get { shuffleController.isShuffleMode }
        set { 
            if newValue {
                shuffleController.enableShuffle(queueSize: queue.count, currentIndex: currentIndex)
            } else {
                shuffleController.disableShuffle()
            }
        }
    }
    
    var loopMode: LoopMode {
        get { shuffleController.loopMode }
        set { shuffleController.loopMode = newValue }
    }
    
    // MARK: - Services

    private let queueManager = QueueManager()
    private let shuffleController = ShuffleController()
    private let playbackService = PlaybackService()
    private let networkManager = NetworkManager.shared
    private let sharePlayManager = SharePlayManager.shared
    private let playbackTracker = PlaybackTracker()

    // MARK: - Crossfade

    private(set) var crossfadeEngine: CrossfadeEngine?
    private let crossfadeSettings = CrossfadeSettings.shared

    /// Flag to prevent duplicate song end handling
    private var isHandlingSongEnd = false
    /// Timestamp of last handled song end — debounces double-triggers from
    /// the fallback timer and AVPlayerItemDidPlayToEndTime firing for the same ending
    private var lastSongEndHandledAt: Date = .distantPast

    // MARK: - Initialization

    private init() {
        setupPlaybackService()
        setupCrossfadeEngine()
        setupRemoteCommandCenter()
        setupNotifications()
        restoreLastSession()
    }

    private func setupPlaybackService() {
        playbackService.onPlayPauseChanged = { [weak self] playing in
            self?.isPlaying = playing
            self?.updateNowPlayingInfo()
        }
        
        playbackService.onTimeUpdated = { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time
            // Periodically save position (every 5 seconds)
            if Int(time) % 5 == 0 {
                self.saveCurrentPosition()
            }
            // Feed crossfade engine for preload/fade timing
            if self.crossfadeSettings.isEnabled {
                self.crossfadeEngine?.startMonitoring(currentTime: time, duration: self.duration)
            }
            // Report playback time for analytics
            Task { await self.playbackTracker.reportTime(currentTime: time) }
        }
        
        // Fallback song end handler for when AVPlayerItemDidPlayToEndTime doesn't fire
        playbackService.onSongEnded = { [weak self] in
            Task { @MainActor in
                guard let self = self, !self.isHandlingSongEnd else { return }
                // If crossfade engine is actively fading, it handles the transition
                if self.crossfadeEngine?.isFading == true { return }
                // Debounce: ignore if a song end was already handled within the last second
                if Date().timeIntervalSince(self.lastSongEndHandledAt) < 1.0 { return }
                self.isHandlingSongEnd = true
                self.lastSongEndHandledAt = Date()
                await self.playbackTracker.stopTracking()
                await self.playNext()
                self.isHandlingSongEnd = false
            }
        }

        playbackService.onReady = { [weak self] dur in
            guard let self = self else { return }
            self.duration = dur
            self.isLoading = false
            // Update NowPlaying with real duration (important for cloud tracks where duration starts as 0)
            if dur > 0 {
                self.updateNowPlayingInfo()
            }
            // For cloud tracks: persist learned duration and pre-fetch next song
            if let song = self.currentSong, self.isCloudSong(song), dur > 0 {
                let fileId = self.cloudFileId(from: song)
                CloudLibraryManager.shared.updateTrackDuration(fileId: fileId, duration: dur)
                self.prefetchNextCloudTrack()
            }
        }
        
        playbackService.onFailed = { [weak self] _ in
            self?.isLoading = false
            self?.isBuffering = false
            // Invalidate cached playback URL so next attempt gets a fresh one (YouTube only)
            if let song = self?.currentSong, self?.isCloudSong(song) != true {
                let videoId = song.videoId
                Task {
                    await self?.networkManager.invalidatePlaybackCache(videoId: videoId)
                    await YouTubeStreamExtractor.shared.invalidateCache(videoId: videoId)
                }
            }
        }
        
        playbackService.onBufferingChanged = { [weak self] buffering in
            self?.isBuffering = buffering
        }
        
        // Retry callback - fetch fresh URL when playback fails (handles expired URLs)
        playbackService.onRetryNeeded = { [weak self] completion in
            guard let self = self, let song = self.currentSong else {
                completion(nil)
                return
            }

            // Cloud songs: don't retry through YouTube — just skip retries
            // (the file extension fix should resolve the root cause)
            if self.isCloudSong(song) {
                Logger.warning("Cloud song retry skipped — replaying via playCloudSong", category: .playback)
                Task { @MainActor in
                    await self.playCloudSong(song)
                }
                completion(nil)
                return
            }

            Task { @MainActor in
                do {
                    // Invalidate all caches to ensure truly fresh URL
                    await self.networkManager.invalidatePlaybackCache(videoId: song.videoId)
                    await YouTubeStreamExtractor.shared.invalidateCache(videoId: song.videoId)
                    Logger.log("Requesting fresh URL for retry: \(song.title)", category: .playback)
                    let playbackInfo = try await self.networkManager.getPlaybackInfo(videoId: song.videoId)
                    if let freshUrl = URL(string: playbackInfo.audioUrl) {
                        Logger.log("Got fresh URL: \(freshUrl.absoluteString.prefix(50))...", category: .playback)
                        completion(freshUrl)
                    } else {
                        Logger.warning("Fresh URL invalid", category: .playback)
                        completion(nil)
                    }
                } catch {
                    Logger.warning("Failed to get fresh URL for retry: \(error.localizedDescription)", category: .playback)
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Crossfade Engine Setup

    private func setupCrossfadeEngine() {
        let engine = CrossfadeEngine()

        engine.onPreloadNeeded = { [weak self] in
            return self?.resolveNextSong()
        }

        engine.onFetchPlaybackURL = { [weak self] song in
            guard let self = self else {
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "AudioPlayer deallocated"])
            }

            // Cloud songs: use cached file or download to cache first
            if self.isCloudSong(song) {
                let fileId = self.cloudFileId(from: song)

                // Check cache first
                if let cachedURL = await CloudTrackCache.shared.cachedURL(for: fileId) {
                    return (cachedURL, 0)
                }

                // Download to cache, then return local URL
                let token = try await CloudAuthManager.shared.getAccessToken()
                let ext = self.cloudFileExtension(from: song)
                await CloudTrackCache.shared.downloadAndCache(fileId: fileId, ext: ext, accessToken: token)

                if let cachedURL = await CloudTrackCache.shared.cachedURL(for: fileId) {
                    return (cachedURL, 0)
                }

                // Fallback: stream directly (CrossfadePlayerSlot doesn't support headers,
                // so this won't work for auth-required URLs — but cache should have succeeded)
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cache cloud track for crossfade"])
            }

            let playbackInfo = try await self.networkManager.getPlaybackInfo(videoId: song.videoId)
            guard let url = URL(string: playbackInfo.audioUrl) else {
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"])
            }
            let expectedDuration = Double(playbackInfo.duration) ?? Double(song.duration) ?? 0
            return (url, expectedDuration)
        }

        engine.onGetActiveTapContext = { [weak self] in
            return self?.playbackService.activeTapContext
        }

        engine.onCrossfadeCompleted = { [weak self] song, player, item, expectedDuration in
            guard let self = self else { return }
            Logger.log("Crossfade: completed, adopting \(song.title)", category: .playback)
            Task { await self.playbackTracker.stopTracking() }

            // Advance queue to the crossfaded song
            self.advanceQueueForCrossfade(to: song)

            // Read actual playback position from the adopted player
            // (it's been playing during the crossfade, so it's ahead of 0)
            let actualTime = player.currentTime().seconds
            let validTime = actualTime.isNaN ? 0 : actualTime

            // For cloud songs, expectedDuration may be 0 — read from player item
            var resolvedDuration = expectedDuration
            if resolvedDuration <= 0 {
                let itemDur = item.duration
                if itemDur.isNumeric && !itemDur.seconds.isNaN && itemDur.seconds > 0 {
                    resolvedDuration = itemDur.seconds
                }
            }

            // Update current song state
            self.currentSong = song
            self.duration = resolvedDuration
            self.currentTime = validTime

            // Adopt the player — PlaybackService takes over without stopping audio
            self.playbackService.adoptPlayer(player, playerItem: item, duration: resolvedDuration)

            self.updateNowPlayingInfo()

            // Save to widget
            LastPlayedSongManager.shared.saveCurrentSong(song, isPlaying: true, currentTime: validTime, totalDuration: resolvedDuration)

            // For cloud tracks: persist duration and pre-fetch next
            if self.isCloudSong(song) && resolvedDuration > 0 {
                let fileId = self.cloudFileId(from: song)
                CloudLibraryManager.shared.updateTrackDuration(fileId: fileId, duration: resolvedDuration)
                self.prefetchNextCloudTrack()
            }

            // Notify for play count tracking
            NotificationCenter.default.post(
                name: .songDidStartPlaying,
                object: nil,
                userInfo: ["song": song]
            )

            // Ensure queue doesn't run out (skip for guests — host syncs queue)
            if !self.sharePlayManager.isGuest {
                self.queueManager.checkAndAppendIfNeeded(loopMode: self.shuffleController.loopMode, currentSong: song)
            }

            // SharePlay broadcast
            self.sharePlayManager.broadcastTrackChange(song: song)
        }

        crossfadeEngine = engine
    }

    /// Peek at the next song respecting shuffle/loop WITHOUT advancing the queue
    private func resolveNextSong() -> Song? {
        guard !queue.isEmpty else { return nil }

        // Loop one: don't crossfade into the same song
        if shuffleController.loopMode == .one {
            return nil
        }

        // Shuffle mode
        if shuffleController.isShuffleMode {
            if let nextIndex = shuffleController.peekNextShuffleIndex() {
                return queue[safe: nextIndex]
            }
            return nil
        }

        // Normal mode
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            return queue[safe: nextIndex]
        }

        // Loop all wraps around
        if shuffleController.loopMode == .all {
            return queue.first
        }

        return nil
    }

    /// Advance queue index to match the crossfaded song (without triggering playback)
    private func advanceQueueForCrossfade(to song: Song) {
        if shuffleController.isShuffleMode {
            if let nextIndex = shuffleController.getNextShuffleIndex() {
                queueManager.jumpToIndex(nextIndex)
            }
        } else {
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                queueManager.jumpToIndex(nextIndex)
            } else if shuffleController.loopMode == .all {
                queueManager.loopToStart()
            }
        }
        // Always consume from userQueue to prevent duplicates on next rebuild
        queueManager.consumeFromUserQueue(songId: song.id)
    }

    // MARK: - Remote Command Center
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                await self?.playNext()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                await self?.playPrevious()
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Start background task to prevent iOS from suspending during song transition
            var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
            backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "SongTransition") {
                // Expiration handler
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
            }

            Task { @MainActor in
                guard let self = self, !self.isHandlingSongEnd else {
                    if backgroundTaskId != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    }
                    return
                }
                // If crossfade engine is actively fading, it handles the transition
                if self.crossfadeEngine?.isFading == true {
                    if backgroundTaskId != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    }
                    return
                }
                // Debounce: ignore if a song end was already handled within the last second
                // (prevents the fallback timer + notification double-trigger)
                if Date().timeIntervalSince(self.lastSongEndHandledAt) < 1.0 {
                    if backgroundTaskId != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    }
                    return
                }
                self.isHandlingSongEnd = true
                self.lastSongEndHandledAt = Date()
                await self.playNext()
                self.isHandlingSongEnd = false

                // End background task when done
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            Task { @MainActor in
                switch type {
                case .began:
                    self?.crossfadeEngine?.cancelCrossfade()
                    self?.pause()
                case .ended:
                    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) {
                            self?.play()
                        }
                    }
                @unknown default:
                    break
                }
            }
        }

        // Handle audio route changes (Bluetooth disconnect, headphones unplugged, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }

            Task { @MainActor in
                self?.handleRouteChange(reason: reason)
            }
        }
    }

    /// Handle audio route changes to prevent audio loss
    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones/Bluetooth disconnected - pause playback
            pause()
            // If AirPlay was active, route change back to local — re-attach tap
            playbackService.handleRouteChange()
        case .newDeviceAvailable, .routeConfigurationChange:
            // New device connected or route changed (e.g. AirPlay)
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Logger.error("Failed to reactivate audio session after route change", category: .playback, error: error)
            }
            // Toggle between AirPlay bypass and local engine mode
            playbackService.handleRouteChange()
        default:
            break
        }
    }
    
    // MARK: - Remote Playback (SharePlay)

    /// Called by SharePlayManager when host changes track — bypasses guest guard
    /// Uses refreshQueue: false because the host syncs the queue separately
    func applyRemoteTrackChange(song: Song, seekTo: Double? = nil, shouldPlay: Bool = true) async {
        guard !song.videoId.isEmpty else { return }
        await playNewSong(song, refreshQueue: false, autoPlay: shouldPlay, seekTo: seekTo)
    }

    // MARK: - Playback Control (Public API)

    /// Play a new song from search/browse - creates fresh queue
    func loadAndPlay(song: Song) async {
        // SharePlay guest guard — listeners can't initiate playback
        guard !sharePlayManager.isGuest else {
            ToastManager.shared.show(icon: "ear", text: "You're vibing with the host. Leave the session to DJ yourself.")
            return
        }
        guard !song.videoId.isEmpty else {
            Logger.warning("Attempted to play song with empty videoId", category: .playback)
            return
        }
        await playNewSong(song, refreshQueue: true)
    }
    
    /// Play a song by videoId only (for deep links)
    func loadAndPlay(videoId: String) async {
        // SharePlay guest guard — listeners can't initiate playback
        guard !sharePlayManager.isGuest else {
            ToastManager.shared.show(icon: "ear", text: "You're vibing with the host. Leave the session to DJ yourself.")
            return
        }
        guard !videoId.isEmpty else {
            Logger.warning("Attempted to play with empty videoId", category: .playback)
            return
        }
        isLoading = true
        
        do {
            let playbackInfo = try await networkManager.getPlaybackInfo(videoId: videoId)
            
            let song = Song(
                id: videoId,
                title: playbackInfo.title,
                artist: playbackInfo.artist,
                thumbnailUrl: playbackInfo.thumbnailUrl,
                duration: playbackInfo.duration,
                artistId: playbackInfo.artistId,
                albumId: playbackInfo.albumId
            )
            
            await loadAndPlay(song: song)
        } catch {
            isLoading = false
            Logger.error("Failed to load song from deep link", category: .playback, error: error)
        }
    }
    
    /// Internal method to play a song
    private func playNewSong(_ song: Song, refreshQueue: Bool, autoPlay: Bool = true, seekTo: Double? = nil) async {
        // Route cloud songs through the Drive pipeline
        if isCloudSong(song) {
            await playCloudSong(song, autoPlay: autoPlay)
            return
        }

        // Start background task
        let taskId = UIApplication.shared.beginBackgroundTask { }
        defer { UIApplication.shared.endBackgroundTask(taskId) }

        isLoading = true
        currentSong = song

        // Notify for play count tracking
        NotificationCenter.default.post(
            name: .songDidStartPlaying,
            object: nil,
            userInfo: ["song": song]
        )

        do {
            let playbackInfo = try await networkManager.getPlaybackInfo(videoId: song.videoId)

            guard let url = URL(string: playbackInfo.audioUrl) else {
                throw NSError(domain: "AudioPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"])
            }

            let expectedDuration = Double(playbackInfo.duration) ?? Double(song.duration) ?? 0
            duration = expectedDuration

            // Update artist/album IDs from API response if needed
            if var updatedSong = currentSong {
                let needsArtistIdUpdate = playbackInfo.artistId != nil && (
                    updatedSong.artistId == nil ||
                    (updatedSong.artistId?.hasPrefix("MPREb_") == true) ||
                    (updatedSong.artistId?.hasPrefix("VL") == true)
                )
                let needsAlbumIdUpdate = updatedSong.albumId == nil && playbackInfo.albumId != nil

                if needsArtistIdUpdate || needsAlbumIdUpdate {
                    updatedSong = Song(
                        id: updatedSong.id,
                        title: updatedSong.title,
                        artist: updatedSong.artist,
                        thumbnailUrl: updatedSong.thumbnailUrl,
                        duration: updatedSong.duration,
                        isLiked: updatedSong.isLiked,
                        artistId: needsArtistIdUpdate ? playbackInfo.artistId : updatedSong.artistId,
                        albumId: updatedSong.albumId ?? playbackInfo.albumId
                    )
                    self.currentSong = updatedSong
                }
            }

            // Play via PlaybackService (AVPlayer) - supports background audio
            Logger.log("Loading AVPlayer: \(url.host ?? "nil") | itag in URL: \(url.query?.contains("itag=140") == true ? "140" : "other")", category: .playback)
            playbackService.load(
                url: url,
                expectedDuration: expectedDuration,
                autoPlay: autoPlay,
                seekTo: seekTo
            )

            // Start playback tracking for artist play counts
            await playbackTracker.startTracking(info: playbackInfo)

            Logger.log("Playing via native AVPlayer: \(song.title)", category: .playback)

            // Handle queue (skip for guests — host syncs queue)
            if !sharePlayManager.isGuest {
                if refreshQueue {
                    await queueManager.loadRelatedSongs(videoId: song.videoId, replaceQueue: true, currentSong: song)
                } else {
                    queueManager.checkAndAppendIfNeeded(loopMode: shuffleController.loopMode, currentSong: song)
                }
            }

            // Fetch album info if missing (runs concurrently, doesn't block playback)
            if currentSong?.albumId == nil {
                let videoId = song.videoId
                let songTitle = song.title
                let songArtist = song.artist
                Task {
                    if let albumInfo = try? await networkManager.getSongAlbumInfo(videoId: videoId, title: songTitle, artist: songArtist),
                       currentSong?.videoId == videoId, currentSong?.albumId == nil {
                        currentSong?.albumId = albumInfo.albumId
                        // Persist so it's available on next app launch
                        if let updatedSong = currentSong {
                            LastPlayedSongManager.shared.saveCurrentSong(updatedSong, isPlaying: isPlaying, currentTime: currentTime, totalDuration: duration)
                        }
                    }
                }
            }

            updateNowPlayingInfo()

            // Save to widget shared data with duration
            if let song = currentSong {
                LastPlayedSongManager.shared.saveCurrentSong(song, isPlaying: autoPlay, currentTime: seekTo ?? 0, totalDuration: duration)
            }

            // SharePlay: broadcast track change and queue state to guests
            sharePlayManager.broadcastTrackChange(song: song)
            sharePlayManager.broadcastQueueSync()

        } catch {
            isLoading = false
            Logger.error("Failed to load playback info", category: .playback, error: error)
        }
    }
    
    func play() {
        // SharePlay guest guard — only host or remote-applied commands can play
        guard !sharePlayManager.isGuest || sharePlayManager.isApplyingRemoteState else { return }

        // Check if we have a song but no audio loaded (restored session)
        if currentSong != nil && !playbackService.isAudioLoaded {
            Task {
                await resumeRestoredSession()
            }
            return
        }

        playbackService.play()
        LastPlayedSongManager.shared.updatePlayState(isPlaying: true)
        sharePlayManager.broadcastPlaybackState(isPlaying: true, currentTime: currentTime)
    }

    func pause() {
        guard !sharePlayManager.isGuest || sharePlayManager.isApplyingRemoteState else { return }
        playbackService.pause()
        LastPlayedSongManager.shared.updatePlaybackState(isPlaying: false, currentTime: currentTime)
        sharePlayManager.broadcastPlaybackState(isPlaying: false, currentTime: currentTime)
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        guard !sharePlayManager.isGuest || sharePlayManager.isApplyingRemoteState else { return }
        playbackService.seek(to: time)
        currentTime = time
        updateNowPlayingInfo()
        sharePlayManager.broadcastSeek(to: time)

        // Cancel crossfade if user seeks backward past the trigger point
        let remaining = duration - time
        if remaining > 20, crossfadeEngine?.isActive == true, crossfadeEngine?.isFading == false {
            crossfadeEngine?.cancelCrossfade()
        }
    }
    
    func playNext() async {
        guard !sharePlayManager.isGuest || sharePlayManager.isApplyingRemoteState else { return }
        guard !queue.isEmpty else { return }

        // Cancel any in-progress crossfade — user skip takes priority
        if crossfadeEngine?.isActive == true {
            crossfadeEngine?.cancelCrossfade()
        }

        // Handle shuffle mode
        if shuffleController.isShuffleMode {
            if let nextIndex = shuffleController.getNextShuffleIndex() {
                queueManager.jumpToIndex(nextIndex)
                if let song = queue[safe: nextIndex] {
                    queueManager.consumeFromUserQueue(songId: song.id)
                    await playNewSong(song, refreshQueue: false)
                }
                return
            }
        }
        
        // Handle loop modes
        switch shuffleController.loopMode {
        case .one:
            // Reload the song fresh instead of seeking on the exhausted player item.
            // Seeking back on a completed streaming item is unreliable — the URL
            // may need re-buffering and the tap/engine state can become stale.
            if let song = currentSong {
                await playNewSong(song, refreshQueue: false)
            }
            return

        case .all:
            if let _ = queueManager.moveToNext() {
                if let song = queue[safe: currentIndex] {
                    await playNewSong(song, refreshQueue: false)
                }
            } else {
                queueManager.loopToStart()
                if let song = queue.first {
                    await playNewSong(song, refreshQueue: false)
                }
            }
            
        case .none:
            if let _ = queueManager.moveToNext() {
                if let song = queue[safe: currentIndex] {
                    await playNewSong(song, refreshQueue: false)
                }
            } else if !queueManager.isPlayingFromAlbum {
                queueManager.checkAndAppendIfNeeded(loopMode: .none, currentSong: currentSong)
            }
        }
    }
    
    func playPrevious() async {
        guard !sharePlayManager.isGuest || sharePlayManager.isApplyingRemoteState else { return }
        if currentTime > 3 {
            seek(to: 0)
        } else if shuffleController.isShuffleMode {
            if let prevIndex = shuffleController.getPreviousShuffleIndex() {
                queueManager.jumpToIndex(prevIndex)
                if let song = queue[safe: prevIndex] {
                    await playNewSong(song, refreshQueue: false)
                }
            } else {
                seek(to: 0)
            }
        } else if let _ = queueManager.moveToPrevious() {
            if let song = queue[safe: currentIndex] {
                await playNewSong(song, refreshQueue: false)
            }
        } else if shuffleController.loopMode == .all && !queue.isEmpty {
            queueManager.jumpToIndex(queue.count - 1)
            if let song = queue.last {
                await playNewSong(song, refreshQueue: false)
            }
        } else {
            seek(to: 0)
        }
    }
    
    func playFromQueue(at index: Int) async {
        guard !sharePlayManager.isGuest else {
            ToastManager.shared.show(icon: "ear", text: "You're vibing with the host. Leave the session to DJ yourself.")
            return
        }
        guard queueManager.jumpToIndex(index) else { return }
        shuffleController.syncShuffleIndex(to: index)
        
        if let song = queue[safe: index] {
            await playNewSong(song, refreshQueue: false)
        }
    }
    
    func toggleLoopMode() {
        shuffleController.toggleLoopMode()
        
        if shuffleController.loopMode == .all {
            if let current = currentSong, !current.isRecommendation {
                queueManager.removeRecommendations(keepingSongId: current.id)
            }
        } else if shuffleController.loopMode == .none {
            queueManager.checkAndAppendIfNeeded(loopMode: .none, currentSong: currentSong)
        }
    }
    
    // MARK: - User Queue Management
    
    func playNextSong(_ song: Song) {
        guard !sharePlayManager.isGuest else {
            ToastManager.shared.show(icon: "ear", text: "Host controls the queue. Sit back and enjoy the ride.")
            return
        }
        queueManager.playNext(song)
        crossfadeEngine?.queueDidChange()
    }

    func addToQueue(_ song: Song) -> Bool {
        guard !sharePlayManager.isGuest else {
            ToastManager.shared.show(icon: "ear", text: "Host controls the queue. Sit back and enjoy the ride.")
            return false
        }
        return queueManager.addToQueue(song)
    }
    
    func isInQueue(_ song: Song) -> Bool {
        queueManager.isInQueue(song)
    }

    func moveQueueItem(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !sharePlayManager.isGuest else { return }
        queueManager.moveItem(fromOffsets: source, toOffset: destination)
        crossfadeEngine?.queueDidChange()
    }

    func removeFromQueue(at index: Int) {
        guard !sharePlayManager.isGuest else { return }
        queueManager.removeFromQueue(at: index)
        crossfadeEngine?.queueDidChange()
    }

    /// Move song to play next. Returns false if already next (meaning: play it now)
    func moveToPlayNext(fromIndex index: Int) -> Bool {
        guard !sharePlayManager.isGuest else { return false }
        let result = queueManager.moveToPlayNext(fromIndex: index)
        crossfadeEngine?.queueDidChange()
        return result
    }

    func replaceUpcomingQueue(with songs: [Song]) {
        guard !sharePlayManager.isGuest else { return }
        queueManager.replaceUpcoming(with: songs)
        crossfadeEngine?.queueDidChange()
    }

    // MARK: - Cloud Playback

    /// Whether a song is a cloud (Google Drive) track
    private func isCloudSong(_ song: Song) -> Bool {
        song.id.hasPrefix("cloud_")
    }

    /// Extract the Drive file ID from a cloud song's id
    private func cloudFileId(from song: Song) -> String {
        String(song.id.dropFirst("cloud_".count))
    }

    /// Get the file extension for a cloud song (e.g. "flac", "mp3")
    private func cloudFileExtension(from song: Song) -> String {
        let fileId = cloudFileId(from: song)
        return CloudLibraryManager.shared.trackFileExtension(for: fileId)
    }

    /// Pre-fetch the next cloud track in queue to cache for instant playback
    private func prefetchNextCloudTrack() {
        guard let nextSong = resolveNextSong(), isCloudSong(nextSong) else { return }
        let fileId = cloudFileId(from: nextSong)
        let ext = cloudFileExtension(from: nextSong)
        Task.detached(priority: .utility) {
            // Only fetch if not already cached
            guard await CloudTrackCache.shared.cachedURL(for: fileId) == nil else { return }
            do {
                let token = try await CloudAuthManager.shared.getAccessToken()
                await CloudTrackCache.shared.downloadAndCache(fileId: fileId, ext: ext, accessToken: token)
                Logger.log("Cloud: pre-fetched next track \(nextSong.title)", category: .playback)
            } catch {
                // Best-effort, don't block
            }
        }
    }

    /// Play a cloud track, optionally setting up the queue from pre-built songs
    func loadAndPlayCloudTrack(song: Song, queueSongs: [Song]? = nil, startIndex: Int? = nil) async {
        // Set up queue if songs provided
        if let queueSongs = queueSongs, !queueSongs.isEmpty {
            let idx = startIndex ?? 0
            queueManager.setAlbumQueue(songs: queueSongs, startIndex: idx)
            shuffleController.disableShuffle()
        }

        await playCloudSong(song)
    }

    /// Internal: play a cloud song by its Song object (extracts file ID from song.id)
    private func playCloudSong(_ song: Song, autoPlay: Bool = true) async {
        let taskId = UIApplication.shared.beginBackgroundTask { }
        defer { UIApplication.shared.endBackgroundTask(taskId) }

        isLoading = true
        currentSong = song

        let fileId = cloudFileId(from: song)

        // Check local cache first for instant playback
        if let cachedURL = await CloudTrackCache.shared.cachedURL(for: fileId) {
            duration = 0
            playbackService.load(
                url: cachedURL,
                expectedDuration: 0,
                autoPlay: autoPlay
            )

            updateNowPlayingInfo()
            LastPlayedSongManager.shared.saveCurrentSong(song, isPlaying: autoPlay, currentTime: 0, totalDuration: duration)
            NotificationCenter.default.post(name: .songDidStartPlaying, object: nil, userInfo: ["song": song])
            return
        }

        // Stream from Drive and cache in background
        do {
            let token = try await CloudAuthManager.shared.getAccessToken()

            guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media") else {
                isLoading = false
                return
            }

            duration = 0
            playbackService.load(
                url: url,
                expectedDuration: 0,
                autoPlay: autoPlay,
                headers: ["Authorization": "Bearer \(token)"]
            )

            updateNowPlayingInfo()
            LastPlayedSongManager.shared.saveCurrentSong(song, isPlaying: autoPlay, currentTime: 0, totalDuration: duration)
            NotificationCenter.default.post(name: .songDidStartPlaying, object: nil, userInfo: ["song": song])

            // Download and cache in background for next time
            let cacheToken = token
            let ext = cloudFileExtension(from: song)
            Task.detached(priority: .utility) {
                await CloudTrackCache.shared.downloadAndCache(fileId: fileId, ext: ext, accessToken: cacheToken)
            }

        } catch {
            isLoading = false
            Logger.error("Failed to play cloud track", category: .playback, error: error)
        }
    }

    // MARK: - Album/Playlist Playback

    func playAlbum(songs: [Song], startIndex: Int = 0, shuffle: Bool = false) async {
        guard !sharePlayManager.isGuest else {
            ToastManager.shared.show(icon: "ear", text: "You're vibing with the host. Leave the session to DJ yourself.")
            return
        }
        if shuffle {
            var shuffledSongs = songs
            shuffledSongs.shuffle()
            queueManager.setAlbumQueue(songs: shuffledSongs, startIndex: 0)
            shuffleController.enableShuffleForPreShuffledQueue(queueSize: shuffledSongs.count)
        } else {
            queueManager.setAlbumQueue(songs: songs, startIndex: startIndex)
            shuffleController.disableShuffle()
        }

        if let song = queue[safe: currentIndex] {
            await playNewSong(song, refreshQueue: false)
        }
    }
    
    // MARK: - Now Playing Info
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        playbackService.updateNowPlayingInfo(
            song: song,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration
        )
    }
    
    // MARK: - Session Persistence
    
    /// Restore the last played song on app launch (shows in mini player)
    private func restoreLastSession() {
        guard let lastSession = LastPlayedSongManager.shared.loadSharedData() else { return }

        // Restore the song to show in mini player (but don't play)
        let restoredSong = lastSession.toSong()
        currentSong = restoredSong
        currentTime = lastSession.currentTime
        duration = lastSession.totalDuration
        isPlaying = false // Don't auto-play, just restore state

        // Update the now playing info so lock screen/control center shows correct info
        updateNowPlayingInfo()

        // Cloud songs: skip YouTube-dependent operations
        if isCloudSong(restoredSong) { return }

        // Populate the queue in background so "Up Next" is ready without waiting for play
        Task {
            await queueManager.loadRelatedSongs(
                videoId: restoredSong.videoId,
                replaceQueue: true,
                currentSong: restoredSong
            )
        }

        // Fetch album info if missing from restored session
        if restoredSong.albumId == nil {
            Task {
                if let albumInfo = try? await networkManager.getSongAlbumInfo(videoId: restoredSong.videoId, title: restoredSong.title, artist: restoredSong.artist),
                   currentSong?.videoId == restoredSong.videoId, currentSong?.albumId == nil {
                    currentSong?.albumId = albumInfo.albumId
                    if let updatedSong = currentSong {
                        LastPlayedSongManager.shared.saveCurrentSong(updatedSong, isPlaying: false, currentTime: currentTime, totalDuration: duration)
                    }
                }
            }
        }
    }
    
    /// Resume playback of the restored session (called when user taps play on mini player)
    func resumeRestoredSession() async {
        guard let song = currentSong else { return }

        // If we have a restored song but no audio loaded, load it with seek position
        if !playbackService.isAudioLoaded {
            // Cloud songs: play via cloud pipeline (no YouTube)
            if isCloudSong(song) {
                await playCloudSong(song)
                return
            }

            let savedPosition = LastPlayedSongManager.shared.loadSharedData()?.currentTime ?? 0
            await loadAndPlayWithSeek(song: song, seekTo: savedPosition)
        } else {
            play()
        }
    }
    
    /// Load and play a song, seeking to a specific position before playback starts
    private func loadAndPlayWithSeek(song: Song, seekTo: Double) async {
        isLoading = true
        currentSong = song
        
        do {
            let playbackInfo = try await networkManager.getPlaybackInfo(videoId: song.videoId)
            
            guard let url = URL(string: playbackInfo.audioUrl) else {
                isLoading = false
                return
            }
            
            let apiDuration = Double(playbackInfo.duration) ?? 0
            
            // Load audio with seek position
            playbackService.load(
                url: url,
                expectedDuration: apiDuration,
                autoPlay: true,
                seekTo: seekTo
            )
            duration = apiDuration
            
            updateNowPlayingInfo()
            
            // Fetch related songs for the queue (so next/prev work)
            await queueManager.loadRelatedSongs(videoId: song.videoId, replaceQueue: true, currentSong: song)
            
            // Save to widget shared data
            if let song = currentSong {
                LastPlayedSongManager.shared.saveCurrentSong(song, isPlaying: true, currentTime: seekTo, totalDuration: duration)
            }
            
        } catch {
            isLoading = false
            Logger.error("Failed to load playback info for resume", category: .playback, error: error)
        }
    }
    
    /// Save current playback position (called periodically and on pause)
    private func saveCurrentPosition() {
        guard currentSong != nil else { return }
        LastPlayedSongManager.shared.updateCurrentTime(currentTime)
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Time Formatting Extension

extension Double {
    var formattedTime: String {
        guard !self.isNaN && !self.isInfinite else { return "0:00" }
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
