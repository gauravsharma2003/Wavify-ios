//
//  ArtistDetailView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI
import SwiftData

struct ArtistDetailView: View {
    let artistId: String
    let initialName: String
    let initialThumbnail: String
    
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var artistDetail: ArtistDetail?
    @State private var isLoading = true
    @State private var gradientColors: [Color] = [Color(white: 0.1), Color(white: 0.05)]
    @State private var scrollOffset: CGFloat = 0
    
    // Add to playlist state
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongIds: Set<String> = []
    
    // Hero animation namespace for albums
    @Namespace private var artistHeroAnimation
    
    // Cooldown to prevent rapid re-open of same item (prevents animation glitch)
    @State private var lastClosedItemId: String?
    @State private var lastClosedTime: Date?
    
    private let networkManager = NetworkManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content with gradient starting here
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 50)
                    } else if let detail = artistDetail {
                        // Action Buttons
                        actionButtons
                            .padding(.top, 16)
                        
                        // Content Sections
                        VStack(spacing: 32) {
                            ForEach(detail.sections.filter { $0.type != .unknown }) { section in
                                sectionView(for: section)
                            }
                        }
                        .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 40)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: UIScreen.main.bounds.height - 350)  // Subtract header height
                .background(
                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                )
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("scroll")).minY
                        )
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
        .background((gradientColors.last ?? Color(white: 0.05)).ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: artistId) {
            // Only load if we don't already have data for this artist
            guard artistDetail == nil || artistDetail?.name != initialName else { return }
            await loadArtistDetails()
            await extractColors()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .global).minY
            // Only stretch when pulling down (minY > 0)
            let height = max(350, 350 + (minY > 0 ? minY : 0))
            let offset = minY > 0 ? -minY : 0
            
            ZStack(alignment: .bottom) {
                // Background Image
                CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForPlayer(artistDetail?.thumbnailUrl ?? initialThumbnail))) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: height)
                            .clipped()
                            .overlay(
                                // Gradient that ends exactly where page background begins
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.4),
                                        .init(color: (gradientColors.first ?? .black).opacity(0.3), location: 0.6),
                                        .init(color: (gradientColors.first ?? .black).opacity(0.7), location: 0.8),
                                        .init(color: gradientColors.first ?? .black, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        Rectangle()
                            .fill(gradientColors.first ?? Color(white: 0.1))
                    }
                }
                
                // Content Overlay (Name only) - no material, just text on gradient
                VStack(alignment: .leading, spacing: 4) {
                    Text(artistDetail?.name ?? initialName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    if let subscribers = artistDetail?.subscribers, !subscribers.isEmpty, artistDetail?.isChannel != true {
                        Text("\(subscribers) • Listeners")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .offset(y: offset)
        }
        .frame(height: 350)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                playTopSongs()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            
            Button {
                shuffleTopSongs()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Shuffle")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private func sectionView(for section: ArtistSection) -> some View {
        // Hide section if no items
        if section.items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let browseId = section.browseId {
                    NavigationLink {
                        if section.type == .topSongs {
                            ArtistTopSongsView(
                                browseId: browseId,
                                artistName: artistDetail?.name ?? initialName,
                                audioPlayer: audioPlayer
                            )
                        } else {
                            ArtistItemsGridView(
                                title: section.title,
                                browseId: browseId,
                                params: section.params,
                                artistName: artistDetail?.name ?? initialName,
                                audioPlayer: audioPlayer,
                                fallbackItems: section.items  // Use carousel items as fallback
                            )
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(section.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                } else {
                    Text(section.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                }
                
                switch section.type {
                case .topSongs, .videos:  // Videos use same playable layout as top songs
                    topSongsGrid(section.items)
                case .albums, .singles:
                    albumsGrid(section.items)
                case .similarArtists:
                    similarArtistsList(section.items)
                case .unknown:
                    EmptyView()
                }
            }
        }
    }
    
    // Top Songs: 5 rows horizontal grid
    private func topSongsGrid(_ items: [ArtistItem]) -> some View {
        if items.isEmpty {
            return AnyView(EmptyView())
        }
        
        let rowCount = min(5, max(1, items.count))
        let rows = Array(repeating: GridItem(.fixed(60), spacing: 8), count: rowCount)
        let totalHeight = CGFloat(rowCount * 60 + (rowCount - 1) * 8)
        let displayItems = Array(items.prefix(25).enumerated())
        
        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 16) {
                    ForEach(displayItems, id: \.element.id) { index, item in
                        HStack(spacing: 0) {
                            Button {
                                playSong(item)
                            } label: {
                                HStack(spacing: 12) {
                                    CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            Rectangle().fill(Color.gray.opacity(0.3))
                                        }
                                    }
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        
                                        Text(item.subtitle ?? "")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            SongOptionsMenu(
                                isLiked: likedSongIds.contains(item.videoId ?? ""),
                                isInQueue: {
                                    guard let videoId = item.videoId else { return false }
                                    let song = Song(from: item, artist: artistDetail?.name ?? initialName)
                                    return audioPlayer.isInQueue(song)
                                }(),
                                isPlaying: {
                                    guard let videoId = item.videoId else { return false }
                                    return audioPlayer.currentSong?.id == videoId
                                }(),
                                onAddToPlaylist: {
                                    guard let videoId = item.videoId else { return }
                                    let song = Song(from: item, artist: artistDetail?.name ?? initialName)
                                    selectedSongForPlaylist = song
                                },
                                onToggleLike: {
                                    guard let videoId = item.videoId else { return }
                                    let song = Song(from: item, artist: artistDetail?.name ?? initialName)
                                    toggleLikeSong(song)
                                },
                                onPlayNext: {
                                    guard let videoId = item.videoId else { return }
                                    let song = Song(from: item, artist: artistDetail?.name ?? initialName)
                                    audioPlayer.playNextSong(song)
                                },
                                onAddToQueue: {
                                    guard let videoId = item.videoId else { return }
                                    let song = Song(from: item, artist: artistDetail?.name ?? initialName)
                                    _ = audioPlayer.addToQueue(song)
                                }
                            )
                        }
                        .padding(.horizontal, 4)
                        .frame(width: UIScreen.main.bounds.width - 48)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: totalHeight)
        )
    }
    
    // Albums/Singles: Dynamic grid - 1 row for ≤2 items, 2 rows otherwise
    @ViewBuilder
    private func albumsGrid(_ items: [ArtistItem]) -> some View {
        if items.isEmpty {
            EmptyView()
        } else if items.count <= 2 {
            // Single row for 2 or fewer items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        albumCard(item)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 200)
        } else {
            // Two rows for more items
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(items) { item in
                        albumCard(item)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 400)
        }
    }
    
    private func albumCard(_ item: ArtistItem) -> some View {
        // Check if this item is in cooldown (recently closed)
        let isInCooldown: Bool = {
            guard lastClosedItemId == item.id,
                  let closedTime = lastClosedTime else { return false }
            return Date().timeIntervalSince(closedTime) < 0.8 // 800ms cooldown
        }()
        
        return NavigationLink {
            if let browseId = item.browseId {
                AlbumDetailView(
                    albumId: browseId,
                    initialName: item.title,
                    initialArtist: artistDetail?.name ?? "",
                    initialThumbnail: item.thumbnailUrl,
                    audioPlayer: audioPlayer
                )
                .navigationTransition(.zoom(sourceID: item.id, in: artistHeroAnimation))
                .onDisappear {
                    // Track when this item's detail view closes
                    lastClosedItemId = item.id
                    lastClosedTime = Date()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color(white: 0.1) // Stable background
                    CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.clear // Use clear here as background provides the color
                        }
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .matchedTransitionSource(id: item.id, in: artistHeroAnimation)
                
                Text(item.title)
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                
                Text(item.subtitle ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isInCooldown) // Disable taps during cooldown
    }
    
    // Similar Artists: Circular profiles
    private func similarArtistsList(_ items: [ArtistItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(items) { item in
                    NavigationLink {
                        if let browseId = item.browseId {
                            ArtistDetailView(
                                artistId: browseId,
                                initialName: item.title,
                                initialThumbnail: item.thumbnailUrl,
                                audioPlayer: audioPlayer
                            )
                        }
                    } label: {
                        VStack(spacing: 8) {
                            CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Circle().fill(Color.gray.opacity(0.3))
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 100)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Actions
    
    private func loadArtistDetails() async {
        // Skip if already loaded
        guard artistDetail == nil else {
            isLoading = false
            return
        }
        
        do {
            artistDetail = try await networkManager.getArtistDetails(browseId: artistId)
            
            // Update stored artist thumbnail with the correct one if we had a wrong one cached
            if let realThumbnail = artistDetail?.thumbnailUrl {
                FavouritesManager.shared.updateArtistThumbnailIfNeeded(
                    artistId: artistId,
                    correctThumbnailUrl: realThumbnail,
                    in: modelContext
                )
            }
        } catch {
            Logger.networkError("Failed to load artist details", error: error)
        }
        isLoading = false
    }
    
    private func extractColors() async {
        loadLikedStatus()
        let imageUrl = artistDetail?.thumbnailUrl ?? initialThumbnail
        guard let url = URL(string: ImageUtils.thumbnailForCard(imageUrl)),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        
        let colors = await ColorExtractor.extractColors(from: uiImage)
        // Define the ending color that matches the navbar background
        let navbarBackgroundColor = Color(white: 0.05)
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientColors = [colors.0, colors.1.opacity(0.6), navbarBackgroundColor]
            }
        }
    }
    
    private func playTopSongs() {
        // Try topSongs first, then fall back to videos for channels
        guard let section = artistDetail?.sections.first(where: { $0.type == .topSongs })
              ?? artistDetail?.sections.first(where: { $0.type == .videos }) else { return }
        
        // Track artist play for favourites
        FavouritesManager.shared.trackArtistPlay(
            artistId: artistId,
            name: artistDetail?.name ?? initialName,
            thumbnailUrl: artistDetail?.thumbnailUrl ?? initialThumbnail,
            in: modelContext
        )
        
        Task {
            var songsToPlay: [Song] = []
            
            // For videos, use items directly (no playlist fetch needed)
            // For topSongs with browseId, try to fetch full list
            if section.type == .videos {
                // Videos section - use items directly
                songsToPlay = section.items.map { Song(from: $0, artist: artistDetail?.name ?? initialName) }
            } else if let browseId = section.browseId {
                // Try to fetch full list for top songs
                do {
                    let page = try await networkManager.getPlaylist(id: browseId)
                    if let fullSection = page.sections.first {
                        songsToPlay = fullSection.items.compactMap { item in
                            guard let videoId = item.id.count > 0 ? item.id : nil else { return nil }
                            return Song(
                                id: videoId,
                                title: item.name,
                                artist: item.artist.isEmpty ? (artistDetail?.name ?? initialName) : item.artist,
                                thumbnailUrl: item.thumbnailUrl,
                                duration: ""
                            )
                        }
                    }
                } catch {
                    Logger.networkError("Failed to fetch full top songs for playback", error: error)
                }
            }
            
            // Fallback to currently loaded items
            if songsToPlay.isEmpty {
                songsToPlay = section.items.map { Song(from: $0, artist: artistDetail?.name ?? initialName) }
            }
            
            if !songsToPlay.isEmpty {
                await audioPlayer.playAlbum(songs: songsToPlay, startIndex: 0, shuffle: false)
            }
        }
    }
    
    private func shuffleTopSongs() {
        // Try topSongs first, then fall back to videos for channels
        guard let section = artistDetail?.sections.first(where: { $0.type == .topSongs })
              ?? artistDetail?.sections.first(where: { $0.type == .videos }) else { return }
        
        // Track artist play for favourites
        FavouritesManager.shared.trackArtistPlay(
            artistId: artistId,
            name: artistDetail?.name ?? initialName,
            thumbnailUrl: artistDetail?.thumbnailUrl ?? initialThumbnail,
            in: modelContext
        )
        
        Task {
            var songsToPlay: [Song] = []
            
            // For videos, use items directly (no playlist fetch needed)
            // For topSongs with browseId, try to fetch full list
            if section.type == .videos {
                // Videos section - use items directly
                songsToPlay = section.items.map { Song(from: $0, artist: artistDetail?.name ?? initialName) }
            } else if let browseId = section.browseId {
                // Try to fetch full list for top songs
                do {
                    let page = try await networkManager.getPlaylist(id: browseId)
                    if let fullSection = page.sections.first {
                        songsToPlay = fullSection.items.compactMap { item in
                            guard let videoId = item.id.count > 0 ? item.id : nil else { return nil }
                            return Song(
                                id: videoId,
                                title: item.name,
                                artist: item.artist.isEmpty ? (artistDetail?.name ?? initialName) : item.artist,
                                thumbnailUrl: item.thumbnailUrl,
                                duration: ""
                            )
                        }
                    }
                } catch {
                    Logger.networkError("Failed to fetch full top songs for shuffle", error: error)
                }
            }
            
            // Fallback to currently loaded items
            if songsToPlay.isEmpty {
                songsToPlay = section.items.map { Song(from: $0, artist: artistDetail?.name ?? initialName) }
            }
            
            if !songsToPlay.isEmpty {
                await audioPlayer.playAlbum(songs: songsToPlay, startIndex: 0, shuffle: true)
            }
        }
    }


    
    private func playSong(_ item: ArtistItem) {
        guard let videoId = item.videoId else { return }
        let song = Song(
            id: videoId,
            title: item.title,
            artist: artistDetail?.name ?? initialName,
            thumbnailUrl: item.thumbnailUrl,
            duration: ""
        )
        Task {
            await audioPlayer.loadAndPlay(song: song)
        }
    }
    
    // MARK: - Like Management
    
    private func loadLikedStatus() {
        guard let items = artistDetail?.sections.first(where: { $0.type == .topSongs })?.items else { return }
        
        for item in items {
            guard let videoId = item.videoId else { continue }
            let descriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId && $0.isLiked == true }
            )
            if (try? modelContext.fetchCount(descriptor)) ?? 0 > 0 {
                likedSongIds.insert(videoId)
            }
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

// Extension to map ArtistItem to Song
extension Song {
    init(from artistItem: ArtistItem, artist: String) {
        self.init(
            id: artistItem.videoId ?? "",
            title: artistItem.title,
            artist: artist,
            thumbnailUrl: artistItem.thumbnailUrl,
            duration: ""
        )
    }
    }


struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
