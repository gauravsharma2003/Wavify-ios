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
                
                if viewModel.isLoading && viewModel.homePage == nil {
                    ProgressView()
                        .tint(.white)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Chip Cloud (Fixed at top of scroll or pinned?)
                            // For now, inside scroll but could be pinned

                            
                            // You Might Like Section (4 rows, horizontal scroll)
                            if !viewModel.recommendedSongs.isEmpty {
                                RecommendationsGridView(
                                    songs: viewModel.recommendedSongs,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    onSongTap: { result in
                                        handleResultTap(result)
                                    },
                                    onAddToPlaylist: { result in
                                        selectedSongForPlaylist = Song(from: result)
                                    },
                                    onToggleLike: { result in
                                        toggleLikeSong(Song(from: result))
                                    },
                                    onPlayNext: { result in
                                        audioPlayer.playNextSong(Song(from: result))
                                    },
                                    onAddToQueue: { result in
                                        _ = audioPlayer.addToQueue(Song(from: result))
                                    }
                                )
                            }
                            
                            // Keep Listening Section (2 rows, horizontal scroll)
                            if viewModel.keepListeningSongs.count >= 4 {
                                KeepListeningGridView(
                                    songs: viewModel.keepListeningSongs,
                                    onSongTap: { result in
                                        handleResultTap(result)
                                    }
                                )
                            }
                            
                            // Your Favourites Section (2 rows, large cards)
                            if viewModel.favouriteItems.count >= 4 {
                                YourFavouritesGridView(
                                    items: viewModel.favouriteItems,
                                    likedSongIds: likedSongIds,
                                    queueSongIds: audioPlayer.userQueueIds,
                                    onItemTap: { result in
                                        handleResultTap(result)
                                    },
                                    onAddToPlaylist: { result in
                                        selectedSongForPlaylist = Song(from: result)
                                    },
                                    onToggleLike: { result in
                                        toggleLikeSong(Song(from: result))
                                    },
                                    onPlayNext: { result in
                                        audioPlayer.playNextSong(Song(from: result))
                                    },
                                    onAddToQueue: { result in
                                        _ = audioPlayer.addToQueue(Song(from: result))
                                    }
                                )
                            }
                            
                            // Sections
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
            await viewModel.loadInitialContent(modelContext: modelContext)
            loadLikedStatus()
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
            colors: [Color(hex: "1a1a1a"), .black],
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
    
    // MARK: - Like Management
    
    private func loadLikedStatus() {
        // We can't easily check all recommended songs at once efficiently without a batch query
        // But for now we can rely on cached liked status or check when rendering
        // A better approach for HomeView is to load all liked song IDs into a set
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
            Text("Keep Listening")
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

// MARK: - Your Favourites Grid (2 rows, large cards like Quick Picks)
struct YourFavouritesGridView: View {
    let items: [SearchResult]
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    let onItemTap: (SearchResult) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    // Grid configuration: 2 rows with larger cards
    private let rowCount = 2
    private let cardWidth: CGFloat = 180
    private let columnSpacing: CGFloat = 14
    private let rowSpacing: CGFloat = 14
    
    // Split items into columns for vertical layout
    private var columns: [[SearchResult]] {
        var result: [[SearchResult]] = []
        let columnCount = (items.count + rowCount - 1) / rowCount
        
        for colIndex in 0..<columnCount {
            var column: [SearchResult] = []
            for rowIndex in 0..<rowCount {
                let itemIndex = colIndex * rowCount + rowIndex
                if itemIndex < items.count {
                    column.append(items[itemIndex])
                }
            }
            result.append(column)
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Your Favourites")
                .font(.title2)
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            // Horizontal scrolling grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(columns.indices, id: \.self) { columnIndex in
                        VStack(spacing: rowSpacing) {
                            ForEach(columns[columnIndex], id: \.id) { item in
                                FavouriteCard(
                                    item: item,
                                    isLiked: likedSongIds.contains(item.id),
                                    isInQueue: queueSongIds.contains(item.id),
                                    onTap: {
                                        onItemTap(item)
                                    },
                                    onAddToPlaylist: {
                                        onAddToPlaylist(item)
                                    },
                                    onToggleLike: {
                                        onToggleLike(item)
                                    },
                                    onPlayNext: {
                                        onPlayNext(item)
                                    },
                                    onAddToQueue: {
                                        onAddToQueue(item)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Favourite Card (Large, like Quick Picks)
struct FavouriteCard: View {
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
            p = p.replacingOccurrences(of: "w120-h120", with: "w540-h540")
        } else if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w540-h540")
        } else if p.contains("s120") {
            p = p.replacingOccurrences(of: "s120", with: "s540")
        }
        return p
    }
    
    private var isArtist: Bool {
        item.type == .artist
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail - larger size, circular for artists
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 150, height: 150)
                .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if item.type == .album {
                        Text("Album")
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    } else if !item.artist.isEmpty && !isArtist {
                        Text(item.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    } else {
                        Text(isArtist ? "Artist" : "Song")
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 150)
            .overlay(alignment: .topTrailing) {
                if !isArtist && item.type == .song {
                    SongOptionsMenu(
                        isLiked: isLiked,
                        isInQueue: isInQueue,
                        onAddToPlaylist: { onAddToPlaylist?() },
                        onToggleLike: { onToggleLike?() },
                        onPlayNext: { onPlayNext?() },
                        onAddToQueue: { onAddToQueue?() }
                    )
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.5))
                    )
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
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
                Text("Based on your listening")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                Text("You might like")
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
    
    private let networkManager = NetworkManager.shared
    private let recommendationsManager = RecommendationsManager.shared
    private let keepListeningManager = KeepListeningManager.shared
    private let favouritesManager = FavouritesManager.shared
    
    func loadInitialContent(modelContext: ModelContext) async {
        // Load cached data instantly (from previous session)
        loadCachedRecommendations()
        loadCachedKeepListening()
        loadCachedFavourites()
        
        // Load home content
        if homePage == nil {
            await loadHome()
        }
        
        // Refresh Keep Listening and Favourites on app launch
        if PlayCountManager.shared.hasPlayHistory(in: modelContext) {
            keepListeningSongs = keepListeningManager.refreshSongs(in: modelContext)
            favouriteItems = favouritesManager.refreshFavourites(in: modelContext)
        }
        
        // After everything is loaded, prefetch new recommendations in background for next launch
        if PlayCountManager.shared.hasPlayHistory(in: modelContext) {
            Task {
                await recommendationsManager.prefetchRecommendationsInBackground(in: modelContext)
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
        // On pull-to-refresh, refresh all sections immediately
        if PlayCountManager.shared.hasPlayHistory(in: modelContext) {
            keepListeningSongs = keepListeningManager.refreshSongs(in: modelContext)
            favouriteItems = favouritesManager.refreshFavourites(in: modelContext)
            recommendedSongs = await recommendationsManager.refreshRecommendations(in: modelContext)
        }
    }
    
    func loadCachedRecommendations() {
        // Load from cache instantly
        recommendedSongs = recommendationsManager.recommendations
    }
    
    func loadCachedKeepListening() {
        // Load from cache instantly
        keepListeningSongs = keepListeningManager.songs
    }
    
    func loadCachedFavourites() {
        // Load from cache instantly
        favouriteItems = favouritesManager.favourites
    }
    
    func loadHome() async {
        isLoading = true
        do {
            // Load Standard Home
            var home = try await networkManager.getHome()
            
            // Load Global Charts (Top Songs)
            async let globalCharts = try? networkManager.getCharts(country: "ZZ")
            async let punjabiCharts = try? networkManager.getCharts(country: "IN") // Using India for Punjabi context
            
            let gCharts = await globalCharts
            let pCharts = await punjabiCharts
            
            // Insert Charts into Sections
            // We want "Global" and "Punjabi" sections at the top or after quick picks
            
            var newSections: [HomeSection] = []
            
            // Add Global Top Songs if available
            if let gSections = gCharts?.sections {
                // Find "Top Songs" section
                if let topSongs = gSections.first(where: { $0.title.contains("Top songs") }) {
                    newSections.append(HomeSection(title: "Global Top Songs", strapline: "Trending Worldwide", items: topSongs.items))
                }
            }
            
            // Add Punjabi/India Top Songs if available
            if let pSections = pCharts?.sections {
                // Find "Top Songs" section
                if let topSongs = pSections.first(where: { $0.title.contains("Top songs") }) {
                    newSections.append(HomeSection(title: "Trending in India", strapline: "Top Songs", items: topSongs.items))
                }
            }
            
            // Combine with Home Sections
            // We'll put these new sections after the first section (usually Quick Picks)
            if !home.sections.isEmpty {
                home.sections.insert(contentsOf: newSections, at: 1)
            } else {
                home.sections.append(contentsOf: newSections)
            }
            
            self.homePage = home
            self.selectedChipId = nil
            
        } catch {
            print("Failed to load home: \(error)")
        }
        isLoading = false
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
