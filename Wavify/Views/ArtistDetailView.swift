//
//  ArtistDetailView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI

struct ArtistDetailView: View {
    let artistId: String
    let initialName: String
    let initialThumbnail: String
    
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @State private var artistDetail: ArtistDetail?
    @State private var isLoading = true
    @State private var gradientColors: [Color] = [Color(white: 0.1), Color(white: 0.05)]
    @State private var scrollOffset: CGFloat = 0
    
    private let networkManager = NetworkManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content with gradient starting here
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 50)
                    } else if let detail = artistDetail {
                        // Action Buttons
                        actionButtons
                            .padding(.top, 16)
                        
                        // Content Sections
                        VStack(spacing: 32) {
                            ForEach(detail.sections.filter { $0.type != .videos && $0.type != .unknown }) { section in
                                sectionView(for: section)
                            }
                        }
                        .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 40)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height)
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
        .task {
            await loadArtistDetails()
            await extractColors()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .global).minY
            // Only stretch when pulling down (minY > 0)
            let height = 350 + (minY > 0 ? minY : 0)
            let offset = minY > 0 ? -minY : 0
            
            ZStack(alignment: .bottom) {
                // Background Image
                AsyncImage(url: URL(string: ImageUtils.thumbnailForPlayer(artistDetail?.thumbnailUrl ?? initialThumbnail))) { phase in
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
                    
                    if let subscribers = artistDetail?.subscribers {
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
                Text(section.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                switch section.type {
                case .topSongs:
                    topSongsGrid(section.items)
                case .albums, .singles:
                    albumsGrid(section.items)
                case .similarArtists:
                    similarArtistsList(section.items)
                case .videos:
                    albumsGrid(section.items) // Reuse album grid for now
                case .unknown:
                    EmptyView()
                }
            }
        }
    }
    
    // Top Songs: 5 rows horizontal grid
    private func topSongsGrid(_ items: [ArtistItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(
                rows: Array(repeating: GridItem(.fixed(60), spacing: 8), count: 5),
                spacing: 16
            ) {
                ForEach(Array(items.prefix(15).enumerated()), id: \.element.id) { index, item in
                    Button {
                        playSong(item)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color.gray.opacity(0.3))
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
                            .frame(width: 200, alignment: .leading)
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 340) // 5 * 60 + spacings
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
        NavigationLink {
            if let browseId = item.browseId {
                AlbumDetailView(
                    albumId: browseId,
                    initialName: item.title,
                    initialArtist: artistDetail?.name ?? "",
                    initialThumbnail: item.thumbnailUrl,
                    audioPlayer: audioPlayer
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
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
                            AsyncImage(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.gray.opacity(0.3))
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
        do {
            artistDetail = try await networkManager.getArtistDetails(browseId: artistId)
        } catch {
            print("Failed to load artist details: \(error)")
        }
        isLoading = false
    }
    
    private func extractColors() async {
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
        guard let songs = artistDetail?.sections.first(where: { $0.type == .topSongs })?.items else { return }
        let songList = songs.map { Song(from: $0, artist: artistDetail?.name ?? initialName) }
        Task {
            await audioPlayer.playAlbum(songs: songList, startIndex: 0, shuffle: false)
        }
    }
    
    private func shuffleTopSongs() {
        guard let songs = artistDetail?.sections.first(where: { $0.type == .topSongs })?.items else { return }
        let songList = songs.map { Song(from: $0, artist: artistDetail?.name ?? initialName) }
        Task {
            await audioPlayer.playAlbum(songs: songList, startIndex: 0, shuffle: true)
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
