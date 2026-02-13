//
//  HomeView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import SwiftData
import Observation

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    var audioPlayer: AudioPlayer
    @State var navigationManager: NavigationManager = .shared
    @Environment(\.modelContext) private var modelContext
    
    // Add to playlist state
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongIds: Set<String> = []
    
    // Hero animation namespace for chart cards
    @Namespace private var chartHeroAnimation
    
    // Force refresh to restore visibility after zoom transition (iOS 18 bug workaround)
    @State private var heroRefreshId = UUID()

    // Scroll reset ID - changes on refresh to reset all horizontal scroll positions
    @State private var scrollResetId = UUID()
    
    var body: some View {
        NavigationStack(path: $navigationManager.homePath) {
            ZStack {
                // Background
                gradientBackground
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Your Favourites Section (2-column grid, shown first)
                            if viewModel.favouriteItems.count >= 2 {
                                YourFavouritesGridView(
                                    items: viewModel.favouriteItems,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    namespace: chartHeroAnimation,
                                    refreshId: heroRefreshId,
                                    onItemTap: handleResultTap,
                                    onAddToPlaylist: handleAddToPlaylist,
                                    onToggleLike: handleToggleLike,
                                    onPlayNext: handlePlayNext,
                                    onAddToQueue: handleAddToQueue
                                )
                            }

                            // Chart Sections (No History - shown first)
                            if !viewModel.hasHistory {
                                chartSections
                            }
                            
                            // You Might Like Section (4 rows, horizontal scroll)
                            if !viewModel.recommendedSongs.isEmpty {
                                RecommendationsGridView(
                                    title: "You might like",
                                    subtitle: "Based on your listening",
                                    songs: viewModel.recommendedSongs,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    scrollResetId: scrollResetId,
                                    onSongTap: handleResultTap,
                                    onAddToPlaylist: handleAddToPlaylist,
                                    onToggleLike: handleToggleLike,
                                    onPlayNext: handlePlayNext,
                                    onAddToQueue: handleAddToQueue
                                )
                            }
                            
                            // Keep Listening Section (2 rows, horizontal scroll)
                            if viewModel.keepListeningSongs.count >= 4 {
                                KeepListeningGridView(
                                    title: "Keep Listening",
                                    songs: viewModel.keepListeningSongs,
                                    scrollResetId: scrollResetId,
                                    onSongTap: handleResultTap
                                )
                            }
                            
                            // Based on Your Likes Section (4 rows, horizontal scroll)
                            if !viewModel.likedBasedRecommendations.isEmpty {
                                RecommendationsGridView(
                                    title: "Based on your likes",
                                    subtitle: "Songs you might enjoy",
                                    songs: viewModel.likedBasedRecommendations,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    scrollResetId: scrollResetId,
                                    onSongTap: handleResultTap,
                                    onAddToPlaylist: handleAddToPlaylist,
                                    onToggleLike: handleToggleLike,
                                    onPlayNext: handlePlayNext,
                                    onAddToQueue: handleAddToQueue
                                )
                            }
                            
                            // Random Category Playlists (for users with history - before trending)
                            if viewModel.hasHistory && !viewModel.randomCategoryPlaylists.isEmpty {
                                RandomCategoryCarouselView(
                                    categoryName: viewModel.randomCategoryName,
                                    playlists: viewModel.randomCategoryPlaylists,
                                    audioPlayer: audioPlayer,
                                    namespace: chartHeroAnimation,
                                    scrollResetId: scrollResetId,
                                    onPlaylistTap: { playlist in
                                        if playlist.isAlbum {
                                            navigationManager.homePath.append(
                                                NavigationDestination.album(playlist.playlistId, playlist.name, playlist.subtitle ?? "", playlist.thumbnailUrl)
                                            )
                                        } else {
                                            navigationManager.homePath.append(
                                                NavigationDestination.playlist(playlist.playlistId, playlist.name, playlist.thumbnailUrl)
                                            )
                                        }
                                    }
                                )
                            }

                            // Chart Sections (With History - shown after personalized content)
                            if viewModel.hasHistory {
                                chartSections
                            }
                            
                            // Sections (Home Page from API)
                            if let sections = viewModel.homePage?.sections {
                                ForEach(sections) { section in
                                    HomeSectionView(section: section, namespace: chartHeroAnimation, refreshId: heroRefreshId) { result in
                                        handleResultTap(result)
                                    }
                                }
                            }
                            
                            // Trending in Shorts Section (Last in order)
                            if !viewModel.shortsSongs.isEmpty {
                                ShortsCarouselView(
                                    title: "Trending in Shorts",
                                    subtitle: "Popular on YouTube Shorts",
                                    songs: viewModel.shortsSongs,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    scrollResetId: scrollResetId,
                                    onSongTap: handleResultTap,
                                    onAddToPlaylist: handleAddToPlaylist,
                                    onToggleLike: handleToggleLike,
                                    onPlayNext: handlePlayNext,
                                    onAddToQueue: handleAddToQueue
                                )
                            }
                        }
                        .padding(.vertical)
                        .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
                    }
                    .refreshable {
                        await viewModel.refresh(modelContext: modelContext)
                        scrollResetId = UUID() // Reset all scroll positions
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "music.note.house.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
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
                    .navigationTransition(.zoom(sourceID: id, in: chartHeroAnimation))
                    .onDisappear {
                        NavigationManager.shared.recordClose(id: id)
                        heroRefreshId = UUID() // Force refresh source images
                    }
                case .album(let id, let name, let artist, let thumbnail):
                    AlbumDetailView(
                        albumId: id,
                        initialName: name,
                        initialArtist: artist,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                    .navigationTransition(.zoom(sourceID: id, in: chartHeroAnimation))
                    .onDisappear {
                        NavigationManager.shared.recordClose(id: id)
                        heroRefreshId = UUID() // Force refresh source images
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
                    .navigationTransition(.zoom(sourceID: id, in: chartHeroAnimation))
                    .onDisappear {
                        NavigationManager.shared.recordClose(id: id)
                        heroRefreshId = UUID() // Force refresh source images
                    }
                case .category(let title, let endpoint):
                    CategoryDetailView(
                        title: title,
                        endpoint: endpoint,
                        namespace: chartHeroAnimation,
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
                case .listenTogether:
                    ListenTogetherView()
                }
            }
        }
        .task {
            // Start loading home content first
            await viewModel.loadInitialContent(modelContext: modelContext)
        }
        .task {
            // Load liked status on background context
            await loadLikedStatus()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
        .onReceive(NotificationCenter.default.publisher(for: .songDidStartPlaying)) { notification in
            if let song = notification.userInfo?["song"] as? Song {
                // Track play counts on background context to keep UI responsive
                Task {
                    // Track song play count
                    await BackgroundDataManager.shared.incrementPlayCount(for: song)

                    // Track artist play (if artistId available)
                    if let artistId = song.artistId, !artistId.isEmpty {
                        await BackgroundDataManager.shared.trackArtistPlay(
                            artistId: artistId,
                            name: song.artist,
                            thumbnailUrl: song.thumbnailUrl
                        )
                    }

                    // Track album play (if albumId available)
                    if let albumId = song.albumId, !albumId.isEmpty {
                        await BackgroundDataManager.shared.trackAlbumPlay(
                            albumId: albumId,
                            title: "Album",
                            artist: song.artist,
                            thumbnailUrl: song.thumbnailUrl
                        )
                    }

                    // Update hasHistory and load recommendations if first song played
                    await viewModel.onSongPlayed(song: song, modelContext: modelContext)
                }

                // Prefetch new recommendations in background for next launch
                Task {
                    await RecommendationsManager.shared.prefetchRecommendationsInBackground(in: modelContext)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var gradientBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color.brandGradientTop, location: 0),
                .init(color: Color.brandBackground, location: 0.45)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var chartSections: some View {
        // 1. Trending Songs
        if !viewModel.trendingSongs.isEmpty {
            RecommendationsGridView(
                title: "Trending Songs",
                subtitle: "Popular right now",
                songs: viewModel.trendingSongs,
                likedSongIds: likedSongIds,
                queueSongIds: audioPlayer.userQueueIds,
                scrollResetId: scrollResetId,
                onSongTap: handleResultTap,
                onAddToPlaylist: handleAddToPlaylist,
                onToggleLike: handleToggleLike,
                onPlayNext: handlePlayNext,
                onAddToQueue: handleAddToQueue
            )
        }
        
        // 2. Top Songs
        if !viewModel.topSongs.isEmpty {
            KeepListeningGridView(
                title: "Top Songs",
                songs: viewModel.topSongs,
                scrollResetId: scrollResetId,
                onSongTap: handleResultTap
            )
        }
        
        // Language Charts Carousel (for users WITH history - between trending and global)
        if viewModel.hasHistory && !viewModel.languageCharts.isEmpty {
            LanguageChartsCarouselView(
                charts: viewModel.languageCharts,
                audioPlayer: audioPlayer,
                likedSongIds: likedSongIds,
                queueSongIds: audioPlayer.userQueueIds,
                namespace: chartHeroAnimation,
                scrollResetId: scrollResetId,
                onPlaylistTap: { chart in
                    guard !navigationManager.isInCooldown(id: chart.playlistId) else { return }
                    navigationManager.homePath.append(
                        NavigationDestination.playlist(chart.playlistId, chart.displayName, chart.thumbnailUrl)
                    )
                },
                onAddToPlaylist: handleAddToPlaylist,
                onToggleLike: handleToggleLike,
                onPlayNext: handlePlayNext,
                onAddToQueue: handleAddToQueue
            )
        }
        
        // Random Category Playlists (for users WITHOUT history - between trending and global)
        if !viewModel.hasHistory && !viewModel.randomCategoryPlaylists.isEmpty {
            RandomCategoryCarouselView(
                categoryName: viewModel.randomCategoryName,
                playlists: viewModel.randomCategoryPlaylists,
                audioPlayer: audioPlayer,
                namespace: chartHeroAnimation,
                scrollResetId: scrollResetId,
                onPlaylistTap: { playlist in
                    guard !navigationManager.isInCooldown(id: playlist.playlistId) else { return }
                    if playlist.isAlbum {
                        navigationManager.homePath.append(
                            NavigationDestination.album(playlist.playlistId, playlist.name, playlist.subtitle ?? "", playlist.thumbnailUrl)
                        )
                    } else {
                        navigationManager.homePath.append(
                            NavigationDestination.playlist(playlist.playlistId, playlist.name, playlist.thumbnailUrl)
                        )
                    }
                }
            )
        }
        
        // 3. Global Top 100
        if !viewModel.global100Songs.isEmpty {
            RecommendationsGridView(
                title: "Global Top 100",
                subtitle: "Worldwide hits",
                songs: viewModel.global100Songs,
                likedSongIds: likedSongIds,
                queueSongIds: audioPlayer.userQueueIds,
                scrollResetId: scrollResetId,
                onSongTap: handleResultTap,
                onAddToPlaylist: handleAddToPlaylist,
                onToggleLike: handleToggleLike,
                onPlayNext: handlePlayNext,
                onAddToQueue: handleAddToQueue
            )
        }
        
        // Language Charts Carousel (for new users - after Global Top 100)
        if !viewModel.hasHistory && !viewModel.languageCharts.isEmpty {
            LanguageChartsCarouselView(
                charts: viewModel.languageCharts,
                audioPlayer: audioPlayer,
                likedSongIds: likedSongIds,
                queueSongIds: audioPlayer.userQueueIds,
                namespace: chartHeroAnimation,
                scrollResetId: scrollResetId,
                onPlaylistTap: { chart in
                    guard !navigationManager.isInCooldown(id: chart.playlistId) else { return }
                    navigationManager.homePath.append(
                        NavigationDestination.playlist(chart.playlistId, chart.displayName, chart.thumbnailUrl)
                    )
                },
                onAddToPlaylist: handleAddToPlaylist,
                onToggleLike: handleToggleLike,
                onPlayNext: handlePlayNext,
                onAddToQueue: handleAddToQueue
            )
        }
        
        // 4. US Top 100
        if !viewModel.us100Songs.isEmpty {
            KeepListeningGridView(
                title: "US Top 100",
                songs: viewModel.us100Songs,
                scrollResetId: scrollResetId,
                onSongTap: handleResultTap
            )
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleResultTap(_ result: SearchResult) {
        if result.type == .song {
            Task {
                await audioPlayer.loadAndPlay(song: Song(from: result))
            }
        } else if result.type == .album {
            navigationManager.homePath.append(NavigationDestination.album(result.id, result.name, result.artist, result.thumbnailUrl))
        } else if result.type == .artist {
            navigationManager.homePath.append(NavigationDestination.artist(result.id, result.name, result.thumbnailUrl))
        } else if result.type == .playlist {
            navigationManager.homePath.append(NavigationDestination.playlist(result.id, result.name, result.thumbnailUrl))
        }
    }
    
    private func handleAddToPlaylist(_ result: SearchResult) {
        selectedSongForPlaylist = Song(from: result)
    }
    
    private func handleToggleLike(_ result: SearchResult) {
        Task {
            await toggleLikeSong(Song(from: result))
        }
    }
    
    private func handlePlayNext(_ result: SearchResult) {
        audioPlayer.playNextSong(Song(from: result))
    }
    
    private func handleAddToQueue(_ result: SearchResult) {
        _ = audioPlayer.addToQueue(Song(from: result))
    }
    
    // MARK: - Like Management
    
    private func loadLikedStatus() async {
        let likedIds = await BackgroundDataManager.shared.getLikedSongIds()
        likedSongIds = likedIds
    }
    
    private func toggleLikeSong(_ song: Song) async {
        let isNowLiked = await BackgroundDataManager.shared.toggleLike(for: song)
        if isNowLiked {
            likedSongIds.insert(song.videoId)
        } else {
            likedSongIds.remove(song.videoId)
        }
    }
}

// MARK: - Extensions

extension Color {
    static let brandGradientTop = Color(red: 0.176, green: 0.106, blue: 0.306)  // Purple #2D1B4E
    static let brandBackground = Color(red: 0.10, green: 0.10, blue: 0.10)  // #1A1A1A

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
