//
//  AudioPlayer.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import Observation

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
    
    // MARK: - Observable Properties
    
    var isPlaying = false
    var currentSong: Song?
    var currentTime: Double = 0
    var duration: Double = 0
    var isLoading = false
    var queue: [Song] = []
    var currentIndex: Int = 0
    var loopMode: LoopMode = .none
    var isPlayingFromAlbum = false  // When true, don't auto-refresh queue
    
    // User-managed queue for Play Next and Add to Queue features
    var userQueue: [Song] = []  // Songs manually added by user
    
    // MARK: - Private Properties
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    
    private let networkManager = NetworkManager.shared
    
    private init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
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
            Task { @MainActor in
                await self?.playNext()
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
    }
    
    // MARK: - Playback Control
    
    /// Play a new song from search/browse - creates fresh queue
    func loadAndPlay(song: Song) async {
        // Add to queue at current position and start playing
        await playNewSong(song, refreshQueue: true)
    }
    
    /// Internal method to play a song with optional queue refresh
    private func playNewSong(_ song: Song, refreshQueue: Bool) async {
        isLoading = true
        currentSong = song
        
        // Notify for play count tracking - this captures ALL song plays
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
            
            // Use YouTube API's duration (lengthSeconds) - more reliable than AVPlayer's duration
            let apiDuration = Double(playbackInfo.duration) ?? 0
            
            // Update artistId if available in playbackInfo (critical for navigation)
            if var song = currentSong {
                if song.artistId == nil || (song.albumId == nil && playbackInfo.albumId != nil) {
                    // Create a copy with updated IDs
                    let updatedSong = Song(
                        id: song.id,
                        title: song.title,
                        artist: song.artist,
                        thumbnailUrl: song.thumbnailUrl,
                        duration: song.duration,
                        isLiked: song.isLiked,
                        artistId: playbackInfo.artistId ?? song.artistId,
                        albumId: playbackInfo.albumId ?? song.albumId
                    )
                    self.currentSong = updatedSong
                }
            }
            
            // Clean up previous player
            cleanupPlayer()
            
            // Create new player
            playerItem = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: playerItem)
            
            // Set duration from API before player reports (more accurate)
            self.duration = apiDuration
            
            // Observe player status
            statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    switch item.status {
                    case .readyToPlay:
                        // Keep API duration, don't override with AVPlayer's potentially incorrect duration
                        self?.isLoading = false
                        self?.player?.play()
                        self?.isPlaying = true
                        self?.updateNowPlayingInfo()
                    case .failed:
                        self?.isLoading = false
                        print("Player failed: \(String(describing: item.error))")
                    default:
                        break
                    }
                }
            }
            
            // Setup time observer
            setupTimeObserver()
            
            // Only refresh queue for new songs, not when playing from existing queue
            if refreshQueue {
                await loadRelatedSongs(videoId: song.videoId, replaceQueue: true)
            } else {
                // Check if we're near the end of queue (last 10 songs) - append more songs
                checkAndAppendToQueue()
            }
            
        } catch {
            isLoading = false
            print("Failed to load playback info: \(error)")
        }
    }
    
    private func loadRelatedSongs(videoId: String, replaceQueue: Bool) async {
        do {
            let relatedSongs = try await networkManager.getRelatedSongs(videoId: videoId)
            let newSongs = relatedSongs.map { song -> Song in
                var s = Song(from: song)
                s.isRecommendation = true
                return s
            }
            
            if replaceQueue {
                // When replacing queue, preserve userQueue songs at the beginning
                // Structure: [currentSong, ...userQueue, ...recommendations]
                if let currentSong = currentSong {
                    // Filter out current song and userQueue songs from recommendations
                    let excludeIds = Set([currentSong.id] + userQueue.map { $0.id })
                    let filteredNewSongs = newSongs.filter { !excludeIds.contains($0.id) }
                    queue = [currentSong] + userQueue + filteredNewSongs
                    currentIndex = 0
                } else {
                    queue = userQueue + newSongs
                    currentIndex = 0
                }
            } else {
                // Append new songs, avoiding duplicates
                let existingIds = Set(queue.map { $0.id })
                let uniqueNewSongs = newSongs.filter { !existingIds.contains($0.id) }
                queue.append(contentsOf: uniqueNewSongs)
            }
        } catch {
            print("Failed to load related songs: \(error)")
        }
    }
    
    /// Check if near end of queue and append more songs if needed
    private func checkAndAppendToQueue() {
        // Don't fetch recommendations if loop mode is active (Loop One or Loop All)
        guard loopMode == .none else { return }
        
        let songsRemaining = queue.count - currentIndex - 1
        
        // If less than 10 songs remaining, fetch more
        if songsRemaining < 10, let currentSong = currentSong {
            Task {
                await loadRelatedSongs(videoId: currentSong.videoId, replaceQueue: false)
            }
        }
    }
    
    func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingInfo()
    }
    
    func playNext() async {
        guard !queue.isEmpty else { return }
        
        // Handle loop modes
        switch loopMode {
        case .one:
            // Loop current song - just restart
            seek(to: 0)
            player?.play()
            isPlaying = true
            return
            
        case .all:
            // Loop through queue
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                currentIndex = nextIndex
                // Remove from userQueue if this song was user-added
                if let song = queue[safe: nextIndex] {
                    userQueue.removeAll { $0.id == song.id }
                }
                await playNewSong(queue[nextIndex], refreshQueue: false)
            } else {
                // Reached end, loop back to start
                currentIndex = 0
                await playNewSong(queue[0], refreshQueue: false)
            }
            
        case .none:
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                currentIndex = nextIndex
                // Remove from userQueue if this song was user-added
                if let song = queue[safe: nextIndex] {
                    userQueue.removeAll { $0.id == song.id }
                }
                await playNewSong(queue[nextIndex], refreshQueue: false)
            } else if !isPlayingFromAlbum {
                // Not playing from album and reached end - try to get more songs
                checkAndAppendToQueue()
            }
            // If playing from album and reached end, just stop
        }
    }
    
    func playPrevious() async {
        if currentTime > 3 {
            // If more than 3 seconds in, restart current song
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            await playNewSong(queue[currentIndex], refreshQueue: false)
        } else if loopMode == .all && !queue.isEmpty {
            // Loop to end
            currentIndex = queue.count - 1
            await playNewSong(queue[currentIndex], refreshQueue: false)
        } else {
            seek(to: 0)
        }
    }
    
    func playFromQueue(at index: Int) async {
        guard index >= 0 && index < queue.count else { return }
        currentIndex = index
        await playNewSong(queue[index], refreshQueue: false)
    }
    
    func toggleLoopMode() {
        loopMode = loopMode.next()
        
        // Handle logic when entering Loop All
        if loopMode == .all {
            if let current = currentSong {
                if !current.isRecommendation {
                    // We are in the core content (Album, Playlist, or User Selection).
                    // Remove all auto-generated recommendations to strictly loop the core content.
                    // User-added songs (addToQueue) are NOT marked isRecommendation, so they are preserved.
                    queue = queue.filter { !$0.isRecommendation }
                    
                    // Reset index to match the filtered queue
                    if let newIndex = queue.firstIndex(where: { $0.id == current.id }) {
                        currentIndex = newIndex
                    }
                } else {
                    // We are currently playing a recommendation.
                    // Keep the current queue (history + recommendations so far).
                    // checkAndAppendToQueue will guard against adding MORE, effectively creating a closed loop of what we have.
                }
            }

        } else if loopMode == .none {
            // Resume recommendation fetching if needed
            checkAndAppendToQueue()
        }
    }
    
    // MARK: - User Queue Management
    
    /// Add song to play immediately after current song
    func playNextSong(_ song: Song) {
        // Remove if already in userQueue to avoid duplicates, then insert at front
        userQueue.removeAll { $0.id == song.id }
        userQueue.insert(song, at: 0)
        
        // Update the main queue to reflect userQueue changes
        rebuildQueueWithUserSongs()
    }
    
    /// Add song to end of queue
    /// Returns true if added, false if already in queue
    func addToQueue(_ song: Song) -> Bool {
        if isInQueue(song) {
            return false
        }
        userQueue.append(song)
        
        // Update the main queue to reflect userQueue changes
        rebuildQueueWithUserSongs()
        return true
    }
    
    /// Check if song is already in user queue or main queue
    func isInQueue(_ song: Song) -> Bool {
        return userQueue.contains { $0.id == song.id } ||
               queue.dropFirst(currentIndex + 1).contains { $0.id == song.id }
    }
    
    /// Rebuild queue with user songs after current playing song
    private func rebuildQueueWithUserSongs() {
        guard currentIndex < queue.count else { return }
        
        // Get current song and songs before it
        let songsUpToCurrent = Array(queue.prefix(currentIndex + 1))
        
        // Get remaining recommendation songs (excluding userQueue songs)
        let userQueueIds = Set(userQueue.map { $0.id })
        let remainingRecommendations = queue.dropFirst(currentIndex + 1).filter { !userQueueIds.contains($0.id) }
        
        // Rebuild: [songs up to current] + [userQueue] + [remaining recommendations]
        queue = songsUpToCurrent + userQueue + Array(remainingRecommendations)
    }
    
    /// Play album/playlist without refreshing queue
    func playAlbum(songs: [Song], startIndex: Int = 0, shuffle: Bool = false) async {
        var songsToPlay = songs
        if shuffle {
            songsToPlay.shuffle()
        }
        
        queue = songsToPlay
        currentIndex = startIndex
        isPlayingFromAlbum = true
        
        if let song = songsToPlay[safe: startIndex] {
            await playNewSong(song, refreshQueue: false)
        }
    }
    
    // MARK: - Time Observer
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let seconds = time.seconds.isNaN ? 0 : time.seconds
                self.currentTime = min(seconds, self.duration) // Cap at duration
                
                // Check if song should end (currentTime reached or exceeded API duration)
                if self.duration > 0 && seconds >= self.duration - 0.5 {
                    // Song has ended based on API duration
                    await self.handleSongEnd()
                }
            }
        }
    }
    
    private func handleSongEnd() async {
        await playNext()
    }
    
    // MARK: - Now Playing Info
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration
        ]
        
        // Load artwork asynchronously
        if let url = URL(string: song.thumbnailUrl) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                } catch {
                    print("Failed to load artwork: \(error)")
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Cleanup
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player = nil
        playerItem = nil
    }
    
    deinit {
        Task { @MainActor in
            cleanupPlayer()
        }
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

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
