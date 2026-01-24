//
//  SharedSongData.swift
//  Wavify
//
//  Shared model for widget-app communication via App Groups
//

import Foundation

/// Lightweight Codable model for sharing song data between app and widget
struct SharedSongData: Codable {
    let videoId: String
    let title: String
    let artist: String
    let thumbnailUrl: String
    let duration: String
    var isPlaying: Bool
    var currentTime: Double  // Playback position in seconds
    var totalDuration: Double  // Total duration in seconds
    var artistId: String?
    var albumId: String?
    
    init(from song: Song, isPlaying: Bool, currentTime: Double = 0, totalDuration: Double = 0) {
        self.videoId = song.videoId
        self.title = song.title
        self.artist = song.artist
        self.thumbnailUrl = song.thumbnailUrl
        self.duration = song.duration
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.artistId = song.artistId
        self.albumId = song.albumId
    }
    
    init(videoId: String, title: String, artist: String, thumbnailUrl: String, duration: String, isPlaying: Bool, currentTime: Double = 0, totalDuration: Double = 0, artistId: String? = nil, albumId: String? = nil) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.artistId = artistId
        self.albumId = albumId
    }
    
    /// Convert back to Song model
    func toSong() -> Song {
        Song(
            id: videoId,
            title: title,
            artist: artist,
            thumbnailUrl: thumbnailUrl,
            duration: duration,
            isLiked: false,
            artistId: artistId,
            albumId: albumId
        )
    }
}
