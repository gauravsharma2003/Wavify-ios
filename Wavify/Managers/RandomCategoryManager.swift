//
//  RandomCategoryManager.swift
//  Wavify
//
//  Manages caching of random category playlists for the homepage carousel
//  Uses chips from the Home API (Search tab's Browse section)
//

import Foundation

/// Manages caching of random category playlists to show varied content on each launch
@MainActor
class RandomCategoryManager {
    static let shared = RandomCategoryManager()
    
    // Cached data
    private(set) var currentCategoryName: String = ""
    private(set) var categoryPlaylists: [CategoryPlaylist] = []
    
    // Track if we've loaded data at least once this session
    private(set) var hasLoaded = false
    
    // Last refresh timestamp (session-only, resets on app launch)
    private var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 60 * 60 // 1 hour - keep same category during session
    
    private let networkManager = NetworkManager.shared
    
    private init() {}
    
    /// Check if cached data exists
    var hasCachedData: Bool {
        return !categoryPlaylists.isEmpty
    }
    
    /// Check if data needs refresh (no data loaded, or older than refresh interval)
    var needsRefresh: Bool {
        // Always need refresh if no data loaded
        if !hasLoaded { return true }
        guard let lastRefresh = lastRefreshTime else { return true }
        return Date().timeIntervalSince(lastRefresh) > refreshInterval
    }
    
    /// Fetch random category playlists from network (updates cache silently)
    func refreshInBackground() async {
        // Always fetch if no data, otherwise respect needsRefresh
        guard !hasLoaded || needsRefresh else { return }
        
        do {
            // 1. Get chips from Home API
            let home = try await networkManager.getHome()
            
            // Filter out podcasts
            let validChips = home.chips.filter { $0.title.lowercased() != "podcasts" }
            
            guard !validChips.isEmpty else {
                Logger.warning("No valid chips found", category: .network)
                return
            }
            
            // 2. Pick a random chip
            let randomIndex = Int.random(in: 0..<validChips.count)
            let selectedChip = validChips[randomIndex]
            
            // 3. Load that chip's page to get playlists
            let categoryPage = try await networkManager.loadPage(endpoint: selectedChip.endpoint)
            
            // 4. Extract playlists from the sections (skip Quick Picks which are usually songs)
            var playlists: [CategoryPlaylist] = []
            
            for section in categoryPage.sections {
                // Skip "Quick picks" sections - they contain songs, not playlists
                let titleLower = section.title.lowercased()
                if titleLower.contains("quick pick") {
                    continue
                }
                
                // Extract playlists from this section
                for item in section.items {
                    if item.type == .playlist || item.type == .album {
                        let isAlbum = item.type == .album
                        playlists.append(CategoryPlaylist(
                            id: item.id,
                            name: item.name,
                            thumbnailUrl: item.thumbnailUrl,
                            playlistId: item.id,
                            subtitle: item.artist.isEmpty ? nil : item.artist,
                            isAlbum: isAlbum
                        ))
                    }
                }
                
                // Stop after getting enough playlists from the first non-QuickPicks section
                if !playlists.isEmpty {
                    break
                }
            }
            
            // Update cache with new data
            if !playlists.isEmpty {
                self.currentCategoryName = selectedChip.title
                self.categoryPlaylists = playlists
                self.hasLoaded = true
                self.lastRefreshTime = Date()
            }
        } catch {
            Logger.error("Random category fetch failed", category: .network, error: error)
        }
    }
    
    /// Force refresh (for pull-to-refresh) - always gets a new random category
    func forceRefresh() async {
        // Reset state to force a new fetch
        lastRefreshTime = nil
        hasLoaded = false
        
        await refreshInBackground()
    }
}
