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
    @State private var isDragging: Bool = false
    @State private var isLiked = false
    @State private var showArtist = false // Deprecated/Unused but kept for safety if referenced? No, removing unwired state.
    
    // Dynamic colors extracted from album art
    @State private var primaryColor: Color = Color(red: 0.2, green: 0.1, blue: 0.3)
    @State private var secondaryColor: Color = Color(red: 0.1, green: 0.1, blue: 0.2)
    @State private var lastSongId: String = ""
    
    // Lyrics state
    @State private var showLyrics = false
    @State private var lyricsState: LyricsState = .idle
    @State private var lastLyricsFetchedSongId: String = ""
    @State private var lyricsExpanded = false
    
    var navigationManager: NavigationManager = .shared // Default for preview compatibility
    
    var body: some View {
        ZStack {
            // Dynamic Background that fills the entire screen
            dynamicBackground
                .ignoresSafeArea(.all)
            
            GeometryReader { geometry in
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        // Drag Handle (always visible)
                        dragHandle
                        
                        if lyricsExpanded && showLyrics {
                            // Expanded Lyrics Mode
                            expandedLyricsContent(geometry: geometry)
                        } else {
                            // Normal Mode - Main Content
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 32) {
                                    // Album Art or Lyrics
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
                .offset(y: lyricsExpanded ? 0 : dragOffset)
                .animation(
                    isDragging ? .none : .spring(response: 0.4, dampingFraction: 0.85, blendDuration: 0.1),
                    value: dragOffset
                )
            }
        }
        .gesture(
            lyricsExpanded ? nil : DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    isDragging = true
                    let dragAmount = value.translation.height
                    
                    if dragAmount > 0 {
                        // Apply resistance curve for smooth feel
                        let resistance = min(1.0, dragAmount / (UIScreen.main.bounds.height * 0.7))
                        let resistanceCurve = 1 - pow(1 - resistance, 2)
                        dragOffset = dragAmount * (0.4 + 0.6 * resistanceCurve)
                    }
                }
                .onEnded { value in
                    isDragging = false
                    let velocity = value.predictedEndTranslation.height
                    let dragAmount = value.translation.height
                    
                    // Enhanced dismiss logic with velocity consideration
                    let shouldDismiss = dragAmount > 120 || (dragAmount > 80 && velocity > 800)
                    
                    if shouldDismiss {
                        // Animate out with momentum
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dragOffset = UIScreen.main.bounds.height
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            dismiss()
                        }
                    } else {
                        // Smooth spring back
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .sheet(isPresented: $showQueue) {
            QueueView(audioPlayer: audioPlayer)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.35), value: lyricsExpanded)
    }
    
    // MARK: - Expanded Lyrics Content
    
    private func expandedLyricsContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Compact Song Info
            compactSongInfoView
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            
            // Progress Bar (slim version)
            slimProgressView
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            
            // Fullscreen Lyrics
            LyricsView(
                lyricsState: lyricsState,
                currentTime: audioPlayer.currentTime,
                onSeek: { time in
                    audioPlayer.seek(to: time)
                },
                isExpanded: true,
                onExpandToggle: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        lyricsExpanded = false
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Compact Song Info (for expanded mode)
    
    private var compactSongInfoView: some View {
        HStack(spacing: 12) {
            // Small album art
            if let song = audioPlayer.currentSong {
                AsyncImage(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(.white.opacity(0.1))
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Play/Pause button
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
    
    // MARK: - Slim Progress View (for expanded mode)
    
    private var slimProgressView: some View {
        VStack(spacing: 4) {
            // Slim Slider
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...max(audioPlayer.duration, 1)
            )
            .tint(.white)
            .scaleEffect(y: 0.8)
            
            // Time Labels
            HStack {
                Text(audioPlayer.currentTime.formattedTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(audioPlayer.duration.formattedTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
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
                
                // Reset lyrics state when song changes
                showLyrics = false
                lyricsState = .idle
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
        VStack(spacing: 12) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.3))
                .frame(width: 40, height: 6)
                .padding(.top, 8)
            
            HStack {
                // Back Button - Glass
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
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
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Album Art
    
    private func albumArtView(geometry: GeometryProxy) -> some View {
        let size = min(geometry.size.width - 48, 340)
        // Lyrics container can be taller than album art
        let lyricsHeight = size 
        
        return Group {
            if let song = audioPlayer.currentSong {
                if showLyrics {
                    // Lyrics View
                    LyricsView(
                        lyricsState: lyricsState,
                        currentTime: audioPlayer.currentTime,
                        onSeek: { time in
                            audioPlayer.seek(to: time)
                        },
                        isExpanded: lyricsExpanded,
                        onExpandToggle: {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                lyricsExpanded = true
                            }
                        }
                    )
                    .frame(width: size, height: lyricsHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // Album Art
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
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                }
            } else {
                albumPlaceholder
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .padding(.top, 32)
        .animation(.easeInOut(duration: 0.3), value: showLyrics)
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
        HStack(spacing: 36) {
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
            
            // Lyrics Button
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showLyrics.toggle()
                }
                // Fetch lyrics if showing and not already fetched for this song
                if showLyrics, let song = audioPlayer.currentSong,
                   song.id != lastLyricsFetchedSongId {
                    fetchLyrics()
                }
            } label: {
                Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(showLyrics ? .white : .secondary)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Lyrics Fetching
    
    private func fetchLyrics() {
        guard let song = audioPlayer.currentSong else { return }
        
        lyricsState = .loading
        lastLyricsFetchedSongId = song.id
        
        Task {
            let result = await LyricsService.shared.fetchLyrics(
                title: song.title,
                artist: song.artist,
                duration: audioPlayer.duration
            )
            
            // Update lyrics state based on result
            if let synced = result.syncedLyrics, !synced.isEmpty {
                lyricsState = .synced(synced)
            } else if let plain = result.plainLyrics, !plain.isEmpty {
                lyricsState = .plain(plain)
            } else {
                lyricsState = .notFound
            }
        }
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
