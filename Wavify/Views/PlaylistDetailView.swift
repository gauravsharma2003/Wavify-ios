//
//  PlaylistDetailView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    let playlistId: String
    let initialName: String
    let initialThumbnail: String
    
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.layoutContext) private var layout
    @State private var playlistPage: HomePage?
    @State private var isLoading = true
    @State private var gradientColors: [Color] = [Color(white: 0.1), Color(white: 0.05)]
    @State private var isSaved = false
    @State private var scrollOffset: CGFloat = 0
    
    // Add to playlist state
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongsStore = LikedSongsStore.shared
    
    private let networkManager = NetworkManager.shared
    
    private var songs: [Song] {
        // Flatten all items from all sections into a single list of songs
        guard let sections = playlistPage?.sections else { return [] }
        return sections.flatMap { $0.items }.compactMap { item in
            if item.type == .song || item.type == .video {
                return Song(from: item)
            }
            return nil
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)

                        Text("Loading playlist...")
                            .font(.system(size: layout.fontCaption))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.bottom, 200) // Add bottom padding to make it full screen
                } else {
                    if !songs.isEmpty {
                        actionButtons
                        songList
                    } else {
                        // Empty state - graceful full-width display
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: layout.isRegularWidth ? 64 : 48))
                                .foregroundStyle(.white.opacity(0.4))

                            Text("No songs found")
                                .font(.system(size: layout.fontBody, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text("This playlist may be empty or unavailable")
                                .font(.system(size: layout.fontCaption))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        .padding(.bottom, 200)
                        .padding(.horizontal, 40)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 40)
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
        .scrollEdgeEffectStyle(nil, for: .top)
        .background(
            LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle(initialName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(initialName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .opacity(scrollOffset < -(layout.detailArtworkSize + 20) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: scrollOffset < -(layout.detailArtworkSize + 20))
            }
        }
        .task {
            await loadPlaylist()
            await extractColors()
            checkSavedStatus()
            loadLikedStatus()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
    }
    
    private func extractColors() async {
        guard let url = URL(string: ImageUtils.thumbnailForCard(initialThumbnail)),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        
        let colors = await ColorExtractor.extractColors(from: uiImage)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientColors = [colors.primary, colors.secondary, Color(white: 0.06)]
            }
        }
    }
    
    private func loadPlaylist() async {
        isLoading = true
        do {
            playlistPage = try await networkManager.getPlaylist(id: playlistId)
        } catch {
            Logger.networkError("Failed to load playlist", error: error)
        }
        isLoading = false
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Artwork
            CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForCard(initialThumbnail))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.2), Color(white: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: layout.isRegularWidth ? 64 : 48))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }
            }
            .frame(width: layout.detailArtworkSize, height: layout.detailArtworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            
            // Info
            VStack(spacing: 8) {
                Text(initialName)
                    .font(.system(size: layout.fontHeadline, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("\(songs.count) songs")
                    .font(.system(size: layout.fontCaption))
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Actions
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Play Button
            Button {
                playAll()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: layout.fontButtonIcon, weight: .semibold))
                    Text("Play")
                        .font(.system(size: layout.fontButton, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: layout.buttonHeight)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // Action buttons row
            HStack(spacing: 12) {
                // Shuffle
                Button {
                    shufflePlay()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shuffle")
                            .font(.system(size: layout.fontButton, weight: .medium))
                        Text("Shuffle")
                            .font(.system(size: layout.fontButton, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.buttonHeight)
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                // Save/Remove Button
                Button {
                    toggleSavePlaylist()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: layout.fontButton, weight: .medium))
                        Text(isSaved ? "Saved" : "Save")
                            .font(.system(size: layout.fontButton, weight: .medium))
                    }
                    .foregroundColor(isSaved ? .green : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.buttonHeight)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .frame(maxWidth: layout.detailButtonMaxWidth)
        .padding(.horizontal, 40)
    }
    
    // MARK: - List
    
    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumSongRow(
                    index: index + 1,
                    song: song,
                    isPlaying: audioPlayer.currentSong?.id == song.id,
                    isLiked: likedSongsStore.likedSongIds.contains(song.videoId),
                    isInQueue: audioPlayer.isInQueue(song),
                    onTap: {
                        Task {
                            await audioPlayer.playAlbum(songs: songs, startIndex: index, shuffle: false)
                        }
                    },
                    onAddToPlaylist: {
                        selectedSongForPlaylist = song
                    },
                    onToggleLike: {
                        toggleLikeSong(song)
                    },
                    onPlayNext: {
                        audioPlayer.playNextSong(song)
                    },
                    onAddToQueue: {
                        _ = audioPlayer.addToQueue(song)
                    },
                    imageSize: layout.songRowImageSize,
                    trackNumWidth: layout.trackNumberWidth,
                    titleFont: layout.fontBody,
                    artistFont: layout.fontCaption,
                    menuIconSize: layout.fontButtonIcon,
                    menuFrameSize: layout.isRegularWidth ? 32 : 24,
                    rowPadding: layout.isRegularWidth ? 16 : 12
                )

                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, layout.dividerLeading)
                        .opacity(0.3)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    // MARK: - Playback
    
    private func playAll() {
        Task {
            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: false)
        }
    }
    
    private func shufflePlay() {
        Task {
            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: true)
        }
    }
    
    // MARK: - Save/Unsave
    
    private func checkSavedStatus() {
        let descriptor = FetchDescriptor<LocalPlaylist>(
            predicate: #Predicate { $0.albumId == playlistId }
        )
        isSaved = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }
    
    private func toggleSavePlaylist() {
        if isSaved {
            removePlaylist()
        } else {
            savePlaylist()
        }
    }
    
    private func savePlaylist() {
        guard !songs.isEmpty else { return }
        
        // Create the local playlist
        let localPlaylist = LocalPlaylist(
            name: initialName,
            thumbnailUrl: initialThumbnail,
            albumId: playlistId
        )
        
        // Create and add local songs
        for (index, song) in songs.enumerated() {
            // Check if song already exists
            let videoId = song.videoId
            let songDescriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId }
            )
            
            let localSong: LocalSong
            if let existingSong = try? modelContext.fetch(songDescriptor).first {
                localSong = existingSong
            } else {
                localSong = LocalSong(
                    videoId: song.videoId,
                    title: song.title,
                    artist: song.artist,
                    thumbnailUrl: song.thumbnailUrl,
                    duration: song.duration,
                    orderIndex: index
                )
                modelContext.insert(localSong)
            }
            
            // Set the order index for this playlist
            localSong.orderIndex = index
            localPlaylist.songs.append(localSong)
        }
        
        modelContext.insert(localPlaylist)
        isSaved = true
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            // Visual feedback
        }
    }
    
    private func removePlaylist() {
        let descriptor = FetchDescriptor<LocalPlaylist>(
            predicate: #Predicate { $0.albumId == playlistId }
        )
        
        if let playlist = try? modelContext.fetch(descriptor).first {
            modelContext.delete(playlist)
            isSaved = false
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                // Visual feedback
            }
        }
    }
    
    // MARK: - Like Management
    
    private func loadLikedStatus() {
        likedSongsStore.loadIfNeeded(context: modelContext)
    }

    private func toggleLikeSong(_ song: Song) {
        likedSongsStore.toggleLike(for: song, in: modelContext)
    }
}
