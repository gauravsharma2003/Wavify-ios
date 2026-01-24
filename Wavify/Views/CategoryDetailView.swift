//
//  CategoryDetailView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let title: String
    let endpoint: BrowseEndpoint
    let namespace: Namespace.ID
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var page: HomePage?
    @State private var isLoading = true
    @State var navigationManager: NavigationManager = .shared
    
    // Force refresh to restore visibility after zoom transition (iOS 18 bug workaround)
    @State private var refreshId = UUID()
    
    private let networkManager = NetworkManager.shared
    
    var body: some View {
        ZStack {
            // Background
            Color(white: 0.05).ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let page = page {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(page.sections) { section in
                            HomeSectionView(section: section, namespace: namespace, refreshId: refreshId) { result in
                                handleResultTap(result)
                            }
                        }
                    }
                    .padding(.vertical)
                    .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
                }
            } else {
                Text("Failed to load content")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: NavigationDestination.self) { destination in
            switch destination {
            case .artist(let id, let name, let thumbnail):
                ArtistDetailView(
                    artistId: id,
                    initialName: name,
                    initialThumbnail: thumbnail,
                    audioPlayer: audioPlayer
                )
                .navigationTransition(.zoom(sourceID: id, in: namespace))
                .onDisappear {
                    NavigationManager.shared.recordClose(id: id)
                    refreshId = UUID() // Force refresh source images
                }
            case .album(let id, let name, let artist, let thumbnail):
                AlbumDetailView(
                    albumId: id,
                    initialName: name,
                    initialArtist: artist,
                    initialThumbnail: thumbnail,
                    audioPlayer: audioPlayer
                )
                .navigationTransition(.zoom(sourceID: id, in: namespace))
                .onDisappear {
                    NavigationManager.shared.recordClose(id: id)
                    refreshId = UUID() // Force refresh source images
                }
            case .song(_):
                EmptyView()
            case .playlist(let id, let name, let thumbnail):
                PlaylistDetailView(
                    playlistId: id,
                    initialName: name,
                    initialThumbnail: thumbnail,
                    audioPlayer: audioPlayer
                )
                .navigationTransition(.zoom(sourceID: id, in: namespace))
                .onDisappear {
                    NavigationManager.shared.recordClose(id: id)
                    refreshId = UUID() // Force refresh source images
                }
            case .category(let title, let endpoint):
                CategoryDetailView(
                    title: title,
                    endpoint: endpoint,
                    namespace: namespace,
                    audioPlayer: audioPlayer
                )
            case .localPlaylist(let pID):
                if let playlist = modelContext.model(for: pID) as? LocalPlaylist {
                    AlbumDetailView(
                        albumId: nil,
                        initialName: playlist.name,
                        initialArtist: "",
                        initialThumbnail: playlist.thumbnailUrl ?? "",
                        localPlaylist: playlist,
                        audioPlayer: audioPlayer
                    )
                } else {
                    ContentUnavailableView("Playlist Not Found", systemImage: "questionmark.folder")
                }
            }
        }
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        // Only load if content hasn't been loaded yet
        // This preserves the cache while view is in navigation stack
        guard page == nil else { return }
        
        isLoading = true
        do {
            page = try await networkManager.loadPage(endpoint: endpoint)
        } catch {
            Logger.networkError("Failed to load category", error: error)
        }
        isLoading = false
    }
    
    private func handleResultTap(_ result: SearchResult) {
        // Navigate using NavigationManager which routes to appropriate tab's stack
        navigationManager.handleNavigation(for: result, audioPlayer: audioPlayer)
    }
}

