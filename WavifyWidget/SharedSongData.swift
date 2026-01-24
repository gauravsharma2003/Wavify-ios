//
//  SharedSongData.swift
//  WavifyWidget
//
//  Copy of shared model for widget (same structure as main app)
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
}
