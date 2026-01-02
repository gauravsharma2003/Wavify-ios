//
//  LyricsModels.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation

// MARK: - Synced Lyric Line

struct SyncedLyricLine: Identifiable, Equatable {
    let id: UUID
    let time: Double       // Time in seconds
    let text: String       // Lyric text
    
    init(time: Double, text: String) {
        self.id = UUID()
        self.time = time
        self.text = text
    }
}

// MARK: - Lyrics Result

struct LyricsResult {
    let syncedLyrics: [SyncedLyricLine]?  // Priority - time-synced
    let plainLyrics: String?               // Fallback - plain text
    let source: LyricsSource
    
    static let empty = LyricsResult(syncedLyrics: nil, plainLyrics: nil, source: .none)
}

// MARK: - Lyrics Source

enum LyricsSource: String {
    case lrcLib = "LrcLib"
    case kuGou = "KuGou"
    case none = "None"
}

// MARK: - Lyrics State

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([SyncedLyricLine])
    case plain(String)
    case notFound
    case error(String)
    
    static func == (lhs: LyricsState, rhs: LyricsState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.notFound, .notFound):
            return true
        case (.synced(let l), .synced(let r)):
            return l == r
        case (.plain(let l), .plain(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - LrcLib API Response

struct LrcLibSearchResult: Codable {
    let id: Int
    let trackName: String
    let artistName: String
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
}

// MARK: - KuGou API Responses

struct KuGouSearchResponse: Codable {
    let candidates: [KuGouCandidate]?
}

struct KuGouCandidate: Codable {
    let id: String
    let accesskey: String
    let duration: Int?
}

struct KuGouLyricsResponse: Codable {
    let content: String? // Base64 encoded lyrics
}
