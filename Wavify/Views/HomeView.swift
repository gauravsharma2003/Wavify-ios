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
                            // Chip Cloud (Fixed at top of scroll or pinned?)
                            // For now, inside scroll but could be pinned

                            // Your Favourites Section (2-column grid, shown first)
                            if viewModel.favouriteItems.count >= 2 {
                                YourFavouritesGridView(
                                    items: viewModel.favouriteItems,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    onItemTap: handleResultTap,
                                    onAddToPlaylist: handleAddToPlaylist,
                                    onToggleLike: handleToggleLike,
                                    onPlayNext: handlePlayNext,
                                    onAddToQueue: handleAddToQueue
                                )
                            }

                            // Chart Sections (No History - shown first)
                            if !viewModel.hasHistory {
                                // 1. Trending Songs
                                if !viewModel.trendingSongs.isEmpty {
                                    RecommendationsGridView(
                                        title: "Trending Songs",
                                        subtitle: "Popular right now",
                                        songs: viewModel.trendingSongs,
                                        likedSongIds: likedSongIds,
                                        queueSongIds: audioPlayer.userQueueIds,
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
                                        onSongTap: handleResultTap
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
                                        onSongTap: handleResultTap,
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
                                        onSongTap: handleResultTap
                                    )
                                }
                            }
                            
                            // You Might Like Section (4 rows, horizontal scroll)
                            if !viewModel.recommendedSongs.isEmpty {
                                RecommendationsGridView(
                                    title: "You might like",
                                    subtitle: "Based on your listening",
                                    songs: viewModel.recommendedSongs,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
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
                                    onSongTap: handleResultTap,
                                    onAddToPlaylist: handleAddToPlaylist,
                                    onToggleLike: handleToggleLike,
                                    onPlayNext: handlePlayNext,
                                    onAddToQueue: handleAddToQueue
                                )
                            }

                            
                            // Chart Sections (With History - shown after personalized content)
                            if viewModel.hasHistory {
                                // 1. Trending Songs
                                if !viewModel.trendingSongs.isEmpty {
                                    RecommendationsGridView(
                                        title: "Trending Songs",
                                        subtitle: "Popular right now",
                                        songs: viewModel.trendingSongs,
                                        likedSongIds: likedSongIds,
                                        queueSongIds: audioPlayer.userQueueIds,
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
                                        onSongTap: handleResultTap
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
                                        onSongTap: handleResultTap,
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
                                        onSongTap: handleResultTap
                                    )
                                }
                            }
                            
                            // Sections (Home Page from API)
                            if let sections = viewModel.homePage?.sections {
                                ForEach(sections) { section in
                                    HomeSectionView(section: section) { result in
                                        handleResultTap(result)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                        .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
                    }
                    .refreshable {
                        await viewModel.refresh(modelContext: modelContext)
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
                case .album(let id, let name, let artist, let thumbnail):
                    AlbumDetailView(
                        albumId: id,
                        initialName: name,
                        initialArtist: artist,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .song(_):
                    EmptyView()
                case .playlist(let id, let name, let thumbnail):
                    PlaylistDetailView(
                        playlistId: id,
                        initialName: name,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .category(let title, let endpoint):
                    CategoryDetailView(
                        title: title,
                        endpoint: endpoint,
                        audioPlayer: audioPlayer
                    )
                }
            }
        }
        .task {
            // Start loading home content first
            await viewModel.loadInitialContent(modelContext: modelContext)
        }
        .task {
            // Load liked status separately with yield to not block UI
            await Task.yield()
            loadLikedStatusSync()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
        .onReceive(NotificationCenter.default.publisher(for: .songDidStartPlaying)) { notification in
            if let song = notification.userInfo?["song"] as? Song {
                // Track song play count
                PlayCountManager.shared.incrementPlayCount(for: song, in: modelContext)
                
                // Track artist play (if artistId available)
                if let artistId = song.artistId, !artistId.isEmpty {
                    FavouritesManager.shared.trackArtistPlay(
                        artistId: artistId,
                        name: song.artist,
                        thumbnailUrl: song.thumbnailUrl,
                        in: modelContext
                    )
                }
                
                // Track album play (if albumId available)
                if let albumId = song.albumId, !albumId.isEmpty {
                    FavouritesManager.shared.trackAlbumPlay(
                        albumId: albumId,
                        title: "Album",  // Album title not always available from song
                        artist: song.artist,
                        thumbnailUrl: song.thumbnailUrl,
                        in: modelContext
                    )
                }
                
                // Prefetch new recommendations in background for next launch
                Task {
                    await RecommendationsManager.shared.prefetchRecommendationsInBackground(in: modelContext)
                }
            }
        }
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: "1A1A1A"),
                Color(hex: "1B1B1B")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
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
        toggleLikeSong(Song(from: result))
    }
    
    private func handlePlayNext(_ result: SearchResult) {
        audioPlayer.playNextSong(Song(from: result))
    }
    
    private func handleAddToQueue(_ result: SearchResult) {
        _ = audioPlayer.addToQueue(Song(from: result))
    }
    
    // MARK: - Like Management
    
    private func loadLikedStatusSync() {
        // Runs on MainActor after yield - stays on main thread for SwiftData safety
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.isLiked == true }
        )
        if let likedSongs = try? modelContext.fetch(descriptor) {
            likedSongIds = Set(likedSongs.map { $0.videoId })
        }
    }
    
    private func toggleLikeSong(_ song: Song) {
        let isNowLiked = PlaylistManager.shared.toggleLike(for: song, in: modelContext)
        if isNowLiked {
            likedSongIds.insert(song.videoId)
        } else {
            likedSongIds.remove(song.videoId)
        }
    }
}

// MARK: - Extensions

extension Color {
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

// MARK: - Subviews

// MARK: - Keep Listening Grid (2 rows, horizontal scroll)
struct KeepListeningGridView: View {
    var title: String = "Keep Listening"
    let songs: [SearchResult]
    let onSongTap: (SearchResult) -> Void
    
    // Grid configuration: 2 rows
    private let rowCount = 2
    private let cardSize: CGFloat = 110  // Slightly bigger than list rows
    private let columnSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 12
    
    // Split songs into columns for vertical layout
    private var columns: [[SearchResult]] {
        var result: [[SearchResult]] = []
        let columnCount = (songs.count + rowCount - 1) / rowCount
        
        for colIndex in 0..<columnCount {
            var column: [SearchResult] = []
            for rowIndex in 0..<rowCount {
                let songIndex = colIndex * rowCount + rowIndex
                if songIndex < songs.count {
                    column.append(songs[songIndex])
                }
            }
            result.append(column)
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(title)
                .font(.title2)
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            // Horizontal scrolling grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(columns.indices, id: \.self) { columnIndex in
                        VStack(spacing: rowSpacing) {
                            ForEach(columns[columnIndex], id: \.id) { song in
                                KeepListeningCard(item: song) {
                                    onSongTap(song)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Keep Listening Card (Medium size)
struct KeepListeningCard: View {
    let item: SearchResult
    let onTap: () -> Void
    
    private var thumbnailUrl: String {
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
            p = p.replacingOccurrences(of: "w120-h120", with: "w360-h360")
        } else if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w360-h360")
        } else if p.contains("s120") {
            p = p.replacingOccurrences(of: "s120", with: "s360")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Thumbnail - square, medium size
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Song info
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 220)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Your Favourites Grid (2-column vertical layout, max 8 items)
struct YourFavouritesGridView: View {
    let items: [SearchResult]
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    let onItemTap: (SearchResult) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    // Always show even number of items (4, 6, or 8) for balanced columns
    private var displayItems: [SearchResult] {
        let maxItems = min(items.count, 8)
        // Round down to even number
        let evenCount = maxItems - (maxItems % 2)
        return Array(items.prefix(evenCount))
    }
    
    // Split into 2 columns (left: 0,2,4,6 right: 1,3,5,7)
    private var leftColumnItems: [SearchResult] {
        displayItems.enumerated().compactMap { index, item in
            index % 2 == 0 ? item : nil
        }
    }
    
    private var rightColumnItems: [SearchResult] {
        displayItems.enumerated().compactMap { index, item in
            index % 2 == 1 ? item : nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Your Favourites")
                .font(.title2)
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            // 2-column vertical grid
            HStack(alignment: .top, spacing: 12) {
                // Left column
                VStack(spacing: 10) {
                    ForEach(leftColumnItems, id: \.id) { item in
                        FavouriteBlockCard(
                            item: item,
                            isLiked: likedSongIds.contains(item.id),
                            isInQueue: queueSongIds.contains(item.id),
                            onTap: { onItemTap(item) },
                            onAddToPlaylist: { onAddToPlaylist(item) },
                            onToggleLike: { onToggleLike(item) },
                            onPlayNext: { onPlayNext(item) },
                            onAddToQueue: { onAddToQueue(item) }
                        )
                    }
                }
                
                // Right column
                VStack(spacing: 10) {
                    ForEach(rightColumnItems, id: \.id) { item in
                        FavouriteBlockCard(
                            item: item,
                            isLiked: likedSongIds.contains(item.id),
                            isInQueue: queueSongIds.contains(item.id),
                            onTap: { onItemTap(item) },
                            onAddToPlaylist: { onAddToPlaylist(item) },
                            onToggleLike: { onToggleLike(item) },
                            onPlayNext: { onPlayNext(item) },
                            onAddToQueue: { onAddToQueue(item) }
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Favourite Block Card (Light grey block with image left, name right)
struct FavouriteBlockCard: View {
    let item: SearchResult
    let isLiked: Bool
    let isInQueue: Bool
    let onTap: () -> Void
    var onAddToPlaylist: (() -> Void)? = nil
    var onToggleLike: (() -> Void)? = nil
    var onPlayNext: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    
    private var thumbnailUrl: String {
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
            p = p.replacingOccurrences(of: "w120-h120", with: "w226-h226")
        } else if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w226-h226")
        } else if p.contains("s120") {
            p = p.replacingOccurrences(of: "s120", with: "s226")
        }
        return p
    }
    
    private var isArtist: Bool {
        item.type == .artist
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Thumbnail on the left - circular for artists
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.4)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 5)))
                
                // Name on the right, left-aligned
                Text(item.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.22))
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isArtist && item.type == .song {
                Button {
                    onAddToPlaylist?()
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
                
                Button {
                    onToggleLike?()
                } label: {
                    Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
                }
                
                Button {
                    onPlayNext?()
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                
                Button {
                    onAddToQueue?()
                } label: {
                    Label(isInQueue ? "In Queue" : "Add to Queue", systemImage: "text.append")
                }
            }
        }
    }
}

// SwiftUI helper for conditional shapes
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = { shape.path(in: $0) }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

// MARK: - Recommendations Grid (4 rows, horizontal scroll)
struct RecommendationsGridView: View {
    var title: String = "You might like"
    var subtitle: String = "Based on your listening"
    let songs: [SearchResult]
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    let onSongTap: (SearchResult) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    // Grid configuration: 4 rows
    private let rowCount = 4
    private let columnWidth: CGFloat = 280
    private let columnSpacing: CGFloat = 16
    private let rowSpacing: CGFloat = 8
    
    // Split songs into columns for vertical layout
    private var columns: [[SearchResult]] {
        var result: [[SearchResult]] = []
        let columnCount = (songs.count + rowCount - 1) / rowCount
        
        for colIndex in 0..<columnCount {
            var column: [SearchResult] = []
            for rowIndex in 0..<rowCount {
                let songIndex = colIndex * rowCount + rowIndex
                if songIndex < songs.count {
                    column.append(songs[songIndex])
                }
            }
            result.append(column)
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Horizontal scrolling list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(columns.indices, id: \.self) { columnIndex in
                        VStack(spacing: rowSpacing) {
                            ForEach(columns[columnIndex], id: \.id) { song in
                                RecommendationListRow(
                                    item: song,
                                    isLiked: likedSongIds.contains(song.id),
                                    isInQueue: queueSongIds.contains(song.id),
                                    onTap: {
                                        onSongTap(song)
                                    },
                                    onAddToPlaylist: {
                                        onAddToPlaylist(song)
                                    },
                                    onToggleLike: {
                                        onToggleLike(song)
                                    },
                                    onPlayNext: {
                                        onPlayNext(song)
                                    },
                                    onAddToQueue: {
                                        onAddToQueue(song)
                                    }
                                )
                            }
                        }
                        .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Recommendation List Row (Compact)
struct RecommendationListRow: View {
    let item: SearchResult
    let isLiked: Bool
    let isInQueue: Bool
    let onTap: () -> Void
    let onAddToPlaylist: () -> Void
    let onToggleLike: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    
    private var thumbnailUrl: String {
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
            p = p.replacingOccurrences(of: "w120-h120", with: "w226-h226")
        } else if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w226-h226")
        } else if p.contains("s120") {
            p = p.replacingOccurrences(of: "s120", with: "s226")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Duration (if available from year field, otherwise show placeholder)
                if !item.year.isEmpty {
                    Text(item.year)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                
                SongOptionsMenu(
                    isLiked: isLiked,
                    isInQueue: isInQueue,
                    onAddToPlaylist: onAddToPlaylist,
                    onToggleLike: onToggleLike,
                    onPlayNext: onPlayNext,
                    onAddToQueue: onAddToQueue
                )
            }
            .padding(.vertical, 4)
        }
    }
}

struct ChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color(white: 0.15))
                .foregroundColor(isSelected ? .black : .white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

struct HomeSectionView: View {
    let section: HomeSection
    let onResultTap: (SearchResult) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                if let strapline = section.strapline {
                    Text(strapline)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                }
                Text(section.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(section.items) { item in
                        ItemCard(item: item) {
                            onResultTap(item)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ItemCard: View {
    let item: SearchResult
    let onTap: () -> Void
    
    // Helper to get high quality image
    private var highQualityThumbnailUrl: String {
        // Replace resolution specs like "w120-h120" with larger ones if present
        // Or assume URL can be modified.
        // YouTube Music URLs often have regex like `s120-c-...` or `w120-h120-...`
        // We'll replace typical size markers with larger ones
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
             p = p.replacingOccurrences(of: "w120-h120", with: "w540-h540")
        } else if p.contains("w60-h60") {
             p = p.replacingOccurrences(of: "w60-h60", with: "w540-h540")
        } else if p.contains("s120") {
             p = p.replacingOccurrences(of: "s120", with: "s540")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                CachedAsyncImagePhase(url: URL(string: highQualityThumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Color.gray.opacity(0.3)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 160, height: 160) // Slightly larger for better look
                .clipShape(RoundedRectangle(cornerRadius: 12)) // Softer corners
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4) // Drop shadow for depth
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: 160)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
class HomeViewModel {
    var homePage: HomePage?
    var selectedChipId: String?
    var isLoading = false
    var recommendedSongs: [SearchResult] = []
    var keepListeningSongs: [SearchResult] = []
    var favouriteItems: [SearchResult] = []
    var likedBasedRecommendations: [SearchResult] = []
    
    // Chart sections (computed from ChartsManager cache)
    var trendingSongs: [SearchResult] { chartsManager.trendingSongs }
    var topSongs: [SearchResult] { chartsManager.topSongs }
    var global100Songs: [SearchResult] { chartsManager.global100Songs }
    var us100Songs: [SearchResult] { chartsManager.us100Songs }
    var hasHistory: Bool = false
    
    private let networkManager = NetworkManager.shared
    private let recommendationsManager = RecommendationsManager.shared
    private let keepListeningManager = KeepListeningManager.shared
    private let favouritesManager = FavouritesManager.shared
    private let chartsManager = ChartsManager.shared
    private let likedBasedRecommendationsManager = LikedBasedRecommendationsManager.shared
    
    func loadInitialContent(modelContext: ModelContext) async {
        // Always show loading on fresh start
        isLoading = true
        
        // 1. Load cached data instantly
        loadCachedRecommendations()
        loadCachedKeepListening()
        loadCachedFavourites()
        loadCachedLikedBasedRecommendations()
        
        hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)
        
        // 2. Load charts and home data
        if !chartsManager.hasCachedData {
            await chartsManager.refreshInBackground()
        }
        
        await loadHome()
        
        // 3. Wait for initial images to start loading
        // Longer delay (3s) for first launch to prevent image decoding freeze
        // Shorter delay (1.5s) for subsequent launches for better UX
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let delay: UInt64 = hasLaunched ? 1_500_000_000 : 3_000_000_000
        try? await Task.sleep(nanoseconds: delay)
        
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        
        isLoading = false
        
        // 3. Refresh Keep Listening and Favourites AFTER UI is fully interactive
        // Delay by 1 second to ensure smooth scrolling first
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            guard let self = self else { return }
            
            if hasHistory {
                self.keepListeningSongs = self.keepListeningManager.refreshSongs(in: modelContext)
                
                // Yield between operations to keep UI responsive
                await Task.yield()
                
                self.favouriteItems = self.favouritesManager.refreshFavourites(in: modelContext)
                
                await Task.yield()
                
                await self.recommendationsManager.prefetchRecommendationsInBackground(in: modelContext)
                
                await Task.yield()
                
                await self.likedBasedRecommendationsManager.prefetchRecommendationsInBackground(in: modelContext)
            }
            
            // Background refresh charts if needed (won't block UI)
            if chartsManager.needsRefresh {
                await chartsManager.refreshInBackground()
            }
        }
    }
    
    func refresh(modelContext: ModelContext) async {
        if let selectedChipId = selectedChipId,
           let chip = homePage?.chips.first(where: { $0.id == selectedChipId }) {
            await selectChip(chip)
        } else {
            await loadHome()
        }
        
        let hasHistory = PlayCountManager.shared.hasPlayHistory(in: modelContext)
        if hasHistory {
            keepListeningSongs = keepListeningManager.refreshSongs(in: modelContext)
            favouriteItems = favouritesManager.refreshFavourites(in: modelContext)
            recommendedSongs = await recommendationsManager.refreshRecommendations(in: modelContext)
            likedBasedRecommendations = await likedBasedRecommendationsManager.refreshRecommendations(in: modelContext)
        }
        
        // Force refresh charts on pull-to-refresh
        await chartsManager.forceRefresh()
    }
    
    func loadCachedRecommendations() {
        recommendedSongs = recommendationsManager.recommendations
    }
    
    func loadCachedKeepListening() {
        keepListeningSongs = keepListeningManager.songs
    }
    
    func loadCachedFavourites() {
        favouriteItems = favouritesManager.favourites
    }
    
    func loadCachedLikedBasedRecommendations() {
        likedBasedRecommendations = likedBasedRecommendationsManager.recommendations
    }
    
    func loadHome() async {
        // Only set loading if we aren't showing chart content already
        if trendingSongs.isEmpty {
             isLoading = true
        }
        
        do {
            let home = try await networkManager.getHome()
            self.homePage = home
            self.selectedChipId = nil
            isLoading = false
        } catch {
            print("Failed to load home: \(error)")
            isLoading = false
        }
    }
    
    func selectChip(_ chip: Chip) async {
        if selectedChipId == chip.id {
            await loadHome()
            return
        }
        
        isLoading = true
        selectedChipId = chip.id
        
        do {
            self.homePage = try await networkManager.loadPage(endpoint: chip.endpoint)
        } catch {
            print("Failed to load chip: \(error)")
        }
        isLoading = false
    }
}
