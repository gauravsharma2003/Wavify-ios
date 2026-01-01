//
//  LocalPlaylist.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation
import SwiftData

@Model
final class LocalPlaylist {
    var name: String
    var createdAt: Date
    var albumId: String?
    var storedThumbnailUrl: String?
    
    @Relationship(deleteRule: .nullify)
    var songs: [LocalSong]
    
    init(name: String, thumbnailUrl: String? = nil, albumId: String? = nil) {
        self.name = name
        self.createdAt = .now
        self.songs = []
        self.storedThumbnailUrl = thumbnailUrl
        self.albumId = albumId
    }
    
    var songCount: Int {
        songs.count
    }
    
    var thumbnailUrl: String? {
        storedThumbnailUrl ?? sortedSongs.first?.thumbnailUrl
    }
    
    /// Songs sorted by orderIndex for correct display order
    var sortedSongs: [LocalSong] {
        songs.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
    }
}
