//
//  LocalSong.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation
import SwiftData

@Model
final class LocalSong {
    @Attribute(.unique) var videoId: String
    var title: String
    var artist: String
    var thumbnailUrl: String
    var duration: String
    var isLiked: Bool
    var addedAt: Date
    var orderIndex: Int?  // Optional for migration compatibility
    
    @Relationship(inverse: \LocalPlaylist.songs)
    var playlists: [LocalPlaylist]?
    
    init(
        videoId: String,
        title: String,
        artist: String,
        thumbnailUrl: String,
        duration: String = "",
        isLiked: Bool = false,
        orderIndex: Int = 0
    ) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.isLiked = isLiked
        self.addedAt = .now
        self.orderIndex = orderIndex
    }
}
