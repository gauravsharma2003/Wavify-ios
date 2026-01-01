//
//  NowPlayingView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import SwiftData

struct NowPlayingView: View {
    var audioPlayer: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showQueue = false
    @State private var dragOffset: CGFloat = 0
    @State private var isLiked = false
    @State private var showArtist = false // Deprecated/Unused but kept for safety if referenced? No, removing unwired state.
    
    // Dynamic colors extracted from album art
    @State private var primaryColor: Color = Color(red: 0.2, green: 0.1, blue: 0.3)
    @State private var secondaryColor: Color = Color(red: 0.1, green: 0.1, blue: 0.2)
    @State private var lastSongId: String = ""
    
    var navigationManager: NavigationManager = .shared // Default for preview compatibility
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dynamic Background
                dynamicBackground
                
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        // Drag Handle
                        dragHandle
                        
                        // Main Content
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 32) {
                                // Album Art
                                albumArtView(geometry: geometry)
                                
                                // Song Info
                                songInfoView
                                
                                // Progress Bar
                                progressView
                                
                                // Controls
                                controlsView
                                
                                // Additional Controls
                                additionalControlsView
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
        .offset(y: dragOffset)
        .sheet(isPresented: $showQueue) {
            QueueView(audioPlayer: audioPlayer)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Background
    
    private var dynamicBackground: some View {
        ZStack {
            // Base gradient from album colors
            LinearGradient(
                colors: [primaryColor, secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle overlay
            Rectangle()
                .fill(.black.opacity(0.2))
        }
        .ignoresSafeArea()
        .onChange(of: audioPlayer.currentSong?.id) { oldValue, newValue in
            if let newValue = newValue, newValue != lastSongId {
                lastSongId = newValue
                extractColorsFromArtwork()
                checkLikeStatus()
                saveToHistory()
            }
        }
        .task {
            // Extract colors on initial load
            if let songId = audioPlayer.currentSong?.id, songId != lastSongId {
                lastSongId = songId
                extractColorsFromArtwork()
                checkLikeStatus()
                saveToHistory()
            }
        }
    }
    
    // MARK: - Like & History
    
    private func checkLikeStatus() {
        guard let song = audioPlayer.currentSong else {
            isLiked = false
            return
        }
        
        let videoId = song.videoId
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId && $0.isLiked == true }
        )
        isLiked = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }
    
    private func toggleLike() {
        guard let song = audioPlayer.currentSong else { return }
        
        let videoId = song.videoId
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId }
        )
        
        if let existingSong = try? modelContext.fetch(descriptor).first {
            existingSong.isLiked.toggle()
            isLiked = existingSong.isLiked
        } else {
            // Create new LocalSong with isLiked = true
            let newSong = LocalSong(
                videoId: song.videoId,
                title: song.title,
                artist: song.artist,
                thumbnailUrl: song.thumbnailUrl,
                duration: song.duration,
                isLiked: true
            )
            modelContext.insert(newSong)
            isLiked = true
        }
    }
    
    private func saveToHistory() {
        guard let song = audioPlayer.currentSong else { return }
        
        // Check if this song was just played (avoid duplicates)
        let videoId = song.videoId
        let descriptor = FetchDescriptor<RecentHistory>(
            predicate: #Predicate { $0.videoId == videoId },
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update timestamp
            existing.playedAt = .now
        } else {
            // Create new history entry
            let history = RecentHistory(
                videoId: song.videoId,
                title: song.title,
                artist: song.artist,
                thumbnailUrl: song.thumbnailUrl,
                duration: song.duration
            )
            modelContext.insert(history)
        }
        
        // Cleanup old entries
        RecentHistory.cleanupOldEntries(in: modelContext)
    }
    
    private func extractColorsFromArtwork() {
        guard let song = audioPlayer.currentSong,
              !song.thumbnailUrl.isEmpty,
              let url = URL(string: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)) else {
            return
        }
        
        Task {
            let colors = await ColorExtractor.extractColors(from: url)
            withAnimation(.easeInOut(duration: 0.6)) {
                primaryColor = colors.primary
                secondaryColor = colors.secondary
            }
        }
    }
    
    // MARK: - Drag Handle
    
    private var dragHandle: some View {
        HStack {
            // Back Button - Glass
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            
            Spacer()
            
            Text("Now Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Queue Button - Glass
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Album Art
    
    private func albumArtView(geometry: GeometryProxy) -> some View {
        let size = min(geometry.size.width - 48, 340)
        
        return Group {
            if let song = audioPlayer.currentSong {
                // Use high-quality upscaled thumbnail for the player
                let highQualityUrl = ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
                
                AsyncImage(url: URL(string: highQualityUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        albumPlaceholder
                    @unknown default:
                        albumPlaceholder
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                .contextMenu {
                    if let albumId = song.albumId {
                        Button {
                            navigationManager.navigateToAlbum(
                                id: albumId,
                                name: song.title, // FIXME: Needs Album Name ideally
                                artist: song.artist,
                                thumbnail: song.thumbnailUrl
                            )
                        } label: {
                            Label("Go to Album", systemImage: "opticaldisc")
                        }
                    }
                    
                    if let artistId = song.artistId {
                        Button {
                            navigationManager.navigateToArtist(
                                id: artistId,
                                name: song.artist,
                                thumbnail: song.thumbnailUrl
                            )
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                        }
                    }
                }
            } else {
                albumPlaceholder
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .padding(.top, 30)
    }
    
    private var albumPlaceholder: some View {
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
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
    
    // Color extraction is now handled in dynamicBackground
    
    // MARK: - Song Info
    
    private var songInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let song = audioPlayer.currentSong {
                Text(song.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Button {
                    if let artistId = song.artistId {
                        navigationManager.navigateToArtist(
                            id: artistId,
                            name: song.artist,
                            thumbnail: song.thumbnailUrl
                        )
                    }
                } label: {
                    Text(song.artist)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(song.artistId == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        VStack(spacing: 8) {
            // Slider
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...max(audioPlayer.duration, 1)
            )
            .tint(.white)
            
            // Time Labels
            HStack {
                Text(audioPlayer.currentTime.formattedTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(audioPlayer.duration.formattedTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsView: some View {
        HStack(spacing: 32) {
            // Shuffle
            Button {
                // Toggle shuffle
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            // Previous
            GlassPlayerButton(icon: "backward.fill", size: 24) {
                Task {
                    await audioPlayer.playPrevious()
                }
            }
            
            // Play/Pause
            LargePlayButton(isPlaying: audioPlayer.isPlaying) {
                audioPlayer.togglePlayPause()
            }
            
            // Next
            GlassPlayerButton(icon: "forward.fill", size: 24) {
                Task {
                    await audioPlayer.playNext()
                }
            }
            
            // Loop Mode Toggle
            Button {
                audioPlayer.toggleLoopMode()
            } label: {
                Image(systemName: audioPlayer.loopMode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(audioPlayer.loopMode == .none ? .gray : .white)
                    .overlay(alignment: .topTrailing) {
                        if audioPlayer.loopMode == .one {
                            Text("1")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: 2, y: -2)
                        }
                    }
            }
        }
    }
    
    // MARK: - Additional Controls
    
    private var additionalControlsView: some View {
        HStack(spacing: 48) {
            // Like Button
            Button {
                toggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isLiked ? .red : .secondary)
            }
            
            // Share Button
            Button {
                // Share
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            // AirPlay Button
            Button {
                // AirPlay
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Queue View

struct QueueView: View {
    var audioPlayer: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(audioPlayer.queue.enumerated()), id: \.element.id) { index, song in
                        CompactSongRow(
                            song: song,
                            isCurrentlyPlaying: index == audioPlayer.currentIndex
                        ) {
                            Task {
                                await audioPlayer.playFromQueue(at: index)
                            }
                        }
                        
                        if index < audioPlayer.queue.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(
                Color(white: 0.06)
                    .ignoresSafeArea()
            )
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)

            }
        }
    }


#Preview {
    NowPlayingView(audioPlayer: AudioPlayer.shared)
        .preferredColorScheme(.dark)
}
