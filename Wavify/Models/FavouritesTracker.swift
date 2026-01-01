//
//  FavouritesTracker.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation
import SwiftData

// MARK: - Album Play Count Model

@Model
final class AlbumPlayCount {
    @Attribute(.unique) var albumId: String
    var title: String
    var artist: String
    var thumbnailUrl: String
    var playCount: Int
    var lastPlayedAt: Date
    
    init(albumId: String, title: String, artist: String, thumbnailUrl: String) {
        self.albumId = albumId
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.playCount = 1
        self.lastPlayedAt = .now
    }
    
    func incrementPlayCount() {
        self.playCount += 1
        self.lastPlayedAt = .now
    }
    
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: albumId,
            name: title,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: "",
            artist: artist,
            type: .album
        )
    }
}

// MARK: - Artist Play Count Model

@Model
final class ArtistPlayCount {
    @Attribute(.unique) var artistId: String
    var name: String
    var thumbnailUrl: String
    var playCount: Int
    var lastPlayedAt: Date
    
    init(artistId: String, name: String, thumbnailUrl: String) {
        self.artistId = artistId
        self.name = name
        self.thumbnailUrl = thumbnailUrl
        self.playCount = 1
        self.lastPlayedAt = .now
    }
    
    func incrementPlayCount() {
        self.playCount += 1
        self.lastPlayedAt = .now
    }
    
    func toSearchResult() -> SearchResult {
        SearchResult(
            id: artistId,
            name: name,
            thumbnailUrl: thumbnailUrl,
            isExplicit: false,
            year: "",
            artist: "",
            type: .artist
        )
    }
}
