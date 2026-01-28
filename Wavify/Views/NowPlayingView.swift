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

    @Environment(\.modelContext) private var modelContext
    @State private var showQueue = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isLiked = false
    @State private var showArtist = false // Deprecated/Unused but kept for safety if referenced? No, removing unwired state.
    
    // Dynamic colors extracted from album art
    @State private var primaryColor: Color = Color(white: 0.15)
    @State private var secondaryColor: Color = Color(white: 0.05)
    @State private var lastSongId: String = ""
    
    // Lyrics state
    @State private var showLyrics = false
    @State private var lyricsState: LyricsState = .idle
    @State private var lastLyricsFetchedSongId: String = ""
    @State private var lyricsExpanded = false
    
    // Add to playlist state
    @State private var showAddToPlaylist = false
    
    // Swipe gesture state for song navigation
    @State private var horizontalSwipeOffset: CGFloat = 0
    @State private var isTransitioningTrack: Bool = false
    
    // Sleep timer state
    @State private var showSleepSheet = false
    @State private var showActiveSleepSheet = false
    var sleepTimerManager: SleepTimerManager = .shared
    
    // Equalizer state
    @State private var showEqualizerSheet = false
    
    // AirPlay state
    @State private var showAirPlayPicker = false
    
    // Constants for bottom sheet behavior
    private let maxCornerRadius: CGFloat = 40
    
    // Animation state
    @State private var isVisible: Bool = false
    
    var navigationManager: NavigationManager = .shared // Default for preview compatibility
    
    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let dragProgress = min(1.0, dragOffset / 200.0)
            let dynamicCornerRadius = maxCornerRadius * dragProgress
            
            ZStack {
                // Tap area to dismiss (invisible, no dimming)
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissSheet()
                    }
                
                // Bottom sheet content
                sheetContent(geometry: geometry, dragProgress: dragProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        dynamicBackground
                            .ignoresSafeArea()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: dynamicCornerRadius, style: .continuous))
                    .offset(y: isVisible ? dragOffset : geometry.size.height)
                    .gesture(
                        lyricsExpanded ? nil : dragGesture(screenHeight: screenHeight)
                    )
                    .ignoresSafeArea()
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isVisible)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isVisible = true
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView(audioPlayer: audioPlayer)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let song = audioPlayer.currentSong {
                AddToPlaylistSheet(song: song)
            }
        }
        .sheet(isPresented: $showSleepSheet) {
            SleepTimerSheet { minutes in
                sleepTimerManager.start(minutes: minutes)
            }
        }
        .sheet(isPresented: $showActiveSleepSheet) {
            SleepTimerActiveSheet(sleepTimerManager: sleepTimerManager)
        }
        .sheet(isPresented: $showEqualizerSheet) {
            EqualizerSheet()
        }
        .background {
            // Hidden AirPlay Picker for programmatic triggering
            AirPlayRoutePickerView(showPicker: $showAirPlayPicker)
                .frame(width: 1, height: 1)
                .opacity(0.001)
        }
        .animation(.easeInOut(duration: 0.35), value: lyricsExpanded)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Drag Gesture
    
    private func dragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                let translation = value.translation.height
                if translation > 0 {
                    // Apply resistance curve for smooth feel
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1, blendDuration: 0)) {
                        dragOffset = translation
                    }
                }
            }
            .onEnded { value in
                isDragging = false
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let shouldDismiss = dragOffset > screenHeight * 0.25 || velocity > 400
                
                if shouldDismiss {
                    dismissSheet()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    // MARK: - Combined Gesture for Track Navigation and Sheet Dismiss
    
    private func combinedSwipeGesture(screenWidth: CGFloat, screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .global)
            .onChanged { value in
                guard !isTransitioningTrack else { return }
                
                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)
                
                // Determine direction on first significant movement
                if !isDragging {
                    isDragging = true
                    // Lock to the dominant direction
                }
                
                // Horizontal swipe for track change
                if horizontalAmount > verticalAmount && horizontalAmount > 20 {
                    // Apply resistance for smooth feel
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9, blendDuration: 0)) {
                        horizontalSwipeOffset = value.translation.width * 0.6
                    }
                    // Reset vertical offset
                    if dragOffset != 0 {
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1, blendDuration: 0)) {
                            dragOffset = 0
                        }
                    }
                }
                // Vertical drag for dismiss
                else if verticalAmount > horizontalAmount && value.translation.height > 0 {
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1, blendDuration: 0)) {
                        dragOffset = value.translation.height
                    }
                    // Reset horizontal offset
                    if horizontalSwipeOffset != 0 {
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9, blendDuration: 0)) {
                            horizontalSwipeOffset = 0
                        }
                    }
                }
            }
            .onEnded { value in
                isDragging = false
                guard !isTransitioningTrack else { return }
                
                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)
                
                // Handle horizontal swipe ending
                if horizontalAmount > verticalAmount {
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let threshold: CGFloat = 80
                    let velocityThreshold: CGFloat = 300
                    
                    // Swipe left (next track)
                    if value.translation.width < -threshold || velocity < -velocityThreshold {
                        performTrackTransition(direction: .next, screenWidth: screenWidth)
                    }
                    // Swipe right (previous track)
                    else if value.translation.width > threshold || velocity > velocityThreshold {
                        performTrackTransition(direction: .previous, screenWidth: screenWidth)
                    }
                    // Not enough to trigger, snap back
                    else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            horizontalSwipeOffset = 0
                        }
                    }
                }
                // Handle vertical drag ending (dismiss)
                else {
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    let shouldDismiss = dragOffset > screenHeight * 0.25 || velocity > 400
                    
                    if shouldDismiss {
                        dismissSheet()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
            }
    }
    
    private enum SwipeDirection {
        case next, previous
    }
    
    private func performTrackTransition(direction: SwipeDirection, screenWidth: CGFloat) {
        isTransitioningTrack = true
        
        // Animate off-screen in swipe direction
        let exitOffset: CGFloat = direction == .next ? -screenWidth : screenWidth
        
        withAnimation(.easeOut(duration: 0.2)) {
            horizontalSwipeOffset = exitOffset
        }
        
        // Change track after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task {
                if direction == .next {
                    await audioPlayer.playNext()
                } else {
                    await audioPlayer.playPrevious()
                }
            }
            
            // Reset offset from opposite side for new track entrance
            let entranceOffset: CGFloat = direction == .next ? screenWidth : -screenWidth
            horizontalSwipeOffset = entranceOffset
            
            // Animate new track in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                horizontalSwipeOffset = 0
            }
            
            // Allow new swipes after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTransitioningTrack = false
            }
        }
    }
    
    // MARK: - Sheet Content
    
    private func sheetContent(geometry: GeometryProxy, dragProgress: Double) -> some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // Header with buttons
                dragHandle
                    .padding(.top, geometry.safeAreaInsets.top)
                
                if lyricsExpanded && showLyrics {
                    // Expanded Lyrics Mode
                    expandedLyricsContent(geometry: geometry)
                } else {
                    // Normal Mode - Main Content
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // Swipeable container for album art and song info
                        VStack(spacing: 0) {
                            // Album Art or Lyrics
                            albumArtView(geometry: geometry)
                            
                            Spacer()
                                .frame(height: 32)
                            
                            // Song Info (included in swipeable area)
                            songInfoView
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle()) // Make entire area respond to gestures
                        .offset(x: horizontalSwipeOffset)
                        .gesture(
                            showLyrics ? nil : combinedSwipeGesture(screenWidth: geometry.size.width, screenHeight: geometry.size.height)
                        )
                        
                        Spacer()
                        
                        VStack(spacing: 32) {
                            // Progress Bar
                            progressView
                            
                            // Controls
                            controlsView
                            
                            // Additional Controls - restored spacing
                            HStack(spacing: 30) {
                                // Sleep Timer Button
                                Button {
                                    if sleepTimerManager.isActive {
                                        showActiveSleepSheet = true
                                    } else {
                                        showSleepSheet = true
                                    }
                                } label: {
                                    Image(systemName: sleepTimerManager.isActive ? "moon.fill" : "moon")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(sleepTimerManager.isActive ? .cyan : .white)
                                        .frame(width: 44, height: 44)
                                }
                                
                                // Share Button
                                Button {
                                    shareSong()
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                }
                                
                                // AirPlay Button
                                Button {
                                    showAirPlayPicker = true
                                } label: {
                                    Image(systemName: "airplayaudio")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                }
                                
                                // Lyrics Button
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showLyrics.toggle()
                                    }
                                    if showLyrics, let song = audioPlayer.currentSong,
                                       song.id != lastLyricsFetchedSongId {
                                        fetchLyrics()
                                    }
                                } label: {
                                    Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                }
                                
                                // More Button (Three Dots)
                                Menu {
                                    // Add to Playlist
                                    Button {
                                        showAddToPlaylist = true
                                    } label: {
                                        Label("Add to Playlist", systemImage: "text.badge.plus")
                                    }
                                    
                                    // Equalizer
                                    Button {
                                        showEqualizerSheet = true
                                    } label: {
                                        Label("Equalizer", systemImage: "slider.horizontal.3")
                                    }
                                    
                                    Divider()
                                    
                                    // Go to Artist
                                    if let song = audioPlayer.currentSong, let artistId = song.artistId {
                                        Button {
                                            dismissSheet()
                                            // Delay navigation to allow sheet dismiss
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                navigationManager.navigateToArtist(
                                                    id: artistId,
                                                    name: song.artist,
                                                    thumbnail: song.thumbnailUrl
                                                )
                                            }
                                        } label: {
                                            Label("Go to Artist", systemImage: "music.mic")
                                        }
                                    }
                                    
                                    // Like/Unlike
                                    Button {
                                        toggleLike()
                                    } label: {
                                        Label(isLiked ? "Unlike Song" : "Like Song", systemImage: isLiked ? "heart.slash" : "heart")
                                    }
                                    
                                    Divider()
                                    
                                    // Similar Songs
                                    Section("Create from similar songs") {
                                        Button {
                                            createStation()
                                        } label: {
                                            Label("Create Station", systemImage: "radio")
                                        }
                                    }
                                    
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .rotationEffect(.degrees(90))
                                }
                            }
                            .padding(.top, -16)
                        }
                        
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60) // Push up slightly from bottom edge
                }
            }
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Dismiss Helper
    
    private func dismissSheet() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isVisible = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            navigationManager.showNowPlaying = false
            dragOffset = 0
        }
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
            .padding(.bottom, 30)
        }
    }
    
    // MARK: - Compact Song Info (for expanded mode)
    
    private var compactSongInfoView: some View {
        HStack(spacing: 12) {
            // Small album art
            if let song = audioPlayer.currentSong {
                CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
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
        // Move database query to background to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            let descriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId && $0.isLiked == true }
            )
            let liked = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
            await MainActor.run {
                self.isLiked = liked
            }
        }
    }
    
    private func toggleLike() {
        guard let song = audioPlayer.currentSong else { return }
        
        // Move database operations to background to avoid blocking UI
        Task.detached(priority: .userInitiated) {
            let videoId = song.videoId
            let descriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId }
            )
            
            let isLiked: Bool
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
            
            await MainActor.run {
                self.isLiked = isLiked
            }
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
                dismissSheet()
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
        .padding(.top, 8)
        .padding(.horizontal, 20)
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
                    // Album Art - Progressive loading (low quality first, then high quality)
                    ProgressiveAlbumArt(
                        lowQualityUrl: song.thumbnailUrl,
                        highQualityUrl: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
                    )
                    .id(song.id) // Force view recreation when song changes
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
    
    // MARK: - Progressive Album Art
    
    /// Loads low quality image first, then upgrades to high quality
    /// Uses SYNC cache check on init so image animates with sheet
    private struct ProgressiveAlbumArt: View {
        let lowQualityUrl: String
        let highQualityUrl: String
        
        @State private var displayImage: Image?
        @State private var isHighQualityLoaded = false
        
        // Check cache synchronously on init
        init(lowQualityUrl: String, highQualityUrl: String) {
            self.lowQualityUrl = lowQualityUrl
            self.highQualityUrl = highQualityUrl
            
            // SYNC check: Try high quality cache first
            if let url = URL(string: highQualityUrl),
               let cached = ImageCache.shared.memoryCachedImage(for: url) {
                _displayImage = State(initialValue: Image(uiImage: cached))
                _isHighQualityLoaded = State(initialValue: true)
            }
            // SYNC check: Fall back to low quality cache
            else if let url = URL(string: lowQualityUrl),
                    let cached = ImageCache.shared.memoryCachedImage(for: url) {
                _displayImage = State(initialValue: Image(uiImage: cached))
                _isHighQualityLoaded = State(initialValue: false)
            }
        }
        
        var body: some View {
            ZStack {
                // Display image or placeholder
                if let image = displayImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Placeholder only if no image cached
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.2), Color(white: 0.1)],
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
            }
            .task {
                // Only load if not already loaded in init
                if !isHighQualityLoaded {
                    await loadHighQuality()
                }
            }
        }
        
        private func loadHighQuality() async {
            guard let url = URL(string: highQualityUrl) else { return }
            
            // Check disk cache
            if let cached = await ImageCache.shared.image(for: url) {
                await MainActor.run {
                    displayImage = Image(uiImage: cached)
                    isHighQualityLoaded = true
                }
                return
            }
            
            // Load from network
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await ImageCache.shared.store(uiImage, for: url)
                    await MainActor.run {
                        displayImage = Image(uiImage: uiImage)
                        isHighQualityLoaded = true
                    }
                }
            } catch {
                // Keep current image on error
            }
        }
    }
    
    private var albumPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.1)],
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
            // Like Button (moved from additional controls)
            // Like Button (moved from additional controls)
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                toggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isLiked ? .red : .secondary)
                    .likeButtonAnimation(trigger: isLiked)
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
            }
        }
    }
    
    // MARK: - Additional Controls
    
    private var additionalControlsView: some View {
        HStack(spacing: 30) {
            // Like Button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                toggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isLiked ? .red : .white)
                    .frame(width: 44, height: 44)
                    .likeButtonAnimation(trigger: isLiked)
            }
            
            // Share Button
            Button {
                shareSong()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            
            // AirPlay Button
            AirPlayRoutePickerView()
                .frame(width: 44, height: 44)
            
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
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(showLyrics ? .white : .white.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            
            // Add to Playlist Button
            Button {
                showAddToPlaylist = true
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
        }
        // Removed top padding to push icons up
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
    
    // MARK: - Sharing
    
    private func shareSong() {
        guard let song = audioPlayer.currentSong else { return }
        
        let shareURL = "https://gauravsharma2003.github.io/wavifyapp/song/\(song.videoId)"
        let shareText = "\(song.title) by \(song.artist)"
        
        var activityItems: [Any] = [shareText]
        if let url = URL(string: shareURL) {
            activityItems.append(url)
        }
        
        // Create activity items on main thread (UI operation)
        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // Find and present view controller on main thread - UI must be on main thread
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Similiar Songs Station
    
    private func createStation() {
        guard let currentSong = audioPlayer.currentSong else { return }
        
        Task {
            // Fetch similar songs
            do {
                let similarVideos = try await NetworkManager.shared.getRelatedSongs(videoId: currentSong.videoId)
                
                guard !similarVideos.isEmpty else { return }
                
                // Limit to 49 similar songs (current song + 49 = 50 total)
                let similarSongsToAdd = Array(similarVideos.prefix(49))
                
                // Create Song array with current song first, then similar songs
                var songsToPlay: [Song] = [currentSong]
                songsToPlay.append(contentsOf: similarSongsToAdd.map { Song(from: $0) })
                
                await MainActor.run {
                    // Create Local Playlist
                    let playlistName = "MIX: \(currentSong.title)"
                    let playlist = LocalPlaylist(name: playlistName, thumbnailUrl: currentSong.thumbnailUrl)
                    modelContext.insert(playlist)
                    
                    // Add current song as first item in playlist
                    let currentLocalSong = LocalSong(
                        videoId: currentSong.videoId,
                        title: currentSong.title,
                        artist: currentSong.artist,
                        thumbnailUrl: currentSong.thumbnailUrl,
                        duration: currentSong.duration,
                        orderIndex: 0
                    )
                    modelContext.insert(currentLocalSong)
                    playlist.songs.append(currentLocalSong)
                    
                    // Create Local Songs for similar tracks
                    for (index, video) in similarSongsToAdd.enumerated() {
                        let localSong = LocalSong(
                            videoId: video.id,
                            title: video.name,
                            artist: video.artist,
                            thumbnailUrl: video.thumbnailUrl,
                            duration: video.duration,
                            orderIndex: index + 1  // Start from 1 since current song is 0
                        )
                        modelContext.insert(localSong)
                        playlist.songs.append(localSong)
                    }
                    
                    // Start playback immediately (starting from current song at index 0)
                    Task {
                        await audioPlayer.playAlbum(songs: songsToPlay, startIndex: 0)
                    }
                    
                    // Dismiss and Navigate to new playlist
                    dismissSheet()
                    
                    // Small delay to ensure sheet dismisses before navigation push?
                    // NavigationManager handles transition, but switching tabs + pushing might be better handled if sequential.
                    // However, `navigateToLocalPlaylist` sets state synchronously.
                    NavigationManager.shared.navigateToLocalPlaylist(playlist)
                }
                
            } catch {
                Logger.error("Failed to create station", category: .network, error: error)
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
