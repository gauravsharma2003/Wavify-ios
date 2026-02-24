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
    @State private var sharePlayManager = SharePlayManager.shared
    @State private var crossfadeSettings = CrossfadeSettings.shared

    @Environment(\.modelContext) private var modelContext

    // MARK: - Full player state (migrated from NowPlayingView)

    @State private var showQueue = false
    @State private var likedSongsStore = LikedSongsStore.shared

    private var isLiked: Bool {
        guard let videoId = audioPlayer.currentSong?.videoId else { return false }
        return likedSongsStore.isLiked(videoId)
    }

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
                .disabled(sharePlayManager.isGuest)
                .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)

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
                .disabled(sharePlayManager.isGuest)
                .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)
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
            // Go to Album + Go to Artist (renders at bottom)
            if let song = audioPlayer.currentSong {
                if let artistId = song.artistId {
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

                if let albumId = song.albumId {
                    Button {
                        navigationManager.collapsePlayer()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            navigationManager.navigateToAlbum(
                                id: albumId,
                                name: song.title,
                                artist: song.artist,
                                thumbnail: song.thumbnailUrl
                            )
                        }
                    } label: {
                        Label("Go to Album", systemImage: "opticaldisc")
                    }
                }
            }

            Divider()

            // Like + Add to Playlist
            Button {
                showAddToPlaylist = true
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }

            Button {
                toggleLike()
            } label: {
                Label(isLiked ? "Unlike Song" : "Like Song", systemImage: isLiked ? "heart.slash" : "heart")
            }

            Divider()

            // Equalizer
            Button {
                showEqualizerSheet = true
            } label: {
                Label("Equalizer", systemImage: "slider.horizontal.3")
            }

            // Crossfade (disabled for Listen Together guests)
            Toggle(isOn: Binding(
                get: { crossfadeSettings.isEnabled },
                set: { crossfadeSettings.isEnabled = $0 }
            )) {
                Label("Crossfade", systemImage: "wave.3.right")
            }
            .disabled(sharePlayManager.isGuest)

            Divider()

            // Listen Together
            Button {
                navigationManager.collapsePlayer()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    navigationManager.navigateToListenTogether()
                }
            } label: {
                Label(
                    sharePlayManager.isSessionActive ? "Listen Together (Active)" : "Listen Together",
                    systemImage: "shareplay"
                )
            }

            // Radio (renders at top, disabled for Listen Together guests)
            ControlGroup {
                Button {
                    startRadio()
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(sharePlayManager.isGuest)

                Button {
                    createStation()
                } label: {
                    Label("Save Radio", systemImage: "music.note.square.stack.fill")
                }
                .disabled(sharePlayManager.isGuest)
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

            if sharePlayManager.isSessionActive {
                HStack(spacing: 6) {
                    Image(systemName: "shareplay")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text(sharePlayManager.isHost ? "Hosting" : "Listening")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
            } else {
                Text("Now Playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(sharePlayManager.isGuest ? .white.opacity(0.4) : .white)
                    .frame(width: 46, height: 46)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(sharePlayManager.isGuest)
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
        NowPlayingProgressSection(
            audioPlayer: audioPlayer,
            isCrossfadeActive: CrossfadeSettings.shared.isEnabled && audioPlayer.crossfadeEngine?.isActive == true
        )
        .disabled(sharePlayManager.isGuest)
        .opacity(sharePlayManager.isGuest ? 0.6 : 1.0)
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
            .disabled(sharePlayManager.isGuest)
            .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)

            LargePlayButton(isPlaying: audioPlayer.isPlaying) {
                audioPlayer.togglePlayPause()
            }
            .disabled(sharePlayManager.isGuest)
            .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)

            GlassPlayerButton(icon: "chevron.forward.dotted.chevron.forward", size: 22) {
                Task { await audioPlayer.playNext() }
            }
            .disabled(sharePlayManager.isGuest)
            .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)

            Button {
                audioPlayer.toggleLoopMode()
            } label: {
                Image(systemName: audioPlayer.loopMode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(audioPlayer.loopMode == .none ? .gray : .white)
            }
            .disabled(sharePlayManager.isGuest)
            .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)
        }
    }

    // MARK: - Expanded Lyrics

    private func expandedLyricsContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            compactSongInfoView
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)

            SlimProgressView(
                audioPlayer: audioPlayer,
                isCrossfadeActive: CrossfadeSettings.shared.isEnabled && audioPlayer.crossfadeEngine?.isActive == true
            )
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
        likedSongsStore.loadIfNeeded(context: modelContext)
    }

    private func toggleLike() {
        guard let song = audioPlayer.currentSong else { return }
        likedSongsStore.toggleLike(for: song, in: modelContext)
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

    private func startRadio() {
        guard let currentSong = audioPlayer.currentSong else { return }
        Task {
            do {
                let similarVideos = try await NetworkManager.shared.getRelatedSongs(videoId: currentSong.videoId)
                guard !similarVideos.isEmpty else { return }

                let radioSongs = Array(similarVideos.prefix(49)).map { Song(from: $0) }
                audioPlayer.replaceUpcomingQueue(with: radioSongs)
                ToastManager.shared.show(
                    icon: "dot.radiowaves.left.and.right",
                    text: "Radio mode. Your queue's in good hands."
                )
            } catch {
                Logger.error("Failed to start radio", category: .network, error: error)
            }
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

                    try? modelContext.save()

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

    private var crossfadeEnabled: Bool {
        CrossfadeSettings.shared.isEnabled
    }

    private var crossfadeActive: Bool {
        audioPlayer.crossfadeEngine?.isActive == true
    }

    private var upcomingSongs: [(offset: Int, element: Song)] {
        guard audioPlayer.currentIndex + 1 < audioPlayer.queue.count else { return [] }
        return Array(audioPlayer.queue.dropFirst(audioPlayer.currentIndex + 1).enumerated())
    }

    var body: some View {
        NavigationStack {
            List {
                // Past and current songs
                ForEach(Array(audioPlayer.queue.prefix(audioPlayer.currentIndex + 1).enumerated()), id: \.element.id) { index, song in
                    CompactSongRow(
                        song: song,
                        isCurrentlyPlaying: index == audioPlayer.currentIndex
                    ) {
                        Task { await audioPlayer.playFromQueue(at: index) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .moveDisabled(true)
                .deleteDisabled(true)

                // Crossfade indicator between current and next song
                if crossfadeEnabled && !upcomingSongs.isEmpty {
                    CrossfadeIndicatorRow(isActive: crossfadeActive)
                }

                // Upcoming songs
                ForEach(upcomingSongs, id: \.element.id) { localIndex, song in
                    let queueIndex = audioPlayer.currentIndex + 1 + localIndex
                    let isLockedForCrossfade = crossfadeActive && localIndex == 0

                    SwipeableQueueRow(
                        song: song,
                        isNextSong: localIndex == 0,
                        isLocked: isLockedForCrossfade,
                        onRemove: { audioPlayer.removeFromQueue(at: queueIndex) },
                        onPlayNext: {
                            if localIndex == 0 {
                                Task { await audioPlayer.playFromQueue(at: queueIndex) }
                            } else {
                                _ = audioPlayer.moveToPlayNext(fromIndex: queueIndex)
                            }
                        },
                        onTap: { Task { await audioPlayer.playFromQueue(at: queueIndex) } }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .moveDisabled(isLockedForCrossfade)
                    .deleteDisabled(true)
                }
                .onMove(perform: handleUpcomingMove)
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.06).ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func handleUpcomingMove(from source: IndexSet, to destination: Int) {
        let base = audioPlayer.currentIndex + 1
        let adjustedSource = IndexSet(source.map { $0 + base })
        let adjustedDestination = destination + base

        if adjustedDestination <= audioPlayer.currentIndex {
            audioPlayer.moveQueueItem(fromOffsets: adjustedSource, toOffset: audioPlayer.currentIndex + 1)
            Task {
                await audioPlayer.playFromQueue(at: audioPlayer.currentIndex + 1)
            }
        } else {
            audioPlayer.moveQueueItem(fromOffsets: adjustedSource, toOffset: adjustedDestination)
        }
    }
}

// MARK: - Swipeable Queue Row

private struct SwipeableQueueRow: View {
    let song: Song
    let isNextSong: Bool
    var isLocked: Bool = false
    let onRemove: () -> Void
    let onPlayNext: () -> Void
    let onTap: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var passedThreshold = false

    private let threshold: CGFloat = 80

    var body: some View {
        ZStack {
            if !isLocked {
                // Right background (swipe left ← green: Play Next)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: isNextSong ? "play.fill" : "text.insert")
                            .font(.system(size: 18, weight: .semibold))
                        Text(isNextSong ? "Play Now" : "Up Next")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.trailing, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.green)
                .opacity(offset < 0 ? 1 : 0)

                // Left background (swipe right → red: Remove)
                HStack {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Remove")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.85, green: 0.18, blue: 0.28))
                .opacity(offset > 0 ? 1 : 0)
            }

            // Row content
            HStack(spacing: 12) {
                CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color(white: 0.15))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.06))
            .offset(x: offset)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .highPriorityGesture(
                DragGesture(minimumDistance: isLocked ? .infinity : 20)
                    .onChanged { value in
                        if !isDragging {
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            guard horizontal > vertical else { return }
                            isDragging = true
                        }
                        guard isDragging else { return }

                        offset = value.translation.width

                        let isPastThreshold = abs(offset) >= threshold
                        if isPastThreshold && !passedThreshold {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            passedThreshold = true
                        } else if !isPastThreshold && passedThreshold {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            passedThreshold = false
                        }
                    }
                    .onEnded { value in
                        guard isDragging else {
                            isDragging = false
                            return
                        }

                        let finalOffset = value.translation.width
                        if finalOffset < -threshold {
                            // Swipe left → Play Next
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = -UIScreen.main.bounds.width
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onPlayNext()
                                offset = 0
                            }
                        } else if finalOffset > threshold {
                            // Swipe right → Remove
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = UIScreen.main.bounds.width
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onRemove()
                                offset = 0
                            }
                        } else {
                            // Snap back
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                offset = 0
                            }
                        }

                        isDragging = false
                        passedThreshold = false
                    }
            )
        }
        .clipped()
    }
}

// MARK: - Crossfade Indicator Row

private struct CrossfadeIndicatorRow: View {
    let isActive: Bool  // preloading/ready/fading

    @State private var shimmerPhase: CGFloat = -1

    private var pipeColor: Color {
        .white.opacity(isActive ? 0.4 : 0.15)
    }

    // Album art center: 12px row padding + 22px (half of 44px art)
    private let pipeX: CGFloat = 34

    var body: some View {
        ZStack(alignment: .leading) {
            // Continuous pipe running full height — never breaks
            Rectangle()
                .fill(pipeColor)
                .frame(width: 1.5)
                .padding(.leading, pipeX - 0.75)

            // Crossfade box sitting on top of the pipe (z-order: drawn last = on top)
            HStack(spacing: 6) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 11, weight: .medium))
                Text("Crossfade")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.06)) // opaque base hides pipe behind box
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(isActive ? 0.12 : 0.06))
                    }
                    .overlay {
                        if isActive {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(0.15),
                                            .clear
                                        ],
                                        startPoint: UnitPoint(x: shimmerPhase, y: 0.5),
                                        endPoint: UnitPoint(x: shimmerPhase + 0.6, y: 0.5)
                                    )
                                )
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(isActive ? 0.25 : 0.1), lineWidth: 1)
                    }
            }
            .padding(.leading, pipeX - 16)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .onChange(of: isActive) {
            if isActive {
                startShimmer()
            }
        }
        .onAppear {
            if isActive {
                startShimmer()
            }
        }
    }

    private func startShimmer() {
        shimmerPhase = -1
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.4
        }
    }
}
