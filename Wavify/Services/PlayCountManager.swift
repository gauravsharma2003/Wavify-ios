//
//  PlayCountManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import Foundation
import SwiftData

/// Manages song play count tracking using SwiftData
@MainActor
class PlayCountManager {
    static let shared = PlayCountManager()
    
    private init() {}
    
    /// Increment play count for a song (creates entry if doesn't exist)
    func incrementPlayCount(for song: Song, in context: ModelContext) {
        let videoId = song.videoId
        print("DEBUG [PlayCountManager]: Recording play for videoId=\(videoId), artistId=\(song.artistId ?? "nil")")
        
        // Try to find existing entry
        let descriptor = FetchDescriptor<SongPlayCount>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        
        do {
            let existing = try context.fetch(descriptor)
            
            if let playCount = existing.first {
                // Update existing entry
                playCount.incrementPlayCount()
                // Update artistId if not already set (for records created before this field existed)
                playCount.updateArtistIdIfNeeded(song.artistId)
            } else {
                // Create new entry with artistId
                let newPlayCount = SongPlayCount(
                    videoId: song.videoId,
                    title: song.title,
                    artist: song.artist,
                    thumbnailUrl: song.thumbnailUrl,
                    duration: song.duration,
                    artistId: song.artistId
                )
                context.insert(newPlayCount)
            }
            
            try context.save()
        } catch {
            print("Failed to update play count: \(error)")
        }
    }
    
    /// Get top played songs sorted by play count (descending)
    func getTopPlayedSongs(limit: Int = 5, in context: ModelContext) -> [SongPlayCount] {
        let descriptor = FetchDescriptor<SongPlayCount>(
            sortBy: [SortDescriptor(\.playCount, order: .reverse)]
        )
        
        do {
            let allSongs = try context.fetch(descriptor)
            return Array(allSongs.prefix(limit))
        } catch {
            print("Failed to fetch top played songs: \(error)")
            return []
        }
    }
    
    /// Check if user has any play history
    func hasPlayHistory(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SongPlayCount>()
        
        do {
            let count = try context.fetchCount(descriptor)
            return count > 0
        } catch {
            print("Failed to check play history: \(error)")
            return false
        }
    }
}

// MARK: - Notification for song play events

extension Notification.Name {
    static let songDidStartPlaying = Notification.Name("songDidStartPlaying")
}
