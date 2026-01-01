//
//  KeepListeningManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation
import SwiftData

/// Cached song item for Keep Listening persistence
struct CachedKeepListeningSong: Codable {
    let id: String
    let name: String
    let thumbnailUrl: String
    let artist: String
    let duration: String
    
    init(from song: SongPlayCount) {
        self.id = song.videoId
        self.name = song.title
        self.thumbnailUrl = song.thumbnailUrl
        self.artist = song.artist
        self.duration = song.duration
    }
    
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: id,
            name: name,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: duration,  // Use year field for duration display
            artist: artist,
            type: .song
        )
    }
}

/// Manages "Keep Listening" section showing most played songs
@MainActor
@Observable
class KeepListeningManager {
    static let shared = KeepListeningManager()
    
    // Current songs to display
    private(set) var songs: [SearchResult] = []
    private var isLoading = false
    
    // UserDefaults key
    private let cacheKey = "cachedKeepListeningSongs"
    
    // Minimum songs required to show section
    private let minSongsRequired = 4
    // Maximum songs to display
    private let maxSongs = 16
    
    private let playCountManager = PlayCountManager.shared
    
    private init() {
        // Load cached songs on init
        loadCachedSongs()
    }
    
    // MARK: - Public Methods
    
    /// Load cached songs (instant, for app startup)
    func loadCachedSongs() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedKeepListeningSong].self, from: data) else {
            songs = []
            return
        }
        songs = cached.map { $0.toSearchResult() }
    }
    
    /// Refresh songs from database and update UI (for app launch and pull-to-refresh)
    func refreshSongs(in context: ModelContext) -> [SearchResult] {
        guard !isLoading else { return songs }
        isLoading = true
        defer { isLoading = false }
        
        // Get top 16 most played songs
        let topSongs = playCountManager.getTopPlayedSongs(limit: maxSongs, in: context)
        
        // Only show if we have at least 4 songs
        guard topSongs.count >= minSongsRequired else {
            songs = []
            saveToCache([])
            return []
        }
        
        // Convert to SearchResult
        let results = topSongs.map { song in
            SearchResult(
                id: song.videoId,
                name: song.title,
                thumbnailUrl: song.thumbnailUrl,
                isExplicit: false,
                year: song.duration,  // Use year field for duration
                artist: song.artist,
                type: .song
            )
        }
        
        songs = results
        saveToCache(topSongs)
        return results
    }
    
    /// Check if we have enough songs to show the section
    var shouldShowSection: Bool {
        songs.count >= minSongsRequired
    }
    
    // MARK: - Private Methods
    
    private func saveToCache(_ playCounts: [SongPlayCount]) {
        let cached = playCounts.map { CachedKeepListeningSong(from: $0) }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
