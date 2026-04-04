//
//  LyricsModels.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation

// MARK: - Synced Word (word-level timing)

struct SyncedWord: Identifiable, Equatable {
    let id: UUID
    let startTime: Double   // seconds
    let endTime: Double     // seconds
    let text: String

    init(startTime: Double, endTime: Double, text: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

// MARK: - Synced Lyric Line

struct SyncedLyricLine: Identifiable, Equatable {
    let id: UUID
    let time: Double            // Time in seconds
    let endTime: Double?        // End time in seconds (from TTML)
    let text: String            // Lyric text
    let words: [SyncedWord]?    // Word-level timing (from TTML/syllable providers)

    init(time: Double, text: String, endTime: Double? = nil, words: [SyncedWord]? = nil) {
        self.id = UUID()
        self.time = time
        self.endTime = endTime
        self.text = text
        self.words = words
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
    case betterLyrics = "BetterLyrics"
    case paxsenix = "Paxsenix"
    case lrcLib = "LrcLib"
    case kuGou = "KuGou"
    case lyricsPlus = "LyricsPlus"
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

// MARK: - BetterLyrics API Response

struct BetterLyricsResponse: Codable {
    let ttml: String?
}

// MARK: - Paxsenix API Responses

struct PaxsenixSearchResult: Codable {
    let id: Int
    let songName: String?
    let trackName: String?
    let artistName: String?
    let duration: Int?  // milliseconds
}

struct PaxsenixLyricsResponse: Codable {
    let type: String?
    let content: [PaxsenixSyllable]?
    let ttmlContent: String?
    let elrc: String?
    let plain: String?
}

struct PaxsenixSyllable: Codable {
    let timestamp: Double?  // milliseconds
    let endtime: Double?    // milliseconds
    let text: [PaxsenixSyllableWord]?
}

struct PaxsenixSyllableWord: Codable {
    let text: String?
    let timestamp: Double?  // milliseconds
    let endtime: Double?    // milliseconds
}

// MARK: - LyricsPlus API Response

struct LyricsPlusResponse: Codable {
    let type: String?
    let lyrics: [LyricsPlusLine]?
}

struct LyricsPlusLine: Codable {
    let time: Double?       // milliseconds
    let duration: Double?   // milliseconds
    let text: String?
}
