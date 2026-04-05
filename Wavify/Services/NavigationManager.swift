//
//  NavigationManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI
import Observation
import SwiftData

enum NavigationDestination: Hashable {
    case artist(String, String, String) // id, name, thumbnail
    case album(String, String, String, String) // id, name, artist, thumbnail
    case playlist(String, String, String) // id, name, thumbnail
    case song(Song)
    case category(String, BrowseEndpoint) // title, endpoint
    case localPlaylist(PersistentIdentifier)
    case listenTogether
}

@Observable
class NavigationManager {
    static let shared = NavigationManager()
    
    // Set to true once splash icon animation lands on toolbar
    var splashIconLanded = false

    // Paths for each tab
    var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()
    
    var selectedTab = 0

    // MARK: - Player State

    /// Drives sheet visibility (background, controls fade). Fast on collapse.
    var playerExpansion: CGFloat = 0.0

    /// Drives art position/size morph. Slower on collapse — art "flies" independently.
    var artExpansion: CGFloat = 0.0

    /// Vertical drag offset of the full player sheet (0 = fully up, positive = dragged down)
    var sheetTranslation: CGFloat = 0

    var isPlayerExpanded: Bool { playerExpansion > 0.01 }

    var showNowPlaying: Bool {
        get { playerExpansion > 0 }
        set {
            playerExpansion = newValue ? 1.0 : 0.0
            artExpansion = newValue ? 1.0 : 0.0
        }
    }

    func expandPlayer(withVelocity: Bool = false) {
        sheetTranslation = 0
        let damping: CGFloat = withVelocity ? 0.8 : 1.0
        let response: CGFloat = withVelocity ? 0.4 : 0.5
        withAnimation(.spring(response: response, dampingFraction: damping)) {
            playerExpansion = 1.0
            artExpansion = 1.0
        }
    }

    func collapsePlayer() {
        // Sheet fades out fast
        withAnimation(.spring(response: 0.25, dampingFraction: 0.95)) {
            playerExpansion = 0.0
        }
        // Art flies to mini with a longer, smoother spring — visually separates from sheet
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            artExpansion = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.sheetTranslation = 0
        }
    }
    
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
        collapsePlayer()
        
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
        collapsePlayer()

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
        collapsePlayer()

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
        collapsePlayer()

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
    
    func navigateToListenTogether() {
        selectedTab = 2
        collapsePlayer()
        libraryPath.append(NavigationDestination.listenTogether)
    }

    func navigateToLocalPlaylist(_ playlist: LocalPlaylist) {
        // Switch to Library tab as local playlists live there
        selectedTab = 2
        collapsePlayer()
        
        let destination = NavigationDestination.localPlaylist(playlist.persistentModelID)
        libraryPath.append(destination)
    }
}
