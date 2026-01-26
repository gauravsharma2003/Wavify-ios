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

    /// Flag to prevent duplicate song end handling
    private var isHandlingSongEnd = false
    
    // MARK: - Initialization
    
    private init() {
        setupPlaybackService()
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
            self?.currentTime = time
            // Periodically save position (every 5 seconds)
            if Int(time) % 5 == 0 {
                self?.saveCurrentPosition()
            }
        }
        
        // Fallback song end handler for when AVPlayerItemDidPlayToEndTime doesn't fire
        playbackService.onSongEnded = { [weak self] in
            Task { @MainActor in
                guard let self = self, !self.isHandlingSongEnd else { return }
                self.isHandlingSongEnd = true
                await self.playNext()
                self.isHandlingSongEnd = false
            }
        }

        playbackService.onReady = { [weak self] dur in
            self?.duration = dur
            self?.isLoading = false
        }
        
        playbackService.onFailed = { [weak self] _ in
            self?.isLoading = false
            self?.isBuffering = false
            // Invalidate cached playback URL so next attempt gets a fresh one
            if let videoId = self?.currentSong?.videoId {
                Task {
                    await self?.networkManager.invalidatePlaybackCache(videoId: videoId)
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

            Task { @MainActor in
                do {
                    // Invalidate cache before fetching to ensure truly fresh URL
                    await self.networkManager.invalidatePlaybackCache(videoId: song.videoId)
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
                self.isHandlingSongEnd = true
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
        case .newDeviceAvailable, .routeConfigurationChange:
            // New device connected or route changed - ensure audio session is active
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Logger.error("Failed to reactivate audio session after route change", category: .playback, error: error)
            }
        default:
            break
        }
    }
    
    // MARK: - Playback Control (Public API)
    
    /// Play a new song from search/browse - creates fresh queue
    func loadAndPlay(song: Song) async {
        guard !song.videoId.isEmpty else {
            Logger.warning("Attempted to play song with empty videoId", category: .playback)
            return
        }
        await playNewSong(song, refreshQueue: true)
    }
    
    /// Play a song by videoId only (for deep links)
    func loadAndPlay(videoId: String) async {
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
    private func playNewSong(_ song: Song, refreshQueue: Bool) async {
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
                isLoading = false
                return
            }

            let apiDuration = Double(playbackInfo.duration) ?? 0
            
            // Update IDs if needed
            // Always prefer playbackInfo.artistId (from channelId) as it's the correct artist channel
            // Cached artistId might be wrong (e.g., album ID instead of artist ID)
            if var updatedSong = currentSong {
                let needsArtistIdUpdate = playbackInfo.artistId != nil && (
                    updatedSong.artistId == nil ||
                    // Fix cached invalid artistId (album ID starts with MPREb_, artist ID starts with UC)
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
            
            // Load audio
            playbackService.load(
                url: url,
                expectedDuration: apiDuration,
                headers: YouTubeAPIContext.playbackHeaders
            )
            duration = apiDuration
            
            // Handle queue
            if refreshQueue {
                await queueManager.loadRelatedSongs(videoId: song.videoId, replaceQueue: true, currentSong: song)
            } else {
                queueManager.checkAndAppendIfNeeded(loopMode: shuffleController.loopMode, currentSong: song)
            }
            
            updateNowPlayingInfo()
            
            // Save to widget shared data with duration
            if let song = currentSong {
                LastPlayedSongManager.shared.saveCurrentSong(song, isPlaying: true, currentTime: 0, totalDuration: duration)
            }
            
        } catch {
            isLoading = false
            Logger.error("Failed to load playback info", category: .playback, error: error)
        }
    }
    
    func play() {
        // Check if we have a song but no audio loaded (restored session)
        if currentSong != nil && !playbackService.isAudioLoaded {
            // Need to load the song first
            Task {
                await resumeRestoredSession()
            }
            return
        }
        
        playbackService.play()
        isPlaying = true
        updateNowPlayingInfo()
        LastPlayedSongManager.shared.updatePlayState(isPlaying: true)
    }
    
    func pause() {
        playbackService.pause()
        isPlaying = false
        updateNowPlayingInfo()
        // Save position when pausing for resume later
        LastPlayedSongManager.shared.updatePlaybackState(isPlaying: false, currentTime: currentTime)
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        playbackService.seek(to: time)
        currentTime = time
        updateNowPlayingInfo()
    }
    
    func playNext() async {
        guard !queue.isEmpty else { return }

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
            // Seek to start for instant looping
            playbackService.seekToStart()
            playbackService.play()
            isPlaying = true
            updateNowPlayingInfo()
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
        queueManager.playNext(song)
    }
    
    func addToQueue(_ song: Song) -> Bool {
        queueManager.addToQueue(song)
    }
    
    func isInQueue(_ song: Song) -> Bool {
        queueManager.isInQueue(song)
    }
    
    // MARK: - Album/Playlist Playback
    
    func playAlbum(songs: [Song], startIndex: Int = 0, shuffle: Bool = false) async {
        queueManager.setAlbumQueue(songs: songs, startIndex: startIndex)
        
        if shuffle {
            let randomIndex = shuffleController.enableShuffleForAlbum(queueSize: songs.count)
            queueManager.jumpToIndex(randomIndex)
        } else {
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
    }
    
    /// Resume playback of the restored session (called when user taps play on mini player)
    func resumeRestoredSession() async {
        guard let song = currentSong else { return }
        
        // Get the saved position before loading
        let savedPosition = LastPlayedSongManager.shared.loadSharedData()?.currentTime ?? 0
        
        // If we have a restored song but no audio loaded, load it with seek position
        if !playbackService.isAudioLoaded {
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
            // Load audio with seek position
            playbackService.load(
                url: url,
                expectedDuration: apiDuration,
                autoPlay: true,
                seekTo: seekTo,
                headers: YouTubeAPIContext.playbackHeaders
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
        guard let song = currentSong else { return }
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
