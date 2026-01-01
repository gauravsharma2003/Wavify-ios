//
//  AlbumDetailView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI
import SwiftData

struct AlbumDetailView: View {
    // Remote album parameters (used when opening from search)
    let albumId: String?
    let initialName: String
    let initialArtist: String
    let initialThumbnail: String
    
    // Local playlist parameter (used when opening from library)
    var localPlaylist: LocalPlaylist?
    
    var audioPlayer: AudioPlayer
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var savedPlaylists: [LocalPlaylist]
    
    @State private var albumDetail: AlbumDetail?
    @State private var isLoading = true
    @State private var isSaved = false
    @State private var showDelete = false
    @State private var gradientColors: [Color] = [Color(white: 0.1), Color(white: 0.05)]
    
    private let networkManager = NetworkManager.shared
    
    // Computed properties for unified data access
    private var displayName: String {
        albumDetail?.albumName ?? localPlaylist?.name ?? initialName
    }
    
    private var displayArtist: String {
        albumDetail?.artist ?? initialArtist
    }
    
    private var displayThumbnail: String {
        albumDetail?.albumThumbnail ?? localPlaylist?.thumbnailUrl ?? initialThumbnail
    }
    
    private var songs: [Song] {
        if let album = albumDetail {
            return album.songs.map { Song(id: $0.id, title: $0.title, artist: album.artist, thumbnailUrl: album.albumThumbnail, duration: $0.duration) }
        } else if let playlist = localPlaylist {
            return playlist.sortedSongs.map { Song(from: $0) }
        }
        return []
    }
    
    private var songCount: Int {
        albumDetail?.songs.count ?? localPlaylist?.songCount ?? 0
    }
    
    private var isLocalPlaylist: Bool {
        localPlaylist != nil && albumId == nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                albumArtwork
                albumInfo
                if !songs.isEmpty {
                    actionButtons
                }
                songList
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
            if let albumId = albumId {
                await loadAlbumDetails(albumId: albumId)
            } else {
                // For local playlists, no remote loading needed
                isLoading = false
            }
            checkIfSaved()
            await extractColors()
        }
    }
    
    private func extractColors() async {
        guard let url = URL(string: ImageUtils.thumbnailForCard(displayThumbnail)),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        
        let colors = await ColorExtractor.extractColors(from: uiImage)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientColors = [colors.0, colors.1, Color(white: 0.06)]
            }
        }
    }
    
    // MARK: - Album Artwork
    
    private var albumArtwork: some View {
        AsyncImage(url: URL(string: ImageUtils.thumbnailForCard(displayThumbnail))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.8))
                    }
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
    
    // MARK: - Album Info
    
    private var albumInfo: some View {
        VStack(spacing: 8) {
            MarqueeText(
                text: displayName,
                font: .system(size: 22, weight: .bold),
                alignment: .center
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            
            if !displayArtist.isEmpty {
                Text(displayArtist)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            
            Text("\(songCount) songs")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Action Buttons
    
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
            
            // Shuffle & Save/Delete Buttons
            HStack(spacing: 16) {
                // Shuffle Button
                Button {
                    shufflePlay()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .medium))
                        Text("Shuffle")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                
                // Save/Delete Button
                Button {
                    toggleSave()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSaved ? (showDelete ? "trash" : "checkmark") : "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text(isSaved ? (showDelete ? "Delete" : "Saved") : "Save")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(isSaved ? (showDelete ? .red : .green) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Song List
    
    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumSongRow(
                    index: index + 1,
                    title: song.title,
                    duration: song.duration,
                    isPlaying: audioPlayer.currentSong?.id == song.id
                ) {
                    Task {
                        await audioPlayer.playAlbum(songs: songs, startIndex: index, shuffle: false)
                    }
                }
                
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
    
    // MARK: - Actions
    
    private func playAll() {
        // Track album play for favourites (only for remote albums, not local playlists)
        if let albumId = albumId, !isLocalPlaylist {
            FavouritesManager.shared.trackAlbumPlay(
                albumId: albumId,
                title: displayName,
                artist: displayArtist,
                thumbnailUrl: displayThumbnail,
                in: modelContext
            )
        }
        
        Task {
            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: false)
        }
    }
    
    private func shufflePlay() {
        // Track album play for favourites (only for remote albums, not local playlists)
        if let albumId = albumId, !isLocalPlaylist {
            FavouritesManager.shared.trackAlbumPlay(
                albumId: albumId,
                title: displayName,
                artist: displayArtist,
                thumbnailUrl: displayThumbnail,
                in: modelContext
            )
        }
        
        Task {
            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: true)
        }
    }
    
    private func loadAlbumDetails(albumId: String) async {
        isLoading = true
        do {
            albumDetail = try await networkManager.getAlbumDetails(albumId: albumId)
        } catch {
            print("Failed to load album: \(error)")
        }
        isLoading = false
    }
    
    private func checkIfSaved() {
        let checkId = albumId ?? localPlaylist?.albumId
        if let checkId = checkId {
            isSaved = savedPlaylists.contains { $0.albumId == checkId }
        } else if localPlaylist != nil {
            isSaved = true
        }
        if isSaved {
            showDelete = true  // Already saved, show delete immediately
        }
    }
    
    private func toggleSave() {
        let playlistId = albumId ?? localPlaylist?.albumId
        
        if isSaved {
            // Remove from saved
            if let playlistId = playlistId,
               let playlist = savedPlaylists.first(where: { $0.albumId == playlistId }) {
                modelContext.delete(playlist)
            } else if let localPlaylist = localPlaylist {
                modelContext.delete(localPlaylist)
                dismiss()
            }
            isSaved = false
            showDelete = false
        } else {
            // Save to library
            guard let album = albumDetail else { return }
            
            let playlist = LocalPlaylist(
                name: album.albumName,
                thumbnailUrl: album.albumThumbnail,
                albumId: album.albumId
            )
            
            for (index, albumSong) in album.songs.enumerated() {
                let localSong = LocalSong(
                    videoId: albumSong.id,
                    title: albumSong.title,
                    artist: album.artist,
                    thumbnailUrl: album.albumThumbnail,
                    duration: albumSong.duration,
                    orderIndex: index
                )
                playlist.songs.append(localSong)
                modelContext.insert(localSong)
            }
            
            modelContext.insert(playlist)
            isSaved = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showDelete = true
            }
        }
    }
}

// MARK: - Album Song Row

struct AlbumSongRow: View {
    let index: Int
    let title: String
    let duration: String
    let isPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Track Number or Playing Indicator
                ZStack {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28)
                
                // Song Title
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(isPlaying ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Duration
                Text(duration)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                
                // Options
                Button {
                    // Options menu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Marquee Text

struct MarqueeText: View {
    let text: String
    let font: Font
    var alignment: Alignment = .leading
    
    @State private var animate = false
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let shouldScroll = textWidth > geometry.size.width
            
            ZStack(alignment: alignment) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.onAppear {
                                textWidth = textGeo.size.width
                            }
                        }
                    )
                    .offset(x: shouldScroll && animate ? -(textWidth - geometry.size.width + 20) : 0)
                    .animation(
                        shouldScroll ? .linear(duration: Double(textWidth / 30)).repeatForever(autoreverses: true).delay(1) : nil,
                        value: animate
                    )
            }
            .frame(width: geometry.size.width, alignment: alignment)
            .clipped()
            .onAppear {
                containerWidth = geometry.size.width
                if textWidth > containerWidth {
                    animate = true
                }
            }
        }
        .frame(height: 28)
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(
            albumId: "test",
            initialName: "Album Name",
            initialArtist: "Artist",
            initialThumbnail: "",
            audioPlayer: AudioPlayer.shared
        )
    }
}
