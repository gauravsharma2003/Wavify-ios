//
//  BackgroundDataManager.swift
//  Wavify
//
//  Background actor for SwiftData operations to keep main thread responsive
//

import Foundation
import SwiftData

/// Actor for performing SwiftData operations on a background context
/// This keeps the main thread free for UI updates
actor BackgroundDataManager {
    static let shared = BackgroundDataManager()
    
    private var container: ModelContainer?
    
    private init() {}
    
    /// Configure the manager with the app's ModelContainer
    /// Must be called during app initialization
    func configure(with container: ModelContainer) {
        self.container = container
    }
    
    /// Increment play count for a song on a background context
    func incrementPlayCount(for song: Song) async {
        guard let container = container else {
            Logger.warning("Container not configured", category: .data)
            return
        }
        
        let context = ModelContext(container)
        let videoId = song.videoId
        let title = song.title
        let artist = song.artist
        let thumbnailUrl = song.thumbnailUrl
        let duration = song.duration
        let artistId = song.artistId
        
        let descriptor = FetchDescriptor<SongPlayCount>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            
            if let playCount = existing.first {
                // Update existing entry
                playCount.incrementPlayCount()
                playCount.updateArtistIdIfNeeded(artistId)
            } else {
                // Create new entry
                let newPlayCount = SongPlayCount(
                    videoId: videoId,
                    title: title,
                    artist: artist,
                    thumbnailUrl: thumbnailUrl,
                    duration: duration,
                    artistId: artistId
                )
                context.insert(newPlayCount)
            }
            
            try context.save()
        } catch {
            Logger.dataError("Failed to update play count", error: error)
        }
    }
    
    /// Track album play on background context
    func trackAlbumPlay(albumId: String, title: String, artist: String, thumbnailUrl: String) async {
        guard let container = container else {
            Logger.warning("Container not configured", category: .data)
            return
        }
        
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<AlbumPlayCount>(
            predicate: #Predicate { $0.albumId == albumId }
        )
        
        do {
            let existing = try context.fetch(descriptor)

            if let albumCount = existing.first {
                albumCount.incrementPlayCount()
                // Update title if a real name is provided and stored title is empty/placeholder
                if !title.isEmpty && title != "Album" && (albumCount.title.isEmpty || albumCount.title == "Album") {
                    albumCount.title = title
                }
            } else {
                // Only create a new record if we have a real album name
                guard !title.isEmpty else { return }
                let newAlbumCount = AlbumPlayCount(
                    albumId: albumId,
                    title: title,
                    artist: artist,
                    thumbnailUrl: thumbnailUrl
                )
                context.insert(newAlbumCount)
            }

            try context.save()
        } catch {
            Logger.dataError("Failed to track album play", error: error)
        }
    }
    
    /// Track artist play on background context
    /// Always fetches the correct artist thumbnail from API (song thumbnails are never reliable)
    func trackArtistPlay(artistId: String, name: String, thumbnailUrl: String) async {
        guard let container = container else {
            Logger.warning("Container not configured", category: .data)
            return
        }
        
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<ArtistPlayCount>(
            predicate: #Predicate { $0.artistId == artistId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            
            if let artistCount = existing.first {
                artistCount.incrementPlayCount()
                
                // If existing thumbnail is empty, fetch from API
                if artistCount.thumbnailUrl.isEmpty {
                    let capturedArtistId = artistId
                    Task.detached(priority: .background) { [weak self] in
                        if let correctThumbnail = await self?.fetchArtistThumbnail(artistId: capturedArtistId) {
                            await self?.updateStoredArtistThumbnail(artistId: capturedArtistId, thumbnailUrl: correctThumbnail)
                        }
                    }
                }
            } else {
                // New artist - always fetch from API, never trust song thumbnail
                let newArtistCount = ArtistPlayCount(
                    artistId: artistId,
                    name: name,
                    thumbnailUrl: ""  // Start empty, fetch proper image from API
                )
                context.insert(newArtistCount)
                
                // Fetch correct artist thumbnail in background
                let capturedArtistId = artistId
                Task.detached(priority: .background) { [weak self] in
                    if let correctThumbnail = await self?.fetchArtistThumbnail(artistId: capturedArtistId) {
                        await self?.updateStoredArtistThumbnail(artistId: capturedArtistId, thumbnailUrl: correctThumbnail)
                    }
                }
            }
            
            try context.save()
        } catch {
            Logger.dataError("Failed to track artist play", error: error)
        }
    }
    
    /// Check if a thumbnail URL is a proper artist image (not a song/video thumbnail)
    private func isProperArtistThumbnail(_ url: String) -> Bool {
        guard !url.isEmpty else { return false }
        // Song/video thumbnails use i.ytimg.com
        // Artist thumbnails use googleusercontent.com or ggpht.com
        return !url.contains("i.ytimg.com") && 
               (url.contains("googleusercontent.com") || url.contains("ggpht.com"))
    }
    
    /// Fetch just the artist thumbnail from API
    /// Returns nil if fetch fails
    private func fetchArtistThumbnail(artistId: String) async -> String? {
        do {
            let artistDetail = try await NetworkManager.shared.getArtistDetails(browseId: artistId)
            let thumbnail = artistDetail.thumbnailUrl
            
            // Verify it's a proper artist thumbnail
            if isProperArtistThumbnail(thumbnail) {
                return thumbnail
            }
        } catch {
            Logger.networkError("Failed to fetch artist thumbnail for favourites", error: error)
        }
        return nil
    }
    
    /// Update stored artist thumbnail in the database
    /// Also refreshes the in-memory FavouritesManager cache
    private func updateStoredArtistThumbnail(artistId: String, thumbnailUrl: String) async {
        guard let container = container else { return }
        
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<ArtistPlayCount>(
            predicate: #Predicate { $0.artistId == artistId }
        )
        
        do {
            if let artistCount = try context.fetch(descriptor).first {
                artistCount.thumbnailUrl = thumbnailUrl
                try context.save()
                
                // Also update the in-memory favourites cache
                await MainActor.run {
                    FavouritesManager.shared.refreshCachedFavouritesThumbnail(artistId: artistId, newThumbnailUrl: thumbnailUrl)
                }
            }
        } catch {
            Logger.dataError("Failed to update stored artist thumbnail", error: error)
        }
    }
    
    /// Update artist thumbnail if the current one is incorrect
    func updateArtistThumbnailIfNeeded(artistId: String, correctThumbnailUrl: String) async {
        guard let container = container else { return }
        
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<ArtistPlayCount>(
            predicate: #Predicate { $0.artistId == artistId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            
            if let artistCount = existing.first {
                // Only update if the thumbnail is different
                if artistCount.thumbnailUrl != correctThumbnailUrl {
                    artistCount.thumbnailUrl = correctThumbnailUrl
                    try context.save()
                }
            }
        } catch {
            Logger.dataError("Failed to update artist thumbnail", error: error)
        }
    }
    
    // MARK: - Like Operations
    
    /// Toggle like status for a song on background context
    /// Returns true if song is now liked, false if unliked
    func toggleLike(for song: Song) async -> Bool {
        guard let container = container else {
            Logger.warning("Container not configured", category: .data)
            return false
        }
        
        let context = ModelContext(container)
        let videoId = song.videoId
        
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        
        do {
            if let existingSong = try context.fetch(descriptor).first {
                existingSong.isLiked.toggle()
                try context.save()
                return existingSong.isLiked
            } else {
                // Create new LocalSong with isLiked = true
                let newSong = LocalSong(
                    videoId: song.videoId,
                    title: song.title,
                    artist: song.artist,
                    thumbnailUrl: song.thumbnailUrl,
                    duration: song.duration,
                    isLiked: true
                )
                context.insert(newSong)
                try context.save()
                return true
            }
        } catch {
            Logger.dataError("Failed to toggle like", error: error)
            return false
        }
    }
    
    /// Get all liked song IDs on background context
    func getLikedSongIds() async -> Set<String> {
        guard let container = container else {
            Logger.warning("Container not configured", category: .data)
            return []
        }
        
        let context = ModelContext(container)
        
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.isLiked == true }
        )
        
        do {
            let likedSongs = try context.fetch(descriptor)
            return Set(likedSongs.map { $0.videoId })
        } catch {
            Logger.dataError("Failed to get liked songs", error: error)
            return []
        }
    }
}
