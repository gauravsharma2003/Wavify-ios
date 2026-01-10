//
//  QueueManager.swift
//  Wavify
//
//  Manages playback queue logic including user queue, related songs, and queue manipulation
//

import Foundation

/// Manages the playback queue separate from playback controls
@MainActor
@Observable
class QueueManager {
    // MARK: - Queue State
    
    /// Main playback queue
    var queue: [Song] = []
    
    /// Current position in the queue
    var currentIndex: Int = 0
    
    /// User-managed queue for Play Next and Add to Queue features
    var userQueue: [Song] = []
    
    /// Whether currently playing from an album/playlist (don't auto-refresh queue)
    var isPlayingFromAlbum = false
    
    // MARK: - Dependencies
    
    private let networkManager = NetworkManager.shared
    
    // MARK: - Computed Properties
    
    /// Cached set of user queue IDs for efficient lookup in views
    var userQueueIds: Set<String> {
        Set(userQueue.map { $0.id })
    }
    
    /// Current song in queue
    var currentSong: Song? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    /// Number of songs remaining after current
    var songsRemaining: Int {
        queue.count - currentIndex - 1
    }
    
    // MARK: - Queue Initialization
    
    /// Set up a new queue with a starting song
    func setQueue(startingSong: Song, relatedSongs: [Song]) {
        // Filter out current song and userQueue songs from related
        let excludeIds = Set([startingSong.id] + userQueue.map { $0.id })
        let filteredSongs = relatedSongs.filter { !excludeIds.contains($0.id) }
        queue = [startingSong] + userQueue + filteredSongs
        currentIndex = 0
    }
    
    /// Set up queue for album/playlist playback
    func setAlbumQueue(songs: [Song], startIndex: Int = 0) {
        queue = songs
        currentIndex = startIndex
        isPlayingFromAlbum = true
    }
    
    /// Append songs to the queue (avoiding duplicates)
    func appendToQueue(_ songs: [Song]) {
        let existingIds = Set(queue.map { $0.id })
        let uniqueNewSongs = songs.filter { !existingIds.contains($0.id) }
        queue.append(contentsOf: uniqueNewSongs)
    }
    
    // MARK: - User Queue Management
    
    /// Add song to play immediately after current song
    func playNext(_ song: Song) {
        // Remove if already in userQueue to avoid duplicates
        userQueue.removeAll { $0.id == song.id }
        userQueue.insert(song, at: 0)
        rebuildQueueWithUserSongs()
    }
    
    /// Add song to end of user queue
    /// Returns true if added, false if already in queue
    func addToQueue(_ song: Song) -> Bool {
        if isInQueue(song) {
            return false
        }
        userQueue.append(song)
        rebuildQueueWithUserSongs()
        return true
    }
    
    /// Check if song is already in user queue or upcoming in main queue
    func isInQueue(_ song: Song) -> Bool {
        return userQueue.contains { $0.id == song.id } ||
               queue.dropFirst(currentIndex + 1).contains { $0.id == song.id }
    }
    
    /// Remove a song from the upcoming queue when it's played
    func consumeFromUserQueue(songId: String) {
        userQueue.removeAll { $0.id == songId }
    }
    
    // MARK: - Queue Navigation
    
    /// Move to next index in queue
    /// Returns the new index, or nil if at end
    func moveToNext() -> Int? {
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            // Remove from userQueue if this song was user-added
            if let song = queue[safe: nextIndex] {
                consumeFromUserQueue(songId: song.id)
            }
            return nextIndex
        }
        return nil
    }
    
    /// Move to previous index in queue
    /// Returns the new index, or nil if at start
    func moveToPrevious() -> Int? {
        if currentIndex > 0 {
            currentIndex -= 1
            return currentIndex
        }
        return nil
    }
    
    /// Jump to specific index in queue
    func jumpToIndex(_ index: Int) -> Bool {
        guard index >= 0 && index < queue.count else { return false }
        currentIndex = index
        return true
    }
    
    /// Loop back to start of queue
    func loopToStart() {
        currentIndex = 0
    }
    
    // MARK: - Related Songs
    
    /// Load related songs from API and add to queue
    func loadRelatedSongs(videoId: String, replaceQueue: Bool, currentSong: Song?) async {
        do {
            let relatedSongs = try await networkManager.getRelatedSongs(videoId: videoId)
            let newSongs = relatedSongs.map { song -> Song in
                var s = Song(from: song)
                s.isRecommendation = true
                return s
            }
            
            if replaceQueue {
                if let currentSong = currentSong {
                    let excludeIds = Set([currentSong.id] + userQueue.map { $0.id })
                    let filteredNewSongs = newSongs.filter { !excludeIds.contains($0.id) }
                    queue = [currentSong] + userQueue + filteredNewSongs
                    currentIndex = 0
                } else {
                    queue = userQueue + newSongs
                    currentIndex = 0
                }
            } else {
                appendToQueue(newSongs)
            }
        } catch {
            Logger.error("Failed to load related songs", category: .playback, error: error)
        }
    }
    
    /// Check if we need to fetch more songs and do so if needed
    func checkAndAppendIfNeeded(loopMode: LoopMode, currentSong: Song?) {
        // Don't fetch recommendations if loop mode is active
        guard loopMode == .none else { return }
        
        // If less than 10 songs remaining, fetch more
        if songsRemaining < 10, let currentSong = currentSong {
            Task {
                await loadRelatedSongs(videoId: currentSong.videoId, replaceQueue: false, currentSong: currentSong)
            }
        }
    }
    
    // MARK: - Queue Cleanup
    
    /// Remove all recommendation songs from queue (for Loop All mode)
    func removeRecommendations(keepingSongId: String?) {
        queue = queue.filter { !$0.isRecommendation }
        
        // Reset index to match the filtered queue
        if let songId = keepingSongId,
           let newIndex = queue.firstIndex(where: { $0.id == songId }) {
            currentIndex = newIndex
        }
    }
    
    /// Clear the entire queue
    func clear() {
        queue = []
        userQueue = []
        currentIndex = 0
        isPlayingFromAlbum = false
    }
    
    // MARK: - Private Helpers
    
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
}
