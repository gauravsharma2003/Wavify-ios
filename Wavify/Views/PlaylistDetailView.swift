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
    @State private var playlistPage: HomePage?
    @State private var isLoading = true
    @State private var gradientColors: [Color] = [Color(white: 0.1), Color(white: 0.05)]
    @State private var isSaved = false
    
    // Add to playlist state
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongIds: Set<String> = []
    
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
                            .font(.system(size: 14))
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
                        Text("No songs found")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 40)
        }
        .background(
            LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            // Gradient blur at top
            LinearGradient(
                stops: [
                    .init(color: (gradientColors.first ?? .black).opacity(0.9), location: 0),
                    .init(color: (gradientColors.first ?? .black).opacity(0.6), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                gradientColors = [colors.0, colors.1, Color(white: 0.06)]
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
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            
            // Info
            VStack(spacing: 8) {
                Text(initialName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("\(songs.count) songs")
                    .font(.system(size: 14))
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
                        .font(.system(size: 16, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 40)
            
            // Action buttons row
            HStack(spacing: 12) {
                // Shuffle
                Button {
                    shufflePlay()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .medium))
                        Text("Shuffle")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                
                // Save/Remove Button
                Button {
                    toggleSavePlaylist()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 14, weight: .medium))
                        Text(isSaved ? "Saved" : "Save")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(isSaved ? .green : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - List
    
    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumSongRow(
                    index: index + 1,
                    song: song,
                    isPlaying: audioPlayer.currentSong?.id == song.id,
                    isLiked: likedSongIds.contains(song.videoId),
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
                    }
                )
                
                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, 50)
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
        for song in songs {
            let videoId = song.videoId
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
