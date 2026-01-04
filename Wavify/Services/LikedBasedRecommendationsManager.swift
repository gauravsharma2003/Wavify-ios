//
//  LikedBasedRecommendationsManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 04/01/26.
//

import Foundation
import SwiftData

/// Cached recommendation item for persistence
struct CachedLikedBasedRecommendation: Codable {
    let id: String
    let name: String
    let thumbnailUrl: String
    let artist: String
    
    init(from searchResult: SearchResult) {
        self.id = searchResult.id
        self.name = searchResult.name
        self.thumbnailUrl = searchResult.thumbnailUrl
        self.artist = searchResult.artist
    }
    
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: id,
            name: name,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: "",
            artist: artist,
            type: .song
        )
    }
}

/// Manages song recommendations based on user's liked songs
@MainActor
@Observable
class LikedBasedRecommendationsManager {
    static let shared = LikedBasedRecommendationsManager()
    
    // Current recommendations to display
    private(set) var recommendations: [SearchResult] = []
    private var isLoading = false
    
    // UserDefaults key
    private let cacheKey = "cachedLikedBasedRecommendations"
    
    private let networkManager = NetworkManager.shared
    
    private init() {
        // Load cached recommendations on init
        loadCachedRecommendations()
    }
    
    // MARK: - Public Methods
    
    /// Load cached recommendations (instant, for app startup)
    func loadCachedRecommendations() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedLikedBasedRecommendation].self, from: data) else {
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
    
    /// Get the 5 most recently liked songs
    private func getLatestLikedSongs(limit: Int = 5, in context: ModelContext) -> [LocalSong] {
        var descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.isLiked == true },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch liked songs: \(error)")
            return []
        }
    }
    
    private func saveToCache(_ results: [SearchResult]) {
        let cached = results.map { CachedLikedBasedRecommendation(from: $0) }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    private func fetchFromAPI(in context: ModelContext) async -> [SearchResult] {
        guard !isLoading else { return [] }
        isLoading = true
        defer { isLoading = false }
        
        // Get latest 5 liked songs
        let likedSongs = getLatestLikedSongs(limit: 5, in: context)
        
        guard !likedSongs.isEmpty else { return [] }
        
        // Take first 3 songs for recommendations to limit API calls
        let seedSongs = Array(likedSongs.prefix(3))
        
        var allRecommendations: [SearchResult] = []
        var seenIds = Set<String>()
        
        // Add seed songs to seen set to avoid recommending liked songs
        for song in likedSongs {
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
                        type: .song
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
