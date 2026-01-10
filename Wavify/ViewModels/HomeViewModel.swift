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
    var favouriteItems: [SearchResult] = []
    var likedBasedRecommendations: [SearchResult] = []
    
    // Chart sections (computed from ChartsManager cache)
    var trendingSongs: [SearchResult] { chartsManager.trendingSongs }
    var topSongs: [SearchResult] { chartsManager.topSongs }
    var global100Songs: [SearchResult] { chartsManager.global100Songs }
    var us100Songs: [SearchResult] { chartsManager.us100Songs }
    var languageCharts: [LanguageChart] { chartsManager.languageCharts }
    var hasHistory: Bool = false
    
    private let networkManager = NetworkManager.shared
    private let recommendationsManager = RecommendationsManager.shared
    private let keepListeningManager = KeepListeningManager.shared
    private let favouritesManager = FavouritesManager.shared
    private let chartsManager = ChartsManager.shared
    private let likedBasedRecommendationsManager = LikedBasedRecommendationsManager.shared
    
    func loadInitialContent(modelContext: ModelContext) async {
        // Always show loading on fresh start
        isLoading = true
        
        // 1. Load cached data instantly
        loadCachedRecommendations()
        loadCachedKeepListening()
        loadCachedFavourites()
        loadCachedLikedBasedRecommendations()
        
        hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)
        
        // 2. Load charts and home data
        if !chartsManager.hasCachedData {
            await chartsManager.refreshInBackground()
        }
        
        await loadHome()
        
        // Let UI show loading state naturally - removed artificial delays
        isLoading = false
        
        // Refresh Keep Listening and Favourites in background
        Task { [weak self] in
            guard let self = self else { return }
            
            if hasHistory {
                self.keepListeningSongs = self.keepListeningManager.refreshSongs(in: modelContext)
                
                // Yield between operations to keep UI responsive
                await Task.yield()
                
                self.favouriteItems = self.favouritesManager.refreshFavourites(in: modelContext)
                
                await Task.yield()
                
                await self.recommendationsManager.prefetchRecommendationsInBackground(in: modelContext)
                
                await Task.yield()
                
                await self.likedBasedRecommendationsManager.prefetchRecommendationsInBackground(in: modelContext)
            }
            
            // Background refresh charts if needed (won't block UI)
            if chartsManager.needsRefresh {
                await chartsManager.refreshInBackground()
            }
        }
    }
    
    func refresh(modelContext: ModelContext) async {
        if let selectedChipId = selectedChipId,
           let chip = homePage?.chips.first(where: { $0.id == selectedChipId }) {
            await selectChip(chip)
        } else {
            await loadHome()
        }
        
        let hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)
        if hasHistory {
            keepListeningSongs = keepListeningManager.refreshSongs(in: modelContext)
            favouriteItems = favouritesManager.refreshFavourites(in: modelContext)
            recommendedSongs = await recommendationsManager.refreshRecommendations(in: modelContext)
            likedBasedRecommendations = await likedBasedRecommendationsManager.refreshRecommendations(in: modelContext)
        }
        
        // Force refresh charts on pull-to-refresh
        await chartsManager.forceRefresh()
    }
    
    func loadCachedRecommendations() {
        recommendedSongs = recommendationsManager.recommendations
    }
    
    func loadCachedKeepListening() {
        keepListeningSongs = keepListeningManager.songs
    }
    
    func loadCachedFavourites() {
        favouriteItems = favouritesManager.favourites
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
}
