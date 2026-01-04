//
//  RecommendationsManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import Foundation
import SwiftData

/// Cached recommendation item for persistence
struct CachedRecommendation: Codable {
    let id: String
    let name: String
    let thumbnailUrl: String
    let artist: String
    let artistId: String?  // Added for artist navigation
    
    init(from searchResult: SearchResult) {
        self.id = searchResult.id
        self.name = searchResult.name
        self.thumbnailUrl = searchResult.thumbnailUrl
        self.artist = searchResult.artist
        self.artistId = searchResult.artistId
    }
    
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: id,
            name: name,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: "",
            artist: artist,
            type: .song,
            artistId: artistId
        )
    }
}

/// Manages personalized song recommendations based on user's listening history
@MainActor
@Observable
class RecommendationsManager {
    static let shared = RecommendationsManager()
    
    // Current recommendations to display
    private(set) var recommendations: [SearchResult] = []
    private var isLoading = false
    
    // UserDefaults keys
    private let cacheKey = "cachedRecommendations"
    
    private let networkManager = NetworkManager.shared
    private let playCountManager = PlayCountManager.shared
    
    private init() {
        // Load cached recommendations on init
        loadCachedRecommendations()
    }
    
    // MARK: - Public Methods
    
    /// Load cached recommendations (instant, for app startup)
    func loadCachedRecommendations() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedRecommendation].self, from: data) else {
            recommendations = []
            return
        }
        recommendations = cached.map { $0.toSearchResult() }
    }
    
    /// Fetch fresh recommendations immediately and update UI (for pull-to-refresh)
    func refreshRecommendations(in context: ModelContext) async -> [SearchResult] {
        let newRecommendations = await fetchFromAPI(in: context)
        if !newRecommendations.isEmpty {
            recommendations = newRecommendations
            saveToCache(newRecommendations)
        }
        return recommendations
    }
    
    /// Fetch recommendations in background without updating current UI
    /// Saves to cache for next app launch
    func prefetchRecommendationsInBackground(in context: ModelContext) async {
        guard !isLoading else { return }
        
        let newRecommendations = await fetchFromAPI(in: context)
        if !newRecommendations.isEmpty {
            saveToCache(newRecommendations)
        }
    }
    
    /// Clear cached recommendations
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    
    /// Check if recommendations are available
    var hasRecommendations: Bool {
        !recommendations.isEmpty
    }
    
    // MARK: - Private Methods
    
    private func saveToCache(_ results: [SearchResult]) {
        let cached = results.map { CachedRecommendation(from: $0) }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    private func fetchFromAPI(in context: ModelContext) async -> [SearchResult] {
        guard !isLoading else { return [] }
        isLoading = true
        defer { isLoading = false }
        
        // Get top 5 most played songs
        let topSongs = playCountManager.getTopPlayedSongs(limit: 5, in: context)
        
        guard !topSongs.isEmpty else { return [] }
        
        // Take first 3 songs for recommendations
        let seedSongs = Array(topSongs.prefix(3))
        
        var allRecommendations: [SearchResult] = []
        var seenIds = Set<String>()
        
        // Add seed songs to seen set
        for song in topSongs {
            seenIds.insert(song.videoId)
        }
        
        // Fetch recommendations for each seed song
        await withTaskGroup(of: [QueueSong].self) { group in
            for song in seedSongs {
                group.addTask { [weak self] in
                    guard let self = self else { return [] }
                    do {
                        return try await self.networkManager.getRelatedSongs(videoId: song.videoId)
                    } catch {
                        return []
                    }
                }
            }
            
            for await relatedSongs in group {
                for queueSong in relatedSongs {
                    guard !seenIds.contains(queueSong.id) else { continue }
                    seenIds.insert(queueSong.id)
                    
                    let searchResult = SearchResult(
                        id: queueSong.id,
                        name: queueSong.name,
                        thumbnailUrl: queueSong.thumbnailUrl,
                        isExplicit: false,
                        year: "",
                        artist: queueSong.artist,
                        type: .song,
                        artistId: queueSong.artistId
                    )
                    allRecommendations.append(searchResult)
                }
            }
        }
        
        // Shuffle and take first 28
        allRecommendations.shuffle()
        return Array(allRecommendations.prefix(28))
    }
}
