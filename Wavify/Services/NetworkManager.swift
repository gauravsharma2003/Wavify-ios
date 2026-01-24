//
//  NetworkManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//
//  Facade for YouTube Music API - delegates to specialized services
//

import Foundation
import Observation

// MARK: - Network Manager (Facade)

@MainActor
@Observable
class NetworkManager {
    static let shared = NetworkManager()
    
    // MARK: - Services
    
    private let searchService = SearchAPIService.shared
    private let playerService = PlayerAPIService.shared
    private let browseService = BrowseAPIService.shared
    private let albumService = AlbumAPIService.shared
    private let artistService = ArtistAPIService.shared
    private let requestManager = APIRequestManager.shared
    
    private init() {}
    
    // MARK: - Search API
    
    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion] {
        try await searchService.getSearchSuggestions(query: query)
    }
    
    func search(query: String, params: String? = nil) async throws -> (topResults: [SearchResult], results: [SearchResult]) {
        try await searchService.search(query: query, params: params)
    }
    
    // MARK: - Player API
    
    func getPlaybackInfo(videoId: String) async throws -> PlaybackInfo {
        try await playerService.getPlaybackInfo(videoId: videoId)
    }
    
    func getRelatedSongs(videoId: String) async throws -> [QueueSong] {
        try await playerService.getRelatedSongs(videoId: videoId)
    }
    
    func getQueueSongs(playlistId: String) async throws -> [QueueSong] {
        try await playerService.getQueueSongs(playlistId: playlistId)
    }

    /// Invalidate cached playback info for a video (call on playback failure)
    func invalidatePlaybackCache(videoId: String) async {
        await requestManager.clearCacheEntry(forKey: "player_\(videoId)")
    }
    
    // MARK: - Browse API
    
    func getHome() async throws -> HomePage {
        try await browseService.getHome()
    }
    
    func getCharts(country: String? = nil) async throws -> HomePage {
        try await browseService.getCharts(country: country)
    }
    
    func getTrendingSongs(country: String) async throws -> [SearchResult] {
        try await browseService.getTrendingSongs(country: country)
    }
    
    func getPlaylist(id: String) async throws -> HomePage {
        try await browseService.getPlaylist(id: id)
    }
    
    func loadPage(endpoint: BrowseEndpoint) async throws -> HomePage {
        try await browseService.loadPage(endpoint: endpoint)
    }
    
    func getLanguageCharts() async throws -> [(name: String, playlistId: String, thumbnailUrl: String)] {
        try await browseService.getLanguageCharts()
    }
    
    func getRandomCategoryPlaylists() async throws -> (categoryName: String, playlists: [CategoryPlaylist]) {
        try await browseService.getRandomCategoryPlaylists()
    }
    
    // MARK: - Album API
    
    func getAlbumDetails(albumId: String) async throws -> AlbumDetail {
        try await albumService.getAlbumDetails(albumId: albumId)
    }
    
    // MARK: - Artist API
    
    func getArtistDetails(browseId: String) async throws -> ArtistDetail {
        try await artistService.getArtistDetails(browseId: browseId)
    }
    
    func getSectionItems(browseId: String, params: String? = nil) async throws -> [ArtistItem] {
        try await artistService.getSectionItems(browseId: browseId, params: params)
    }
    
    // MARK: - Location & Charts
    
    func getLocation() async throws -> UserLocation {
        guard let url = URL(string: "https://locate.indiatimes.com/service/locate") else {
            return .fallback
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, /", forHTTPHeaderField: "accept")
        request.setValue("no-cache", forHTTPHeaderField: "cache-control")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36", forHTTPHeaderField: "user-agent")
        
        do {
            let data = try await requestManager.execute(request)
            let location = try JSONDecoder().decode(UserLocation.self, from: data)
            return location
        } catch {
            Logger.networkError("Location fetch failed", error: error)
            return .fallback
        }
    }
    
    func getLocationSafe() async -> UserLocation {
        do {
            return try await getLocation()
        } catch {
            return .fallback
        }
    }
    
    func getChartsFlow(countryCode: String, countryName: String) async throws -> (country: [SearchResult], global: [SearchResult], countryName: String) {
        let explorePage = try await getCharts(country: countryCode)
        
        // For Country: Get first section with songs
        var countrySongs: [SearchResult] = []
        for section in explorePage.sections {
            let songs = section.items.filter { $0.type == .song }
            if !songs.isEmpty {
                countrySongs = songs
                break
            }
        }
        
        // For Global: Get a DIFFERENT section with songs
        var globalSongs: [SearchResult] = []
        var usedFirstSection = false
        for section in explorePage.sections {
            let songs = section.items.filter { $0.type == .song }
            if !songs.isEmpty {
                if !usedFirstSection {
                    usedFirstSection = true
                    continue
                }
                globalSongs = songs
                break
            }
        }
        
        // Fallbacks
        if globalSongs.isEmpty {
            for section in explorePage.sections {
                let title = section.title.lowercased()
                if (title.contains("chart") || title.contains("trend") || title.contains("top")) && !section.items.isEmpty {
                    globalSongs = section.items
                    break
                }
            }
        }
        
        if globalSongs.isEmpty && explorePage.sections.count > 1 {
            globalSongs = explorePage.sections.last?.items ?? []
        }
        
        return (countrySongs, globalSongs, countryName)
    }
}
