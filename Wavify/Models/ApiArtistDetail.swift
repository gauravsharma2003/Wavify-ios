//
//  ApiArtistDetail.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import Foundation

struct ArtistDetail: Identifiable {
    let id: String // browseId
    let name: String
    let description: String?
    let subscribers: String
    let thumbnailUrl: String
    
    var sections: [ArtistSection]
}

enum ArtistSectionType {
    case topSongs
    case albums
    case singles
    case similarArtists
    case videos
    case unknown
}

struct ArtistSection: Identifiable {
    let id = UUID()
    let type: ArtistSectionType
    let title: String
    let items: [ArtistItem]
    let browseId: String? // For "See All" endpoint
    let params: String? // For "See All" endpoint filters
}

struct ArtistItem: Identifiable, Hashable {
    let id: String // videoId or browseId
    let title: String
    let subtitle: String? // Artist name, year, etc.
    let thumbnailUrl: String
    let isExplicit: Bool
    
    // For songs
    let videoId: String?
    let playlistId: String?
    
    // For albums/artists
    let browseId: String?
}
