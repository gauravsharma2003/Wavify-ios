//
//  HomeView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import Observation

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    var audioPlayer: AudioPlayer
    @State var navigationManager: NavigationManager = .shared
    
    var body: some View {
        NavigationStack(path: $navigationManager.homePath) {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Quick Picks Section
                    if !viewModel.quickPicks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Quick Picks")
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(viewModel.quickPicks) { result in
                                        AlbumCard(
                                            title: result.name,
                                            subtitle: result.artist,
                                            imageUrl: result.thumbnailUrl
                                        ) {
                                            handleResultTap(result)
                                        }
                                        .frame(width: 150)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Featured Section
                    if !viewModel.featured.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Featured")
                            
                            ForEach(viewModel.featured) { result in
                                FeaturedCard(
                                    title: result.name,
                                    subtitle: result.artist,
                                    imageUrl: result.thumbnailUrl
                                ) {
                                    handleResultTap(result)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Trending Songs
                    if !viewModel.trending.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Trending")
                            
                            VStack(spacing: 0) {
                                ForEach(viewModel.trending) { result in
                                    SongRow(
                                        song: Song(from: result),
                                        onTap: { handleResultTap(result) }
                                    )
                                    
                                    if result.id != viewModel.trending.last?.id {
                                        Divider()
                                            .padding(.leading, 76)
                                            .opacity(0.3)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
                .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
            }
            .background(gradientBackground)
            .overlay(alignment: .top) {
                // Gradient blur at top
                LinearGradient(
                    stops: [
                        .init(color: Color(white: 0.06).opacity(0.95), location: 0),
                        .init(color: Color(white: 0.06).opacity(0.7), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.refresh()
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .artist(let id, let name, let thumbnail):
                    ArtistDetailView(
                        artistId: id,
                        initialName: name,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .album(let id, let name, let artist, let thumbnail):
                    AlbumDetailView(
                        albumId: id,
                        initialName: name,
                        initialArtist: artist,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .song(_):
                    EmptyView() // Songs usually processed by player, not navigation
                }
            }
        }
        .task {
            await viewModel.loadInitialContent()
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.horizontal)
    }
    
    private var gradientBackground: some View {
        Color(white: 0.06)
            .ignoresSafeArea()
    }
    
    private func handleResultTap(_ result: SearchResult) {
        if result.type == .song {
            Task {
                await audioPlayer.loadAndPlay(song: Song(from: result))
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
class HomeViewModel {
    var quickPicks: [SearchResult] = []
    var featured: [SearchResult] = []
    var trending: [SearchResult] = []
    var isLoading = false
    
    private let networkManager = NetworkManager.shared
    
    func loadInitialContent() async {
        guard quickPicks.isEmpty else { return }
        await loadContent()
    }
    
    func refresh() async {
        await loadContent()
    }
    
    private func loadContent() async {
        isLoading = true
        
        // Load trending content with different queries
        async let trendingResults = networkManager.search(query: "trending songs 2025 india")
        async let popResults = networkManager.search(query: "pop hits india")
        async let newResults = networkManager.search(query: "new music")
        
        do {
            let (trending, pop, newMusic) = try await (trendingResults, popResults, newResults)
            
            // Filter to only songs - extract results from tuple
            let trendingSongs = trending.results.filter { $0.type == .song }
            let popSongs = pop.results.filter { $0.type == .song }
            let newSongs = newMusic.results.filter { $0.type == .song }
            
            self.trending = Array(trendingSongs.prefix(10))
            self.quickPicks = Array(popSongs.prefix(8))
            self.featured = Array(newSongs.prefix(3))
        } catch {
            print("Failed to load content: \(error)")
        }
        
        isLoading = false
    }
}

#Preview {
    HomeView(audioPlayer: AudioPlayer.shared)
        .preferredColorScheme(.dark)
}
