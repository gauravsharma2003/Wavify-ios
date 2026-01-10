//
//  LanguageChart.swift
//  Wavify
//
//  Model for language-specific music charts
//

import Foundation

/// Represents a language-specific chart with its songs
struct LanguageChart: Identifiable, Hashable {
    let id: String      // Playlist ID (browseId)
    let name: String    // Language name (e.g., "Hindi", "Punjabi")
    let playlistId: String
    var thumbnailUrl: String
    var songs: [SearchResult]
    
    var displayName: String {
        // Format: "Top Weekly Videos Hindi" -> "Hindi"
        // Or just return the name if it's already clean
        if name.contains("Top Weekly Videos") {
            return name.replacingOccurrences(of: "Top Weekly Videos ", with: "")
        }
        return name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LanguageChart, rhs: LanguageChart) -> Bool {
        lhs.id == rhs.id
    }
}
