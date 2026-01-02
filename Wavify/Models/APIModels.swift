//
//  APIModels.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation

// MARK: - Search Result Types

enum SearchResultType: String, Codable {
    case song
    case artist
    case album
    case playlist
    case video
}

struct SearchResult: Identifiable, Hashable {
    let id: String
    let name: String
    let thumbnailUrl: String
    let isExplicit: Bool
    let year: String
    let artist: String
    let type: SearchResultType
    var artistId: String? = nil
    var albumId: String? = nil
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

enum SearchSuggestion: Identifiable, Hashable {
    case text(String)
    case result(SearchResult)
    
    var id: String {
        switch self {
        case .text(let text): return text
        case .result(let result): return result.id
        }
    }
}

// MARK: - Home Page Models

struct HomePage {
    var chips: [Chip]
    var sections: [HomeSection]
    var continuation: String?
}

struct Chip: Identifiable, Hashable {
    let title: String
    let endpoint: BrowseEndpoint
    var isSelected: Bool = false
    
    var id: String { title }
}

struct BrowseEndpoint: Hashable {
    let browseId: String
    let params: String?
}

struct HomeSection: Identifiable {
    let id = UUID()
    let title: String
    let strapline: String?
    let items: [SearchResult]
}

// MARK: - Playback Info

struct PlaybackInfo {
    let audioUrl: String
    let videoId: String
    let title: String
    let duration: String
    let thumbnailUrl: String
    let artist: String
    let viewCount: String
    let artistId: String?
    let albumId: String?
}

// MARK: - Queue Song

struct QueueSong: Identifiable, Hashable {
    let id: String // videoId
    let name: String
    let artist: String
    let thumbnailUrl: String
    let duration: String
    
    var videoId: String { id }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: QueueSong, rhs: QueueSong) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Album Detail

struct AlbumDetail {
    let albumId: String
    let albumThumbnail: String
    let albumName: String
    let artist: String
    let artistThumbnail: String
    let songCount: String
    let duration: String
    let songs: [AlbumSong]
    let relatedAlbums: [RelatedAlbum]
}

struct AlbumSong: Identifiable, Hashable {
    let id: String // videoId
    let title: String
    let viewCount: String
    let duration: String
    
    var videoId: String { id }
}

struct RelatedAlbum: Identifiable, Hashable {
    let id: String // albumId
    let name: String
    let thumbnailUrl: String
    let artist: String
    
    var albumId: String { id }
}

// MARK: - Display Song (Unified model for UI)

struct Song: Identifiable, Hashable {
    let id: String // videoId
    let title: String
    let artist: String
    let thumbnailUrl: String
    let duration: String
    var isLiked: Bool
    var artistId: String? = nil
    var albumId: String? = nil
    var isRecommendation: Bool = false
    
    var videoId: String { id }
    
    init(from searchResult: SearchResult) {
        self.id = searchResult.id
        self.title = searchResult.name
        self.artist = searchResult.artist
        self.thumbnailUrl = searchResult.thumbnailUrl
        self.duration = ""
        self.isLiked = false
        self.artistId = searchResult.artistId
        self.albumId = searchResult.albumId
    }
    
    init(from queueSong: QueueSong) {
        self.id = queueSong.id
        self.title = queueSong.name
        self.artist = queueSong.artist
        self.thumbnailUrl = queueSong.thumbnailUrl
        self.duration = queueSong.duration
        self.isLiked = false
    }
    
    init(from albumSong: AlbumSong, artist: String, thumbnailUrl: String) {
        self.id = albumSong.id
        self.title = albumSong.title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.duration = albumSong.duration
        self.isLiked = false
    }
    
    init(from localSong: LocalSong) {
        self.id = localSong.videoId
        self.title = localSong.title
        self.artist = localSong.artist
        self.thumbnailUrl = localSong.thumbnailUrl
        self.duration = localSong.duration
        self.isLiked = localSong.isLiked
    }
    
    init(from history: RecentHistory) {
        self.id = history.videoId
        self.title = history.title
        self.artist = history.artist
        self.thumbnailUrl = history.thumbnailUrl
        self.duration = history.duration
        self.isLiked = false
    }
    
    init(
        id: String,
        title: String,
        artist: String,
        thumbnailUrl: String,
        duration: String,
        isLiked: Bool = false,
        artistId: String? = nil,
        albumId: String? = nil,
        isRecommendation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.isLiked = isLiked
        self.artistId = artistId
        self.albumId = albumId
        self.isRecommendation = isRecommendation
    }

}

// MARK: - API Errors

enum YouTubeMusicError: Error, LocalizedError {
    case invalidURL
    case noResults
    case playbackNotAvailable
    case unsupportedFormat
    case networkError(Error)
    case parseError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noResults:
            return "No results found"
        case .playbackNotAvailable:
            return "Playback not available"
        case .unsupportedFormat:
            return "Unsupported audio format"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .invalidResponse:
            return "Invalid API response"
        }
    }
}
