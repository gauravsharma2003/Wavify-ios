//
//  NavigationManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI
import Observation

enum NavigationDestination: Hashable {
    case artist(String, String, String) // id, name, thumbnail
    case album(String, String, String, String) // id, name, artist, thumbnail
    case playlist(String, String, String) // id, name, thumbnail
    case song(Song)
    case category(String, BrowseEndpoint) // title, endpoint
}

@Observable
class NavigationManager {
    static let shared = NavigationManager()
    
    // Paths for each tab
    var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()
    
    var selectedTab = 0
    var showNowPlaying = false
    
    // Cooldown to prevent rapid re-navigation to same item (prevents zoom transition glitch)
    private var lastNavigatedId: String?
    private var lastNavigatedTime: Date?
    private let cooldownDuration: TimeInterval = 2.0
    
    /// Check if an item is in cooldown (was recently navigated away from)
    func isInCooldown(id: String) -> Bool {
        guard lastNavigatedId == id,
              let lastTime = lastNavigatedTime else { return false }
        return Date().timeIntervalSince(lastTime) < cooldownDuration
    }
    
    /// Record that a destination was closed
    func recordClose(id: String) {
        lastNavigatedId = id
        lastNavigatedTime = Date()
    }
    
    func navigateToArtist(id: String, name: String, thumbnail: String) {
        // Dismiss player if open
        showNowPlaying = false
        
        let destination = NavigationDestination.artist(id, name, thumbnail)
        
        // Push to active tab's stack
        switch selectedTab {
        case 0:
            homePath.append(destination)
        case 1:
            searchPath.append(destination)
        case 2:
            libraryPath.append(destination)
        default:
            homePath.append(destination)
        }
    }
    
    func navigateToAlbum(id: String, name: String, artist: String, thumbnail: String) {
        // Skip if in cooldown
        guard !isInCooldown(id: id) else { return }
        
        // Dismiss player if open
        showNowPlaying = false
        
        let destination = NavigationDestination.album(id, name, artist, thumbnail)
        
        // Push to active tab's stack
        switch selectedTab {
        case 0:
            homePath.append(destination)
        case 1:
            searchPath.append(destination)
        case 2:
            libraryPath.append(destination)
        default:
            homePath.append(destination)
        }
    }
    
    func navigateToPlaylist(id: String, name: String, thumbnail: String) {
        // Skip if in cooldown
        guard !isInCooldown(id: id) else { return }
        
        // Dismiss player if open
        showNowPlaying = false
        
        let destination = NavigationDestination.playlist(id, name, thumbnail)
        
        // Push to active tab's stack
        switch selectedTab {
        case 0:
            homePath.append(destination)
        case 1:
            searchPath.append(destination)
        case 2:
            libraryPath.append(destination)
        default:
            homePath.append(destination)
        }
        }

    
    func handleNavigation(for result: SearchResult, audioPlayer: AudioPlayer) {
        switch result.type {
        case .song, .video:
            Task {
                await audioPlayer.loadAndPlay(song: Song(from: result))
            }
        case .artist:
            if let artistId = result.artistId ?? (result.type == .artist ? result.id : nil) {
                 navigateToArtist(id: artistId, name: result.name, thumbnail: result.thumbnailUrl)
            } else {
                 navigateToArtist(id: result.id, name: result.name, thumbnail: result.thumbnailUrl)
            }
        case .album:
            navigateToAlbum(id: result.id, name: result.name, artist: result.artist, thumbnail: result.thumbnailUrl)
        case .playlist:
            navigateToPlaylist(id: result.id, name: result.name, thumbnail: result.thumbnailUrl)
        }
    }
    
    func navigateToCategory(title: String, endpoint: BrowseEndpoint) {
        // Dismiss player if open
        showNowPlaying = false
        
        let destination = NavigationDestination.category(title, endpoint)
        
        // Push to active tab's stack
        switch selectedTab {
        case 0:
            homePath.append(destination)
        case 1:
            searchPath.append(destination)
        case 2:
            libraryPath.append(destination)
        default:
            homePath.append(destination)
        }
    }
}
