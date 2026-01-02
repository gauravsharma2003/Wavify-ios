//
//  PlaylistManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation
import SwiftData

/// Centralized manager for playlist operations
@MainActor
class PlaylistManager {
    static let shared = PlaylistManager()
    
    private init() {}
    
    // MARK: - Add Song to Playlist
    
    /// Adds a song to a playlist at the last position
    func addSong(_ song: Song, to playlist: LocalPlaylist, in context: ModelContext) {
        // Check if song already exists in playlist
        if playlist.songs.contains(where: { $0.videoId == song.videoId }) {
            return // Song already in playlist
        }
        
        // Find or create LocalSong
        let localSong = findOrCreateLocalSong(for: song, in: context)
        
        // Calculate new order index (add to end)
        let maxIndex = playlist.songs.map { $0.orderIndex ?? 0 }.max() ?? -1
        localSong.orderIndex = maxIndex + 1
        
        // Add to playlist
        playlist.songs.append(localSong)
        
        try? context.save()
    }
    
    /// Adds a song to multiple playlists
    func addSong(_ song: Song, to playlists: [LocalPlaylist], in context: ModelContext) {
        for playlist in playlists {
            addSong(song, to: playlist, in: context)
        }
    }
    
    // MARK: - Remove Song from Playlist
    
    /// Removes a song from a playlist
    func removeSong(_ song: Song, from playlist: LocalPlaylist, in context: ModelContext) {
        playlist.songs.removeAll { $0.videoId == song.videoId }
        try? context.save()
    }
    
    // MARK: - Check Song in Playlist
    
    /// Checks if a song is already in a playlist
    func isSongInPlaylist(_ song: Song, playlist: LocalPlaylist) -> Bool {
        playlist.songs.contains { $0.videoId == song.videoId }
    }
    
    /// Returns set of playlist IDs that contain the song
    func playlistsContainingSong(_ song: Song, from playlists: [LocalPlaylist]) -> Set<String> {
        Set(playlists.filter { playlist in
            playlist.songs.contains { $0.videoId == song.videoId }
        }.compactMap { $0.persistentModelID.storeIdentifier })
    }
    
    // MARK: - Create Playlist
    
    /// Creates a new empty playlist
    func createPlaylist(name: String, in context: ModelContext) -> LocalPlaylist {
        let playlist = LocalPlaylist(name: name)
        context.insert(playlist)
        try? context.save()
        return playlist
    }
    
    // MARK: - Toggle Like
    
    /// Toggles the liked status of a song
    func toggleLike(for song: Song, in context: ModelContext) -> Bool {
        let videoId = song.videoId
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        
        if let existingSong = try? context.fetch(descriptor).first {
            existingSong.isLiked.toggle()
            try? context.save()
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
            try? context.save()
            return true
        }
    }
    
    /// Checks if a song is liked
    func isLiked(_ song: Song, in context: ModelContext) -> Bool {
        let videoId = song.videoId
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId && $0.isLiked == true }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }
    
    // MARK: - Helper
    
    private func findOrCreateLocalSong(for song: Song, in context: ModelContext) -> LocalSong {
        let videoId = song.videoId
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        
        if let existingSong = try? context.fetch(descriptor).first {
            return existingSong
        }
        
        let newSong = LocalSong(
            videoId: song.videoId,
            title: song.title,
            artist: song.artist,
            thumbnailUrl: song.thumbnailUrl,
            duration: song.duration
        )
        context.insert(newSong)
        return newSong
    }
}
