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
            } else {
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
                // Update thumbnail if provided and different
                if !thumbnailUrl.isEmpty && artistCount.thumbnailUrl != thumbnailUrl {
                    artistCount.thumbnailUrl = thumbnailUrl
                }
            } else {
                let newArtistCount = ArtistPlayCount(
                    artistId: artistId,
                    name: name,
                    thumbnailUrl: thumbnailUrl
                )
                context.insert(newArtistCount)
            }
            
            try context.save()
        } catch {
            Logger.dataError("Failed to track artist play", error: error)
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
