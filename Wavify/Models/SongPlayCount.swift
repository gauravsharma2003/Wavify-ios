//
//  SongPlayCount.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import Foundation
import SwiftData

@Model
final class SongPlayCount {
    @Attribute(.unique) var videoId: String
    var title: String
    var artist: String
    var thumbnailUrl: String
    var duration: String
    var playCount: Int
    var lastPlayedAt: Date
    
    init(
        videoId: String,
        title: String,
        artist: String,
        thumbnailUrl: String,
        duration: String
    ) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.playCount = 1
        self.lastPlayedAt = .now
    }
    
    /// Increment play count and update last played time
    func incrementPlayCount() {
        self.playCount += 1
        self.lastPlayedAt = .now
    }
}

// MARK: - Conversion to SearchResult for UI compatibility

extension SongPlayCount {
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: videoId,
            name: title,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: "",
            artist: artist,
            type: .song
        )
    }
}
