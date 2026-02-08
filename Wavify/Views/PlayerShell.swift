//
//  PlayerShell.swift
//  Wavify
//
//  Unified mini-player ↔ full-player morph transition.
//  Driven by NavigationManager.playerExpansion (0 = mini, 1 = full).
//

import SwiftUI
import SwiftData

struct PlayerShell: View {
    @Bindable var audioPlayer: AudioPlayer
    var navigationManager: NavigationManager

    @Environment(\.modelContext) private var modelContext

    // MARK: - Full player state (migrated from NowPlayingView)

    @State private var showQueue = false
    @State private var isLiked = false

    // Dynamic colors
    @State private var primaryColor: Color = Color(white: 0.15)
    @State private var secondaryColor: Color = Color(white: 0.05)
    @State private var lastColorSongId: String = ""

    // Lyrics
    @State private var showLyrics = false
    @State private var lyricsState: LyricsState = .idle
    @State private var lastLyricsFetchedSongId: String = ""
    @State private var lyricsExpanded = false

    // Sheets
    @State private var showAddToPlaylist = false
    @State private var showSleepSheet = false
    @State private var showActiveSleepSheet = false
    @State private var showEqualizerSheet = false
    @State private var showAirPlayPicker = false
    var sleepTimerManager: SleepTimerManager = .shared

    // Horizontal swipe (track change)
    @State private var horizontalSwipeOffset: CGFloat = 0
    @State private var isTransitioningTrack: Bool = false

    // Mini player progress ring
    @State private var displayedProgress: Double = 0
    @State private var isProgressTransitioning: Bool = false
    @State private var lastMiniSongId: String = ""

    // Interactive drag state
    @State private var dragStartExpansion: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var gestureDirectionLock: GestureAxis? = nil

    private enum GestureAxis {
        case horizontal, vertical
    }

    // Mini player horizontal swipe
    @State private var miniDragOffset: CGFloat = 0
    private let miniSwipeThreshold: CGFloat = 50

    private var actualProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(1.0, max(0.0, audioPlayer.currentTime / audioPlayer.duration))
    }

    private var topSafeAreaInset: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return 59 }
        return window.safeAreaInsets.top
    }

    private var bottomSafeAreaInset: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return 34 }
        return window.safeAreaInsets.bottom
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let expansion = navigationManager.playerExpansion
            // geometry.size already includes safe area because ignoresSafeArea is on GeometryReader
            let screenHeight = geometry.size.height

            // Interpolated layout values
            let miniHeight: CGFloat = 70
            let height = miniHeight + (screenHeight - miniHeight) * expansion
            let hPadding = 16 * (1 - expansion)
            // Tab bar (~49pt) + home indicator (bottomSafeAreaInset) + small gap
            let miniBottomOffset = 49 + bottomSafeAreaInset + 8
            let bottomOffset = miniBottomOffset * (1 - expansion)
            let cornerRadius = 35 * (1 - expansion)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // The actual shell width (after horizontal padding)
                let shellWidth = geometry.size.width - hPadding * 2

                ZStack {
                    // Background — gradient for full player
                    backgroundLayers(expansion: expansion)

                    // Mini content — with glass applied directly
                    miniContent
                        .frame(width: shellWidth, height: miniHeight)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .opacity(Double(max(0, 1 - expansion * 3))) // fade out 0..0.33
                        .allowsHitTesting(expansion < 0.3)

                    // Full content — only in hierarchy when expanding
                    if expansion > 0.02 {
                        fullContent(geometry: geometry, shellWidth: shellWidth)
                            .opacity(Double(min(1, max(0, (expansion - 0.1) / 0.3)))) // fade in 0.1..0.4
                            .allowsHitTesting(expansion > 0.5)
                    }

                    // Morphing album art — sits on top, interpolates between mini & full positions
                    if !showLyrics {
                        morphingAlbumArt(expansion: expansion, shellHeight: height, shellWidth: shellWidth, geometry: geometry)
                    }
                }
                .frame(width: shellWidth, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(maxWidth: .infinity)
                .padding(.bottom, bottomOffset)
                .gesture(shellGesture(screenHeight: screenHeight))
                .onTapGesture {
                    if expansion < 0.1 {
                        navigationManager.expandPlayer()
                    }
                }
            }
        }
        .ignoresSafeArea(.container)
        // Sheets
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
            AirPlayRoutePickerView(showPicker: $showAirPlayPicker)
                .frame(width: 1, height: 1)
                .opacity(0.001)
        }
        .animation(.easeInOut(duration: 0.35), value: lyricsExpanded)
        // Mini progress tracking
        .onChange(of: audioPlayer.currentSong?.id) { oldId, newId in
            guard let newId, !lastMiniSongId.isEmpty, oldId != newId else {
                if let newId { lastMiniSongId = newId }
                return
            }
            isProgressTransitioning = true
            lastMiniSongId = newId
            withAnimation(.easeOut(duration: 0.25)) {
                displayedProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isProgressTransitioning = false
            }
            // Color + like + lyrics reset for full player
            extractColorsFromArtwork()
            checkLikeStatus()
            showLyrics = false
            lyricsState = .idle
        }
        .onChange(of: actualProgress) { _, newValue in
            guard !isProgressTransitioning else { return }
            displayedProgress = newValue
        }
        .onAppear {
            if let id = audioPlayer.currentSong?.id {
                lastMiniSongId = id
                displayedProgress = actualProgress
                extractColorsFromArtwork()
                checkLikeStatus()
            }
        }
        .task(id: audioPlayer.currentSong?.id) {
            if let song = audioPlayer.currentSong {
                await preloadPlayerImage(for: song)
            }
        }
    }

    // MARK: - Background Layers

    @ViewBuilder
    private func backgroundLayers(expansion: CGFloat) -> some View {
        // Dynamic gradient for full player — fades in as we expand
        ZStack {
            LinearGradient(
                colors: [primaryColor, secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.black.opacity(0.2))
        }
        .opacity(Double(expansion))
    }

    // MARK: - Morphing Album Art

    @ViewBuilder
    private func morphingAlbumArt(expansion: CGFloat, shellHeight: CGFloat, shellWidth: CGFloat, geometry: GeometryProxy) -> some View {
        if let song = audioPlayer.currentSong {
            // Mini state: 40×40 circle, positioned at left of mini player
            let miniSize: CGFloat = 40
            // Full state: large square with rounded corners
            let fullSize: CGFloat = min(shellWidth - 48, 340)
            let artSize = miniSize + (fullSize - miniSize) * expansion

            // Corner radius: circle (half size) → 24pt rounded rect
            let miniCorner = miniSize / 2
            let fullCorner: CGFloat = 24
            let artCorner = miniCorner + (fullCorner - miniCorner) * expansion

            // Offsets from center of the shell frame (shellWidth × shellHeight)
            // Mini: leading padding(16) + ring center(25) from left edge of shell
            let miniX = 16 + 25 - shellWidth / 2
            // Mini: vertically centered in the 70pt mini bar at the bottom of shell
            let miniY = shellHeight / 2 - 35

            // Full: horizontally centered (x=0), positioned below header
            let fullY = -(shellHeight / 2) + topSafeAreaInset + 4 + 54 + 36 + fullSize / 2

            let artX = miniX + (0 - miniX) * expansion
            let artY = miniY + (fullY - miniY) * expansion

            ProgressiveAlbumArt(
                lowQualityUrl: song.thumbnailUrl,
                highQualityUrl: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
            )
            .id(song.id)
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .shadow(color: .black.opacity(0.4 * Double(expansion)), radius: 24, y: 12)
            .offset(x: artX + horizontalSwipeOffset * expansion, y: artY)
            // Hidden in mini state — mini player has its own image; crossfade during transition
            .opacity(Double(min(1, expansion / 0.15)))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Shell Gesture

    private func shellGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                // Only respond when expanded (not in mini state)
                guard dragStartExpansion > 0.1 || navigationManager.playerExpansion > 0.1 else { return }
                guard !lyricsExpanded else { return }

                if !isDragging {
                    isDragging = true
                    dragStartExpansion = navigationManager.playerExpansion
                    gestureDirectionLock = nil
                }

                let verticalAmount = abs(value.translation.height)
                let horizontalAmount = abs(value.translation.width)

                // Lock direction on first significant movement
                if gestureDirectionLock == nil && (horizontalAmount > 15 || verticalAmount > 15) {
                    if horizontalAmount > verticalAmount && navigationManager.playerExpansion > 0.9 {
                        gestureDirectionLock = .horizontal
                    } else {
                        gestureDirectionLock = .vertical
                    }
                }

                switch gestureDirectionLock {
                case .horizontal:
                    // Horizontal swipe for track change (only when mostly expanded)
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9, blendDuration: 0)) {
                        horizontalSwipeOffset = value.translation.width * 0.6
                    }
                case .vertical:
                    // Vertical drag → adjust expansion
                    if value.translation.height > 0 {
                        let dragFraction = value.translation.height / screenHeight
                        let newExpansion = max(0, dragStartExpansion - dragFraction * 1.8)
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1)) {
                            navigationManager.playerExpansion = newExpansion
                        }
                    }
                case nil:
                    break
                }
            }
            .onEnded { value in
                let lockedDirection = gestureDirectionLock
                isDragging = false
                gestureDirectionLock = nil

                if lockedDirection == .horizontal && navigationManager.playerExpansion > 0.9 {
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let threshold: CGFloat = 80
                    let velocityThreshold: CGFloat = 300

                    if value.translation.width < -threshold || velocity < -velocityThreshold {
                        performTrackTransition(direction: .next, screenWidth: UIScreen.main.bounds.width)
                    } else if value.translation.width > threshold || velocity > velocityThreshold {
                        performTrackTransition(direction: .previous, screenWidth: UIScreen.main.bounds.width)
                    } else {
                        // Didn't meet threshold — snap back to center
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            horizontalSwipeOffset = 0
                        }
                    }
                    return
                }

                // Always reset horizontal offset if we ended up in vertical mode
                if horizontalSwipeOffset != 0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        horizontalSwipeOffset = 0
                    }
                }

                // Snap expansion based on position + velocity
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let current = navigationManager.playerExpansion

                if current < 0.4 || velocity > 400 {
                    navigationManager.collapsePlayer()
                } else {
                    navigationManager.expandPlayer()
                }
            }
    }

    // MARK: - Track Transition

    private enum SwipeDirection {
        case next, previous
    }

    private func performTrackTransition(direction: SwipeDirection, screenWidth: CGFloat) {
        isTransitioningTrack = true
        let exitOffset: CGFloat = direction == .next ? -screenWidth : screenWidth

        withAnimation(.easeOut(duration: 0.2)) {
            horizontalSwipeOffset = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task {
                if direction == .next {
                    await audioPlayer.playNext()
                } else {
                    await audioPlayer.playPrevious()
                }
            }
            let entranceOffset: CGFloat = direction == .next ? screenWidth : -screenWidth
            horizontalSwipeOffset = entranceOffset
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                horizontalSwipeOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isTransitioningTrack = false
            }
        }
    }

    // MARK: - Mini Content

    private var miniContent: some View {
        HStack(spacing: 12) {
            if let song = audioPlayer.currentSong {
                // Album Art with progress ring — owns its image so it moves with swipes
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: displayedProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))

                    ProgressiveAlbumArt(
                        lowQualityUrl: song.thumbnailUrl,
                        highQualityUrl: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
                    )
                    .id(song.id)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }

                // Song Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Play/Pause
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Next
                Button {
                    Task { await audioPlayer.playNext() }
                } label: {
                    Image(systemName: "chevron.forward.dotted.chevron.forward")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .offset(x: miniDragOffset)
        .gesture(miniSwipeGesture)
    }

    private var miniSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard navigationManager.playerExpansion < 0.1 else { return }
                if abs(value.translation.width) > abs(value.translation.height) {
                    let dampened = value.translation.width * 0.4
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                        miniDragOffset = max(-60, min(60, dampened))
                    }
                }
            }
            .onEnded { value in
                guard navigationManager.playerExpansion < 0.1 else { return }
                let horizontalAmount = value.translation.width

                if horizontalAmount < -miniSwipeThreshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await audioPlayer.playNext() }
                } else if horizontalAmount > miniSwipeThreshold {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await audioPlayer.playPrevious() }
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    miniDragOffset = 0
                }
            }
    }

    // MARK: - Full Content

    @ViewBuilder
    private func fullContent(geometry: GeometryProxy, shellWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Header
            dragHandle
                .padding(.top, topSafeAreaInset + 4)

            if lyricsExpanded && showLyrics {
                expandedLyricsContent(geometry: geometry)
            } else {
                VStack(spacing: 0) {
                    // Swipeable album art + song info
                    VStack(spacing: 0) {
                        albumArtView(shellWidth: shellWidth)

                        Spacer().frame(height: 24)

                        songInfoView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .offset(x: horizontalSwipeOffset)

                    // Flexible space between song info and controls
                    Spacer(minLength: 16)

                    // Controls stack
                    VStack(spacing: 24) {
                        progressView
                        controlsView
                        additionalControlsRow
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, bottomSafeAreaInset + 12)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Additional Controls Row

    private var additionalControlsRow: some View {
        HStack(spacing: 30) {
            // Sleep Timer
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
                    .sleepButtonAnimation(trigger: sleepTimerManager.isActive)
            }

            // Share
            Button { shareSong() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            // AirPlay
            Button { showAirPlayPicker = true } label: {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            // Lyrics
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showLyrics.toggle()
                }
                if showLyrics, let song = audioPlayer.currentSong,
                   song.id != lastLyricsFetchedSongId {
                    fetchLyrics()
                }
            } label: {
                Image(systemName: showLyrics ? "text.word.spacing" : "text.word.spacing")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(showLyrics ? .cyan : .white)
                    .frame(width: 44, height: 44)
            }

            // More menu
            moreMenu
        }
    }

    // MARK: - More Menu

    private var moreMenu: some View {
        Menu {
            Button {
                showAddToPlaylist = true
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }

            Button {
                showEqualizerSheet = true
            } label: {
                Label("Equalizer", systemImage: "slider.horizontal.3")
            }

            Divider()

            if let song = audioPlayer.currentSong, let artistId = song.artistId {
                Button {
                    navigationManager.collapsePlayer()
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

            Button {
                toggleLike()
            } label: {
                Label(isLiked ? "Unlike Song" : "Like Song", systemImage: isLiked ? "heart.slash" : "heart")
            }

            Divider()

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

    // MARK: - Drag Handle

    private var dragHandle: some View {
        HStack {
            Button {
                navigationManager.collapsePlayer()
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

    private func albumArtView(shellWidth: CGFloat) -> some View {
        let size = min(shellWidth - 48, 340)
        let lyricsHeight = size

        return Group {
            if let song = audioPlayer.currentSong {
                if showLyrics {
                    LyricsView(
                        lyricsState: lyricsState,
                        currentTime: audioPlayer.currentTime,
                        onSeek: { time in audioPlayer.seek(to: time) },
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
                    // Invisible placeholder — morphing art layer renders the actual image
                    Color.clear
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .contextMenu {
                            if let albumId = song.albumId {
                                Button {
                                    navigationManager.navigateToAlbum(
                                        id: albumId,
                                        name: song.title,
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
        .padding(.top, 36)
        .animation(.easeInOut(duration: 0.3), value: showLyrics)
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

    // MARK: - Progress & Controls

    private var progressView: some View {
        NowPlayingProgressSection(audioPlayer: audioPlayer)
    }

    private var controlsView: some View {
        HStack(spacing: 32) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                toggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isLiked ? .red : .secondary)
                    .likeButtonAnimation(trigger: isLiked)
            }

            GlassPlayerButton(icon: "chevron.backward.chevron.backward.dotted", size: 22) {
                Task { await audioPlayer.playPrevious() }
            }

            LargePlayButton(isPlaying: audioPlayer.isPlaying) {
                audioPlayer.togglePlayPause()
            }

            GlassPlayerButton(icon: "chevron.forward.dotted.chevron.forward", size: 22) {
                Task { await audioPlayer.playNext() }
            }

            Button {
                audioPlayer.toggleLoopMode()
            } label: {
                Image(systemName: audioPlayer.loopMode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(audioPlayer.loopMode == .none ? .gray : .white)
            }
        }
    }

    // MARK: - Expanded Lyrics

    private func expandedLyricsContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            compactSongInfoView
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)

            SlimProgressView(audioPlayer: audioPlayer)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            LyricsView(
                lyricsState: lyricsState,
                currentTime: audioPlayer.currentTime,
                onSeek: { time in audioPlayer.seek(to: time) },
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

    private var compactSongInfoView: some View {
        HStack(spacing: 12) {
            if let song = audioPlayer.currentSong {
                CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(.white.opacity(0.1))
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

    // MARK: - Progressive Album Art (kept from NowPlayingView)

    private struct ProgressiveAlbumArt: View {
        let lowQualityUrl: String
        let highQualityUrl: String

        @State private var displayImage: Image?
        @State private var isHighQualityLoaded = false

        init(lowQualityUrl: String, highQualityUrl: String) {
            self.lowQualityUrl = lowQualityUrl
            self.highQualityUrl = highQualityUrl

            if let url = URL(string: highQualityUrl),
               let cached = ImageCache.shared.memoryCachedImage(for: url) {
                _displayImage = State(initialValue: Image(uiImage: cached))
                _isHighQualityLoaded = State(initialValue: true)
            } else if let url = URL(string: lowQualityUrl),
                      let cached = ImageCache.shared.memoryCachedImage(for: url) {
                _displayImage = State(initialValue: Image(uiImage: cached))
                _isHighQualityLoaded = State(initialValue: false)
            }
        }

        var body: some View {
            ZStack {
                if let image = displayImage {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
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
                if !isHighQualityLoaded { await loadHighQuality() }
            }
        }

        private func loadHighQuality() async {
            guard let url = URL(string: highQualityUrl) else { return }
            if let cached = await ImageCache.shared.image(for: url) {
                await MainActor.run {
                    displayImage = Image(uiImage: cached)
                    isHighQualityLoaded = true
                }
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await ImageCache.shared.store(uiImage, for: url)
                    await MainActor.run {
                        displayImage = Image(uiImage: uiImage)
                        isHighQualityLoaded = true
                    }
                }
            } catch { }
        }
    }

    // MARK: - Helpers

    private func extractColorsFromArtwork() {
        guard let song = audioPlayer.currentSong,
              !song.thumbnailUrl.isEmpty,
              let url = URL(string: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)) else { return }

        Task {
            let colors = await ColorExtractor.extractColors(from: url)
            withAnimation(.easeInOut(duration: 0.6)) {
                primaryColor = colors.primary
                secondaryColor = colors.secondary
            }
        }
    }

    private func checkLikeStatus() {
        guard let song = audioPlayer.currentSong else {
            isLiked = false
            return
        }
        let videoId = song.videoId
        Task.detached(priority: .userInitiated) {
            let descriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId && $0.isLiked == true }
            )
            let liked = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
            await MainActor.run { self.isLiked = liked }
        }
    }

    private func toggleLike() {
        guard let song = audioPlayer.currentSong else { return }
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
            await MainActor.run { self.isLiked = isLiked }
        }
    }

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
            if let synced = result.syncedLyrics, !synced.isEmpty {
                lyricsState = .synced(synced)
            } else if let plain = result.plainLyrics, !plain.isEmpty {
                lyricsState = .plain(plain)
            } else {
                lyricsState = .notFound
            }
        }
    }

    private func shareSong() {
        guard let song = audioPlayer.currentSong else { return }
        let shareURL = "https://gauravsharma2003.github.io/wavifyapp/song/\(song.videoId)"
        let shareText = "\(song.title) by \(song.artist)"
        var activityItems: [Any] = [shareText]
        if let url = URL(string: shareURL) { activityItems.append(url) }

        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(activityVC, animated: true)
        }
    }

    private func createStation() {
        guard let currentSong = audioPlayer.currentSong else { return }
        Task {
            do {
                let similarVideos = try await NetworkManager.shared.getRelatedSongs(videoId: currentSong.videoId)
                guard !similarVideos.isEmpty else { return }

                let similarSongsToAdd = Array(similarVideos.prefix(49))
                var songsToPlay: [Song] = [currentSong]
                songsToPlay.append(contentsOf: similarSongsToAdd.map { Song(from: $0) })

                await MainActor.run {
                    let playlistName = "MIX: \(currentSong.title)"
                    let playlist = LocalPlaylist(name: playlistName, thumbnailUrl: currentSong.thumbnailUrl)
                    modelContext.insert(playlist)

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

                    for (index, video) in similarSongsToAdd.enumerated() {
                        let localSong = LocalSong(
                            videoId: video.id,
                            title: video.name,
                            artist: video.artist,
                            thumbnailUrl: video.thumbnailUrl,
                            duration: video.duration,
                            orderIndex: index + 1
                        )
                        modelContext.insert(localSong)
                        playlist.songs.append(localSong)
                    }

                    Task { await audioPlayer.playAlbum(songs: songsToPlay, startIndex: 0) }

                    navigationManager.collapsePlayer()
                    NavigationManager.shared.navigateToLocalPlaylist(playlist)
                }
            } catch {
                Logger.error("Failed to create station", category: .network, error: error)
            }
        }
    }

    private func preloadPlayerImage(for song: Song) async {
        let highQualityUrl = ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
        guard let url = URL(string: highQualityUrl) else { return }
        if await ImageCache.shared.image(for: url) != nil { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await ImageCache.shared.store(image, for: url)
            }
        } catch { }
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
