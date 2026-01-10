//
//  FavouritesManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation
import SwiftData

/// Cached favourite item for persistence
struct CachedFavouriteItem: Codable {
    let id: String
    let name: String
    let thumbnailUrl: String
    let artist: String
    let type: String  // "song", "album", "artist"
    let artistId: String?  // Added for artist navigation
    
    func toSearchResult() -> SearchResult {
        let resultType: SearchResultType
        switch type {
        case "album": resultType = .album
        case "artist": resultType = .artist
        default: resultType = .song
        }
        return SearchResult(
            id: id,
            name: name,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: "",
            artist: artist,
            type: resultType,
            artistId: artistId
        )
    }
}

/// Manages "Your Favourites" section showing top songs, albums, and artists
@MainActor
@Observable
class FavouritesManager {
    static let shared = FavouritesManager()
    
    // Current items to display
    private(set) var favourites: [SearchResult] = []
    private var isLoading = false
    
    // UserDefaults key
    private let cacheKey = "cachedFavourites"
    
    // Configuration
    private let minItemsRequired = 4
    private let maxItems = 16  // Max items for 2 rows x 8 columns
    
    private init() {
        loadCachedFavourites()
    }
    
    // MARK: - Public Methods
    
    func loadCachedFavourites() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([CachedFavouriteItem].self, from: data) else {
            favourites = []
            return
        }
        favourites = cached.map { $0.toSearchResult() }
    }
    
    /// Refresh favourites from database (for app launch and pull-to-refresh)
    /// Pattern: 1 artist, 1 album, 2 songs (repeating)
    /// If no albums: 1 artist, 3 songs (repeating)
    func refreshFavourites(in context: ModelContext) -> [SearchResult] {
        guard !isLoading else { return favourites }
        isLoading = true
        defer { isLoading = false }
        
        // Get top songs (sorted by play count)
        var songs: [SearchResult] = []
        let songDescriptor = FetchDescriptor<SongPlayCount>(
            sortBy: [SortDescriptor(\.playCount, order: .reverse)]
        )
        if let fetchedSongs = try? context.fetch(songDescriptor) {
            songs = fetchedSongs.map { $0.toSearchResult() }
        }
        
        // Get top albums (sorted by play count)
        var albums: [SearchResult] = []
        let albumDescriptor = FetchDescriptor<AlbumPlayCount>(
            sortBy: [SortDescriptor(\.playCount, order: .reverse)]
        )
        if let fetchedAlbums = try? context.fetch(albumDescriptor) {
            albums = fetchedAlbums.map { $0.toSearchResult() }
        }
        
        // Get top artists (sorted by play count)
        var artists: [SearchResult] = []
        let artistDescriptor = FetchDescriptor<ArtistPlayCount>(
            sortBy: [SortDescriptor(\.playCount, order: .reverse)]
        )
        if let fetchedArtists = try? context.fetch(artistDescriptor) {
            artists = fetchedArtists.map { $0.toSearchResult() }
        }
        
        // Build results using pattern
        var results: [SearchResult] = []
        var seenIds = Set<String>()  // Track seen IDs to prevent duplicates
        var artistIndex = 0
        var albumIndex = 0
        var songIndex = 0
        
        let hasAlbums = !albums.isEmpty
        
        // Helper to add a song (skipping duplicates)
        func addNextSong() -> Bool {
            while songIndex < songs.count {
                let song = songs[songIndex]
                songIndex += 1
                if !seenIds.contains(song.id) {
                    seenIds.insert(song.id)
                    results.append(song)
                    return true
                }
            }
            return false
        }
        
        // Helper to add an artist (or song if duplicate)
        func addNextArtist() -> Bool {
            while artistIndex < artists.count {
                let artist = artists[artistIndex]
                artistIndex += 1
                if !seenIds.contains(artist.id) {
                    seenIds.insert(artist.id)
                    results.append(artist)
                    return true
                }
            }
            // No unique artist available, try adding a song instead
            return addNextSong()
        }
        
        // Helper to add an album (or song if duplicate)
        func addNextAlbum() -> Bool {
            while albumIndex < albums.count {
                let album = albums[albumIndex]
                albumIndex += 1
                if !seenIds.contains(album.id) {
                    seenIds.insert(album.id)
                    results.append(album)
                    return true
                }
            }
            // No unique album available, try adding a song instead
            return addNextSong()
        }
        
        // NEW Pattern:
        // 1. First: 1 artist (only once at start)
        // 2. Then: 1 album/playlist
        // 3. Then: 2 songs
        // 4. Repeat: 1 album + 3 songs until maxItems
        // If no albums: fill with songs after artist
        // If only 1 album: just put it after artist, then songs
        
        // Step 1: Add 1 artist at the start
        _ = addNextArtist()
        if results.count >= maxItems { 
            // Continue to save results
        } else if hasAlbums {
            // Step 2: Add 1 album below artist
            _ = addNextAlbum()
            
            if results.count < maxItems {
                // Step 3: Add 2 songs
                for _ in 0..<2 {
                    if results.count < maxItems {
                        if !addNextSong() { break }
                    }
                }
            }
            
            // Step 4: Repeat: 1 album + 3 songs
            while results.count < maxItems {
                let albumsExhausted = albumIndex >= albums.count
                let songsExhausted = songIndex >= songs.count
                
                if albumsExhausted && songsExhausted { break }
                
                // Add 1 album (if available)
                if !albumsExhausted {
                    _ = addNextAlbum()
                }
                
                // Add 3 songs
                for _ in 0..<3 {
                    if results.count < maxItems {
                        if !addNextSong() { break }
                    }
                }
            }
        } else {
            // No albums: fill with songs
            while results.count < maxItems && songIndex < songs.count {
                if !addNextSong() { break }
            }
        }
        
        // Only show if we have enough items
        guard results.count >= minItemsRequired else {
            favourites = []
            saveToCache([])
            return []
        }
        
        favourites = results
        saveToCache(results)
        return results
    }
    
    var shouldShowSection: Bool {
        favourites.count >= minItemsRequired
    }
    
    // MARK: - Track Album Play
    
    func trackAlbumPlay(albumId: String, title: String, artist: String, thumbnailUrl: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<AlbumPlayCount>(
            predicate: #Predicate { $0.albumId == albumId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            if let album = existing.first {
                album.incrementPlayCount()
            } else {
                let newAlbum = AlbumPlayCount(
                    albumId: albumId,
                    title: title,
                    artist: artist,
                    thumbnailUrl: thumbnailUrl
                )
                context.insert(newAlbum)
            }
            try context.save()
        } catch {
            Logger.dataError("Failed to track album play", error: error)
        }
    }
    
    // MARK: - Track Artist Play
    
    /// Check if a thumbnail URL is a proper artist image (not a song/video thumbnail)
    private func isArtistThumbnail(_ url: String) -> Bool {
        // Song/video thumbnails use i.ytimg.com
        // Artist thumbnails use googleusercontent.com
        return !url.contains("i.ytimg.com") && (url.contains("googleusercontent.com") || url.contains("ggpht.com"))
    }
    
    func trackArtistPlay(artistId: String, name: String, thumbnailUrl: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<ArtistPlayCount>(
            predicate: #Predicate { $0.artistId == artistId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            if let artist = existing.first {
                artist.incrementPlayCount()
                // Update thumbnail if we're given a proper artist thumbnail
                // (previous thumbnail might have been a song thumbnail)
                if isArtistThumbnail(thumbnailUrl) && !isArtistThumbnail(artist.thumbnailUrl) {
                    artist.thumbnailUrl = thumbnailUrl
                }
            } else {
                let newArtist = ArtistPlayCount(
                    artistId: artistId,
                    name: name,
                    thumbnailUrl: thumbnailUrl
                )
                context.insert(newArtist)
            }
            try context.save()
        } catch {
            Logger.dataError("Failed to track artist play", error: error)
        }
    }
    
    // MARK: - Update Artist Thumbnail
    
    /// Update stored artist thumbnail when the correct artist image becomes available
    /// Called when ArtistDetailView loads and gets the real artist thumbnail
    func updateArtistThumbnailIfNeeded(artistId: String, correctThumbnailUrl: String, in context: ModelContext) {
        // Only update if it's a proper artist thumbnail
        guard isArtistThumbnail(correctThumbnailUrl) else { return }
        
        let descriptor = FetchDescriptor<ArtistPlayCount>(
            predicate: #Predicate { $0.artistId == artistId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            if let artist = existing.first {
                // Only update if current thumbnail is NOT a proper artist image
                if !isArtistThumbnail(artist.thumbnailUrl) {
                    artist.thumbnailUrl = correctThumbnailUrl
                    try context.save()
                    
                    // Also update the cached favourites to show the correct image
                    refreshCachedFavouritesThumbnail(artistId: artistId, newThumbnailUrl: correctThumbnailUrl)
                }
            }
        } catch {
            Logger.dataError("Failed to update artist thumbnail", error: error)
        }
    }
    
    /// Update the cached favourites with the correct thumbnail URL
    private func refreshCachedFavouritesThumbnail(artistId: String, newThumbnailUrl: String) {
        // Update in-memory favourites
        if let index = favourites.firstIndex(where: { $0.id == artistId && $0.type == .artist }) {
            let old = favourites[index]
            favourites[index] = SearchResult(
                id: old.id,
                name: old.name,
                thumbnailUrl: newThumbnailUrl,
                isExplicit: old.isExplicit,
                year: old.year,
                artist: old.artist,
                type: old.type,
                artistId: old.artistId
            )
        }
        
        // Update UserDefaults cache
        saveToCache(favourites)
    }
    
    // MARK: - Private Methods
    
    private func saveToCache(_ results: [SearchResult]) {
        let cached = results.map { result in
            CachedFavouriteItem(
                id: result.id,
                name: result.name,
                thumbnailUrl: result.thumbnailUrl,
                artist: result.artist,
                type: result.type == .album ? "album" : (result.type == .artist ? "artist" : "song"),
                artistId: result.artistId
            )
        }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
