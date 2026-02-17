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
    @State private var scrollOffset: CGFloat = 0
    
    // Add to playlist state
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongsStore = LikedSongsStore.shared
    
    // Rename playlist state
    @State private var showRenameAlert = false
    @State private var newPlaylistName = ""
    
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

    private var displayYear: String {
        albumDetail?.year ?? ""
    }
    
    private var isLocalPlaylist: Bool {
        localPlaylist != nil && albumId == nil
    }
    
    /// User-created playlists have no albumId (external playlists that are saved have an albumId)
    private var isUserCreatedPlaylist: Bool {
        localPlaylist != nil && (localPlaylist?.albumId == nil || localPlaylist?.albumId?.isEmpty == true)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerView

                // Content with gradient starting here
                VStack(spacing: 20) {
                    albumInfo

                    if isLoading {
                        VStack(spacing: 20) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)

                            Text("Loading album...")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .padding(.bottom, 200)
                    } else if !songs.isEmpty {
                        actionButtons
                        songList
                    } else if isUserCreatedPlaylist {
                        emptyPlaylistState
                    } else {
                        remoteEmptyState
                    }
                }
                .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 40)
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 350, alignment: .top)
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
            if let albumId = albumId {
                await loadAlbumDetails(albumId: albumId)
            } else {
                isLoading = false
            }
            checkIfSaved()
            loadLikedStatus()
            await extractColors()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Save") {
                renamePlaylist()
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
        }
    }
    
    private func extractColors() async {
        guard let url = URL(string: ImageUtils.thumbnailForPlayer(displayThumbnail)),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        
        let colors = await ColorExtractor.extractColors(from: uiImage)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientColors = [colors.0, colors.1, Color(white: 0.06)]
            }
        }
    }
    
    // MARK: - Header

    private var headerView: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .global).minY
            let height = max(350, 350 + (minY > 0 ? minY : 0))
            let offset = minY > 0 ? -minY : 0

            CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForPlayer(displayThumbnail))) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: height)
                        .clipped()
                        .overlay(
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
            .offset(y: offset)
        }
        .frame(height: 350)
    }

    private var albumInfo: some View {
        VStack(spacing: 6) {
            if isUserCreatedPlaylist {
                Button {
                    newPlaylistName = displayName
                    showRenameAlert = true
                } label: {
                    Text(displayName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            } else {
                Text(displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !displayArtist.isEmpty || !displayYear.isEmpty {
                Text([displayArtist, displayYear].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 12)
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
                    onRemoveFromPlaylist: isUserCreatedPlaylist ? {
                        removeSongFromPlaylist(song)
                    } : nil
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
    
    // MARK: - Empty Playlist State
    
    private var emptyPlaylistState: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)
            
            Image(systemName: "plus.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No songs yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("Add songs to this playlist")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
    
    // MARK: - Remote Album Empty State
    
    private var remoteEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            
            Text("No songs found")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("This album may be empty or unavailable")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 200)
        .padding(.horizontal, 40)
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
            Logger.networkError("Failed to load album", error: error)
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
    
    // MARK: - Like Management
    
    private func loadLikedStatus() {
        likedSongsStore.loadIfNeeded(context: modelContext)
    }

    private func toggleLikeSong(_ song: Song) {
        likedSongsStore.toggleLike(for: song, in: modelContext)
    }
    
    // MARK: - Playlist Management
    
    private func renamePlaylist() {
        guard !newPlaylistName.isEmpty, let playlist = localPlaylist else { return }
        playlist.name = newPlaylistName
        try? modelContext.save()
        newPlaylistName = ""
    }
    
    private func removeSongFromPlaylist(_ song: Song) {
        guard let playlist = localPlaylist else { return }
        playlist.songs.removeAll { $0.videoId == song.videoId }
        try? modelContext.save()
    }
}

// MARK: - Album Song Row

struct AlbumSongRow: View {
    let index: Int
    let song: Song
    let isPlaying: Bool
    let onTap: () -> Void
    var onAddToPlaylist: (() -> Void)? = nil
    var onToggleLike: (() -> Void)? = nil
    var onPlayNext: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    var onRemoveFromPlaylist: (() -> Void)? = nil
    var isLiked: Bool = false
    var isInQueue: Bool = false
    var showImage: Bool = false
    
    // Legacy initializer for backward compatibility
    init(
        index: Int,
        title: String,
        duration: String,
        isPlaying: Bool,
        onTap: @escaping () -> Void
    ) {
        self.index = index
        self.song = Song(
            id: "",
            title: title,
            artist: "",
            thumbnailUrl: "",
            duration: duration,
            isLiked: false
        )
        self.isPlaying = isPlaying
        self.onTap = onTap
        self.onAddToPlaylist = nil
        self.onToggleLike = nil
        self.isLiked = false
        self.showImage = false // Default for legacy
    }
    
    // New initializer with Song and menu callbacks
    init(
        index: Int,
        song: Song,
        isPlaying: Bool,
        isLiked: Bool = false,
        isInQueue: Bool = false,
        showImage: Bool = false,
        onTap: @escaping () -> Void,
        onAddToPlaylist: (() -> Void)? = nil,
        onToggleLike: (() -> Void)? = nil,
        onPlayNext: (() -> Void)? = nil,
        onAddToQueue: (() -> Void)? = nil,
        onRemoveFromPlaylist: (() -> Void)? = nil
    ) {
        self.index = index
        self.song = song
        self.isPlaying = isPlaying
        self.isLiked = isLiked
        self.isInQueue = isInQueue
        self.showImage = showImage
        self.onTap = onTap
        self.onAddToPlaylist = onAddToPlaylist
        self.onToggleLike = onToggleLike
        self.onPlayNext = onPlayNext
        self.onAddToQueue = onAddToQueue
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
    }
    
    var body: some View {
        Button(action: { onTap() }) {
            HStack(spacing: 12) {
                // Image or Track Number
                if showImage {
                    ZStack {
                        CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForCard(song.thumbnailUrl))) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Rectangle().fill(Color.gray.opacity(0.3))
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        // Playing overlay for image
                        if isPlaying {
                            ZStack {
                                Color.black.opacity(0.4)
                                Image(systemName: "waveform.low")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                    .symbolEffect(.variableColor.iterative)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: 48, height: 48)
                } else {
                    // Standard Track Number / Waveform
                    ZStack {
                        if isPlaying {
                            Image(systemName: "waveform.low")
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
                }
                
                // Song Title & Artist (if image shown, likely want artist too?)
                // For now, sticking to Title as per existing row, but Top Songs usually show artist name too if mixed,
                // but here it's Artist Page so artist is implied.
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 15))
                        .foregroundStyle(isPlaying ? .white : .primary)
                        .lineLimit(1)
                    
                    if showImage {
                        Text(song.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Duration
                Text(song.duration)
                    .foregroundStyle(.secondary)
                
                // Options Menu
                Menu {
                    // Queue options first
                    if let onPlayNext = onPlayNext {
                        Button {
                            onPlayNext()
                        } label: {
                            Label(isPlaying ? "Currently Playing" : "Play Next", 
                                  systemImage: isPlaying ? "speaker.wave.2" : "text.line.first.and.arrowtriangle.forward")
                        }
                        .disabled(isPlaying)
                    }
                    
                    if let onAddToQueue = onAddToQueue {
                        Button {
                            onAddToQueue()
                        } label: {
                            Label(isPlaying ? "Currently Playing" : (isInQueue ? "Already in Queue" : "Add to Queue"), 
                                  systemImage: isPlaying ? "speaker.wave.2" : (isInQueue ? "checkmark" : "text.append"))
                        }
                        .disabled(isInQueue || isPlaying)
                    }
                    
                    if onPlayNext != nil || onAddToQueue != nil {
                        Divider()
                    }
                    
                    if let onAddToPlaylist = onAddToPlaylist {
                        Button {
                            onAddToPlaylist()
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                    }
                    
                    if let onToggleLike = onToggleLike {
                        Button {
                            onToggleLike()
                        } label: {
                            Label(
                                isLiked ? "Remove from Liked" : "Add to Liked",
                                systemImage: isLiked ? "heart.slash" : "heart"
                            )
                        }
                    }
                    
                    if let onRemoveFromPlaylist = onRemoveFromPlaylist {
                        Divider()
                        
                        Button(role: .destructive) {
                            onRemoveFromPlaylist()
                        } label: {
                            Label("Remove from Playlist", systemImage: "trash")
                        }
                    }
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
