//
//  HomeViewModel.swift
//  Wavify
//
//  ViewModel for HomeView - handles data loading and state management
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
class HomeViewModel {
    var homePage: HomePage?
    var selectedChipId: String?
    var isLoading = false
    var recommendedSongs: [SearchResult] = []
    var keepListeningSongs: [SearchResult] = []
    // Computed property that always returns the latest favourites from FavouritesManager
    var favouriteItems: [SearchResult] { FavouritesManager.shared.favourites }
    var likedBasedRecommendations: [SearchResult] = []
    
    // Chart sections (computed from ChartsManager cache)
    var trendingSongs: [SearchResult] { chartsManager.trendingSongs }
    var topSongs: [SearchResult] { chartsManager.topSongs }
    var global100Songs: [SearchResult] { chartsManager.global100Songs }
    var us100Songs: [SearchResult] { chartsManager.us100Songs }
    var languageCharts: [LanguageChart] { chartsManager.languageCharts }
    var hasHistory: Bool = false
    
    // Shorts section (computed from ShortsManager cache)
    var shortsSongs: [SearchResult] { shortsManager.shortsSongs }

    // Track if initial load has completed (prevents loader on tab switch)
    private var hasLoadedInitially = false

    // Random category section (computed from RandomCategoryManager cache)
    var randomCategoryName: String { randomCategoryManager.currentCategoryName }
    var randomCategoryPlaylists: [CategoryPlaylist] { randomCategoryManager.categoryPlaylists }
    
    private let networkManager = NetworkManager.shared
    private let recommendationsManager = RecommendationsManager.shared
    private let keepListeningManager = KeepListeningManager.shared
    private let favouritesManager = FavouritesManager.shared
    private let chartsManager = ChartsManager.shared
    private let likedBasedRecommendationsManager = LikedBasedRecommendationsManager.shared
    private let randomCategoryManager = RandomCategoryManager.shared
    private let shortsManager = ShortsManager.shared
    
    func loadInitialContent(modelContext: ModelContext) async {
        // Skip if already loaded (prevents loader when switching tabs)
        guard !hasLoadedInitially else { return }

        // 1. Load cached data instantly
        loadCachedRecommendations()
        loadCachedKeepListening()
        loadCachedFavourites()
        loadCachedLikedBasedRecommendations()

        hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)

        // Only show loader if we have no content to display
        let hasCachedContent = chartsManager.hasCachedData || homePage != nil
        if !hasCachedContent {
            isLoading = true
        }

        // 2. Load charts and random category data in parallel
        let needsChartsRefresh = !chartsManager.hasCachedData

        await withTaskGroup(of: Void.self) { group in
            if needsChartsRefresh {
                group.addTask { @MainActor in
                    await self.chartsManager.refreshInBackground()
                }
            }

            group.addTask { @MainActor in
                await self.randomCategoryManager.refreshInBackground()
            }
            
            group.addTask { @MainActor in
                await self.shortsManager.refreshInBackground()
            }
        }

        await loadHome()

        isLoading = false
        hasLoadedInitially = true

        // Refresh Keep Listening and Favourites in background
        Task { [weak self] in
            guard let self = self else { return }

            if hasHistory {
                self.keepListeningSongs = self.keepListeningManager.refreshSongs(in: modelContext)

                // Yield between operations to keep UI responsive
                await Task.yield()

                // Refresh favourites in FavouritesManager (computed property will pick it up)
                _ = self.favouritesManager.refreshFavourites(in: modelContext)

                await Task.yield()

                await self.recommendationsManager.prefetchRecommendationsInBackground(in: modelContext)

                await Task.yield()

                await self.likedBasedRecommendationsManager.prefetchRecommendationsInBackground(in: modelContext)
            }

            // Background refresh charts if needed (won't block UI)
            if chartsManager.needsRefresh {
                await chartsManager.refreshInBackground()
            }
            
            // Background refresh shorts if needed
            if shortsManager.needsRefresh {
                await shortsManager.refreshInBackground()
            }
        }
    }
    
    func refresh(modelContext: ModelContext) async {
        // Local operations first (instant)
        let hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)
        if hasHistory {
            keepListeningSongs = keepListeningManager.refreshSongs(in: modelContext)
            _ = favouritesManager.refreshFavourites(in: modelContext)
        }

        // All network operations in PARALLEL for faster refresh
        await withTaskGroup(of: Void.self) { group in
            // 1. Load home page or selected chip
            group.addTask { @MainActor in
                if let selectedChipId = self.selectedChipId,
                   let chip = self.homePage?.chips.first(where: { $0.id == selectedChipId }) {
                    await self.selectChip(chip)
                } else {
                    await self.loadHome()
                }
            }

            // 2. Refresh recommendations (if user has history)
            if hasHistory {
                group.addTask { @MainActor in
                    self.recommendedSongs = await self.recommendationsManager.refreshRecommendations(in: modelContext)
                }
                group.addTask { @MainActor in
                    self.likedBasedRecommendations = await self.likedBasedRecommendationsManager.refreshRecommendations(in: modelContext)
                }
            }

            // 3. Force refresh charts
            group.addTask { @MainActor in
                await self.chartsManager.forceRefresh()
            }

            // 4. Force refresh random category
            group.addTask { @MainActor in
                await self.randomCategoryManager.forceRefresh()
            }
            
            // 5. Force refresh shorts
            group.addTask { @MainActor in
                await self.shortsManager.forceRefresh()
            }
        }
    }
    
    func loadCachedRecommendations() {
        recommendedSongs = recommendationsManager.recommendations
    }
    
    func loadCachedKeepListening() {
        keepListeningSongs = keepListeningManager.songs
    }
    
    func loadCachedFavourites() {
        // No-op: favouriteItems is now a computed property from FavouritesManager
        // FavouritesManager loads cached data on init
    }
    
    func loadCachedLikedBasedRecommendations() {
        likedBasedRecommendations = likedBasedRecommendationsManager.recommendations
    }
    
    func loadHome() async {
        // Only set loading if we aren't showing chart content already
        if trendingSongs.isEmpty {
             isLoading = true
        }
        
        do {
            let home = try await ErrorHandler.withRetry {
                try await self.networkManager.getHome()
            }
            self.homePage = home
            self.selectedChipId = nil
            isLoading = false
        } catch {
            Logger.error("Failed to load home", category: .network, error: error)
            isLoading = false
        }
    }
    
    func selectChip(_ chip: Chip) async {
        if selectedChipId == chip.id {
            await loadHome()
            return
        }

        isLoading = true
        selectedChipId = chip.id

        do {
            self.homePage = try await ErrorHandler.withRetry {
                try await self.networkManager.loadPage(endpoint: chip.endpoint)
            }
        } catch {
            Logger.error("Failed to load chip", category: .network, error: error)
        }
        isLoading = false
    }

    /// Called when a song starts playing - loads recommendations if this creates history for the first time
    func onSongPlayed(song: Song, modelContext: ModelContext) async {
        // Check if history was just created (user didn't have history before)
        let hadHistoryBefore = hasHistory
        hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)

        // If this is the first song played (history just created), load recommendations immediately
        if !hadHistoryBefore && hasHistory {
            // Fetch recommendations based on the song just played
            recommendedSongs = await recommendationsManager.refreshRecommendations(in: modelContext)
        }
    }
}
