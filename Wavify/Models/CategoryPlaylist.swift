//
//  CategoryPlaylist.swift
//  Wavify
//
//  Model representing a playlist from a random category section
//

import Foundation

/// Represents a playlist or album fetched from a random category on the explore page
struct CategoryPlaylist: Identifiable, Hashable {
    let id: String          // Playlist/Album ID (browseId)
    let name: String        // Playlist/Album title
    let thumbnailUrl: String
    let playlistId: String
    let subtitle: String?   // e.g., artist name or description
    let isAlbum: Bool       // True if this is an album (MPREb prefix)
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CategoryPlaylist, rhs: CategoryPlaylist) -> Bool {
        lhs.id == rhs.id
    }
}
