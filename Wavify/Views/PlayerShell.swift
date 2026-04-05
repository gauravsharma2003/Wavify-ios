//
//  PlayerShell.swift
//  Wavify
//
//  Apple Music-style bottom sheet player.
//  Single expansion value (0=mini, 1=full) drives morphing art + content crossfade.
//  Full player translates down as a sheet during drag. Art docks to mini on collapse.
//

import SwiftUI
import SwiftData

struct PlayerShell: View {
    @Bindable var audioPlayer: AudioPlayer
    var navigationManager: NavigationManager
    @State private var sharePlayManager = SharePlayManager.shared
    @State private var crossfadeSettings = CrossfadeSettings.shared
    @State private var equalizerManager = EqualizerManager.shared

    @Environment(\.modelContext) private var modelContext
    @Environment(\.layoutContext) private var layout

    // MARK: - Full player state

    @State private var showQueue = false
    @State private var likedSongsStore = LikedSongsStore.shared

    private var isLiked: Bool {
        guard let videoId = audioPlayer.currentSong?.videoId else { return false }
        return likedSongsStore.isLiked(videoId)
    }

    // Dynamic colors — extracted once per song, persists across expand/collapse
    @State private var primaryColor: Color = Color(white: 0.15)
    @State private var secondaryColor: Color = Color(white: 0.08)
    @State private var accentColor: Color = Color(white: 0.03)

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
    @State private var showShareCard = false
    @State private var showAirPlayPicker = false
    var sleepTimerManager: SleepTimerManager = .shared

    // Horizontal swipe (track change in full player)
    @State private var horizontalSwipeOffset: CGFloat = 0
    @State private var isTransitioningTrack: Bool = false

    // Mini player progress ring
    @State private var displayedProgress: Double = 0
    @State private var isProgressTransitioning: Bool = false
    @State private var lastMiniSongId: String = ""

    // Sheet drag state
    @State private var isDragging: Bool = false
    @State private var gestureDirectionLock: GestureAxis? = nil
    @State private var passedDismissThreshold: Bool = false
    @State private var dragStartedInSeekZone: Bool = false

    private enum GestureAxis {
        case horizontal, vertical
    }

    /// The sheetTranslation value at which dismiss commits
    private let dismissThreshold: CGFloat = 120

    // Mini player horizontal swipe
    @State private var miniDragOffset: CGFloat = 0
    private let miniSwipeThreshold: CGFloat = 50

    private var actualProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(1.0, max(0.0, audioPlayer.currentTime / audioPlayer.duration))
    }

    // MARK: - Sizes

    private var miniHeight: CGFloat { layout.isRegularWidth ? 82 : 70 }
    private var miniRingSize: CGFloat { layout.isRegularWidth ? 62 : 50 }
    private var miniArtSize: CGFloat { layout.isRegularWidth ? 50 : 40 }
    private var miniTitleFont: CGFloat { layout.isRegularWidth ? 17 : 14 }
    private var miniArtistFont: CGFloat { layout.isRegularWidth ? 15 : 12 }
    private var miniPlayIcon: CGFloat { layout.isRegularWidth ? 26 : 22 }
    private var miniNextIcon: CGFloat { layout.isRegularWidth ? 20 : 16 }
    private var miniTapSize: CGFloat { layout.isRegularWidth ? 52 : 44 }

    private var fullTitleFont: CGFloat { layout.isRegularWidth ? 30 : 24 }
    private var fullArtistFont: CGFloat { layout.isRegularWidth ? 21 : 17 }
    private var controlIcon: CGFloat { layout.isRegularWidth ? 24 : 20 }
    private var controlIconLarge: CGFloat { layout.isRegularWidth ? 26 : 22 }
    private var controlTapSize: CGFloat { layout.isRegularWidth ? 52 : 44 }
    private var handleButtonSize: CGFloat { layout.isRegularWidth ? 52 : 46 }

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

    // MARK: - Device corner radius

    /// Apple Music-style: corners match the device screen radius when sheet is dragged down
    private var deviceCornerRadius: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let screen = windowScene.screen as? UIScreen else { return 55 }
        // _displayCornerRadius is private API; use a safe default matching modern iPhones
        let value = screen.value(forKey: "_displayCornerRadius") as? CGFloat
        return value ?? 55
    }

    private func sheetCornerRadius(for geometry: GeometryProxy) -> CGFloat {
        let translation = navigationManager.sheetTranslation
        guard translation > 0 else { return 0 }
        // Ramp up to device corner radius over the first 60pt of drag
        let progress = min(1, translation / 60)
        return deviceCornerRadius * progress
    }

    // MARK: - Rubber band

    private func rubberBand(_ offset: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard offset > 0 else { return 0 }
        return (1.0 - (1.0 / ((offset * coefficient / dimension) + 1.0))) * dimension
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let expansion = navigationManager.playerExpansion
            let artExp = navigationManager.artExpansion
            let screenH = geometry.size.height
            let screenW = geometry.size.width
            let miniBottomOffset = 49 + bottomSafeAreaInset + 8

            ZStack {
                // LAYER 1: Full player background + controls — fades with playerExpansion (fast)
                fullPlayerLayer(expansion: expansion, geometry: geometry)
                    .offset(y: navigationManager.sheetTranslation)
                    .allowsHitTesting(expansion > 0.5)
                    .simultaneousGesture(sheetDragGesture(screenHeight: screenH, screenWidth: screenW))

                // LAYER 2: Mini player bar — appears based on artExpansion (when art arrives)
                miniPlayerBar(expansion: artExp, geometry: geometry, miniBottomOffset: miniBottomOffset)

                // LAYER 3: Morphing album art — driven by artExpansion (slow, smooth flight)
                morphingAlbumArt(expansion: artExp, geometry: geometry, miniBottomOffset: miniBottomOffset)
                    .opacity(showLyrics && artExp > 0.5 ? 0 : Double(min(1, artExp / 0.15)))
                    .allowsHitTesting(false)
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
        .sheet(isPresented: $showShareCard) {
            if let song = audioPlayer.currentSong {
                ShareCardSheet(
                    song: song,
                    initialLyricsState: lyricsState,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor,
                    audioDuration: audioPlayer.duration
                )
            }
        }
        .background {
            AirPlayRoutePickerView(showPicker: $showAirPlayPicker)
                .frame(width: 1, height: 1)
                .opacity(0.001)
        }
        .animation(.easeInOut(duration: 0.35), value: lyricsExpanded)
        // Track change handling
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
            extractColorsFromArtwork()
            checkLikeStatus()
            if showLyrics {
                lyricsState = .loading
                fetchLyrics()
            } else {
                lyricsState = .idle
            }
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

    // MARK: - Layer 1: Full Player (background + controls, no art)

    @ViewBuilder
    private func fullPlayerLayer(expansion: CGFloat, geometry: GeometryProxy) -> some View {
        let contentOpacity = Double(min(1, expansion * 2.5)) // fades out: 0.4→0

        ZStack {
            // Background — flat color always present, breathing gradient fades in for lyrics
            primaryColor
            BreathingBackground(
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                accentColor: accentColor
            )
            .opacity(showLyrics ? 1 : 0)

            // Controls
            fullContent(geometry: geometry, shellWidth: geometry.size.width)
                .opacity(contentOpacity)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipShape(RoundedRectangle(cornerRadius: sheetCornerRadius(for: geometry), style: .continuous))
        .opacity(Double(min(1, expansion * 2))) // sheet fades: 0.5→0
    }

    // MARK: - Layer 2: Morphing Album Art

    @ViewBuilder
    private func morphingAlbumArt(expansion: CGFloat, geometry: GeometryProxy, miniBottomOffset: CGFloat) -> some View {
        if let song = audioPlayer.currentSong {
            let screenH = geometry.size.height
            let screenW = geometry.size.width
            let iPadLandscape = layout.isIPad && layout.isLandscape
            let sheetTranslation = navigationManager.sheetTranslation

            // Full state: top portion of screen
            let fullW = iPadLandscape ? screenW / 2 : screenW
            let fullH = screenH * 0.6
            let fullCenterX = iPadLandscape ? fullW / 2 : screenW / 2
            let fullCenterY = fullH / 2 + sheetTranslation // moves with sheet during drag

            // Mini state: inside the progress ring on the mini bar
            let miniCenterX: CGFloat = 16 + 16 + miniRingSize / 2
            let miniCenterY: CGFloat = screenH - miniBottomOffset - miniHeight / 2

            // Interpolate position, size, shape
            let artCenterX = miniCenterX + (fullCenterX - miniCenterX) * expansion
            let artCenterY = miniCenterY + (fullCenterY - miniCenterY) * expansion
            let artW = miniArtSize + (fullW - miniArtSize) * expansion
            let artH = miniArtSize + (fullH - miniArtSize) * expansion

            // Corner radius: circle when mini, matches device corners when sheet is dragged, 0 when fully expanded
            let miniCorner = miniArtSize / 2
            let dragCorner = sheetCornerRadius(for: geometry) // ramps up to ~55pt during drag
            let fullCorner = max(0, dragCorner) // 0 when not dragging, device corners when dragging
            let artCorner = miniCorner + (fullCorner - miniCorner) * expansion

            ProgressiveAlbumArt(
                lowQualityUrl: ImageUtils.upscaleThumbnail(song.thumbnailUrl, targetSize: 226),
                highQualityUrl: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
            )
            .id(song.id)
            .frame(width: artW, height: artH)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .overlay(alignment: .bottom) {
                // Gradient: visible only when expanded
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.35),
                        .init(color: primaryColor.opacity(0.4), location: 0.55),
                        .init(color: primaryColor.opacity(0.85), location: 0.75),
                        .init(color: primaryColor, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(Double(expansion))
            }
            .offset(x: horizontalSwipeOffset * expansion)
            .position(x: artCenterX, y: artCenterY)
        }
    }

    // MARK: - Layer 3: Mini Player Bar

    @ViewBuilder
    private func miniPlayerBar(expansion: CGFloat, geometry: GeometryProxy, miniBottomOffset: CGFloat) -> some View {
        let miniOpacity = Double(max(0, 1 - expansion * 5)) // visible below expansion 0.2

        if audioPlayer.currentSong != nil {
            VStack {
                Spacer()
                miniContent
                    .frame(width: geometry.size.width - 32, height: miniHeight)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    .padding(.bottom, miniBottomOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(miniOpacity)
            .allowsHitTesting(expansion < 0.1)
            .onTapGesture {
                if expansion < 0.1 {
                    navigationManager.expandPlayer()
                }
            }
        }
    }

    // MARK: - Sheet Drag Gesture

    private func sheetDragGesture(screenHeight: CGFloat, screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard navigationManager.playerExpansion > 0.9 else { return }
                guard !showLyrics else { return }

                if !isDragging {
                    // Check if drag started in the seek bar / controls zone (bottom ~35%)
                    let seekZoneTop = screenHeight * 0.65
                    if value.startLocation.y > seekZoneTop {
                        dragStartedInSeekZone = true
                        return
                    }

                    let verticalAmount = abs(value.translation.height)
                    let horizontalAmount = abs(value.translation.width)
                    guard verticalAmount > 15 || horizontalAmount > 15 else { return }
                    isDragging = true
                    gestureDirectionLock = horizontalAmount > verticalAmount ? .horizontal : .vertical
                }

                guard !dragStartedInSeekZone else { return }

                switch gestureDirectionLock {
                case .horizontal:
                    // Track swipe (only in art area, above seek zone)
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9, blendDuration: 0)) {
                        horizontalSwipeOffset = value.translation.width * 0.6
                    }
                    return
                case .vertical:
                    break // handled below
                case nil:
                    return
                }


                if value.translation.height > 0 {
                    let rubberBanded = rubberBand(value.translation.height, dimension: screenHeight, coefficient: 0.9)
                    navigationManager.sheetTranslation = rubberBanded

                    // Haptic at dismiss threshold
                    let isPastThreshold = rubberBanded > dismissThreshold
                    if isPastThreshold && !passedDismissThreshold {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        passedDismissThreshold = true
                    } else if !isPastThreshold && passedDismissThreshold {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        passedDismissThreshold = false
                    }
                } else {
                    navigationManager.sheetTranslation = 0
                }
            }
            .onEnded { value in
                let lockedDir = gestureDirectionLock
                let wasInSeekZone = dragStartedInSeekZone
                isDragging = false
                gestureDirectionLock = nil
                passedDismissThreshold = false
                dragStartedInSeekZone = false

                guard !wasInSeekZone else { return }

                if lockedDir == .horizontal {
                    // Track change via horizontal swipe
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let threshold: CGFloat = 80
                    let velocityThreshold: CGFloat = 300

                    if value.translation.width < -threshold || velocity < -velocityThreshold {
                        performTrackTransition(direction: .next, screenWidth: screenWidth)
                    } else if value.translation.width > threshold || velocity > velocityThreshold {
                        performTrackTransition(direction: .previous, screenWidth: screenWidth)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            horizontalSwipeOffset = 0
                        }
                    }
                    return
                }

                guard lockedDir == .vertical else { return }

                let velocity = value.predictedEndTranslation.height - value.translation.height
                let translation = navigationManager.sheetTranslation

                if translation > dismissThreshold || velocity > 300 {
                    navigationManager.collapsePlayer()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        navigationManager.sheetTranslation = 0
                    }
                }
            }
    }

    // MARK: - Track Transition

    private enum SwipeDirection { case next, previous }

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
                // Album art + progress ring — art is a real child so it moves with swipes
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        .frame(width: miniRingSize, height: miniRingSize)

                    MiniProgressRing(
                        audioPlayer: audioPlayer,
                        ringSize: miniRingSize,
                        displayedProgress: displayedProgress,
                        isProgressTransitioning: isProgressTransitioning
                    )

                    // Art inside the ring — fades out as morphing overlay fades in
                    ProgressiveAlbumArt(
                        lowQualityUrl: ImageUtils.upscaleThumbnail(song.thumbnailUrl, targetSize: 226),
                        highQualityUrl: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
                    )
                    .id(song.id)
                    .frame(width: miniArtSize, height: miniArtSize)
                    .clipShape(Circle())
                    .opacity(Double(max(0, 1 - navigationManager.artExpansion / 0.15)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: miniTitleFont, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: miniArtistFont))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: miniPlayIcon, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: miniTapSize, height: miniTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sharePlayManager.isGuest)
                .opacity(sharePlayManager.isGuest ? 0.4 : 1.0)

                Button {
                    Task { await audioPlayer.playNext() }
                } label: {
                    Image(systemName: "chevron.forward.dotted.chevron.forward")
                        .font(.system(size: miniNextIcon, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: miniTapSize - 8, height: miniTapSize)
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
        let screenW = geometry.size.width
        let screenH = geometry.size.height
        let hPad = max(16, screenW * 0.06)
        let controlsGap = screenH * 0.022

        if lyricsExpanded && showLyrics {
            VStack(spacing: 0) {
                expandedLyricsContent(geometry: geometry)
            }
            .contentShape(Rectangle())
        } else if layout.isIPad && layout.isLandscape {
            HStack(spacing: 0) {
                Spacer().frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    songInfoView
                    Spacer().frame(height: screenH * 0.035)
                    VStack(spacing: controlsGap) {
                        middleActionRow(screenWidth: screenW / 2)
                        progressView
                        controlsView(screenWidth: screenW / 2, screenHeight: screenH)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, hPad)
            }
            .padding(.bottom, bottomSafeAreaInset + screenH * 0.014)
            .contentShape(Rectangle())
        } else {
            VStack(spacing: 0) {
                if showLyrics {
                    LyricsView(
                        lyricsState: lyricsState,
                        currentTime: audioPlayer.currentTime,
                        isPlaying: audioPlayer.isPlaying,
                        onSeek: { time in audioPlayer.seek(to: time) },
                        isExpanded: lyricsExpanded,
                        onExpandToggle: {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                lyricsExpanded = true
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, topSafeAreaInset + 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Spacer()
                }

                songInfoView
                    .offset(x: horizontalSwipeOffset)

                Spacer().frame(height: controlsGap * 1.2)
                middleActionRow(screenWidth: screenW)
                Spacer().frame(height: controlsGap * 1.2)
                progressView
                Spacer().frame(height: controlsGap)
                controlsView(screenWidth: screenW, screenHeight: screenH)
            }
            .padding(.horizontal, hPad)
            .padding(.bottom, bottomSafeAreaInset + screenH * 0.014)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Middle Action Row

    private func middleActionRow(screenWidth: CGFloat) -> some View {
        ZStack {
            HStack(spacing: 16) {
                Button { shareSong() } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: controlIcon, weight: .medium))
                        .foregroundStyle(.white)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toggleLike()
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: controlIcon, weight: .medium))
                        .foregroundStyle(isLiked ? .red : .white)
                        .likeButtonAnimation(trigger: isLiked)
                }
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: controlIcon, weight: .medium))
                        .foregroundStyle(sharePlayManager.isGuest ? .white.opacity(0.4) : .white)
                }
                .disabled(sharePlayManager.isGuest)
            }
            .padding(.horizontal, 24)
            .frame(height: handleButtonSize + 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { showLyrics.toggle() }
                    if showLyrics, let song = audioPlayer.currentSong,
                       song.id != lastLyricsFetchedSongId {
                        fetchLyrics()
                    }
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: controlIconLarge, weight: .medium))
                        .foregroundStyle(showLyrics ? .cyan : .white)
                        .frame(width: handleButtonSize, height: handleButtonSize)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                Spacer()
            }

            HStack {
                Spacer()
                moreMenuButton
            }
        }
        .padding(.horizontal, 4)
    }

    private var moreMenuButton: some View {
        Menu {
            if let song = audioPlayer.currentSong {
                if let artistId = song.artistId {
                    Button {
                        navigationManager.collapsePlayer()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            navigationManager.navigateToArtist(id: artistId, name: song.artist, thumbnail: song.thumbnailUrl)
                        }
                    } label: { Label("Go to Artist", systemImage: "music.mic") }
                }
                if let albumId = song.albumId {
                    Button {
                        navigationManager.collapsePlayer()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            navigationManager.navigateToAlbum(id: albumId, name: song.title, artist: song.artist, thumbnail: song.thumbnailUrl)
                        }
                    } label: { Label("Go to Album", systemImage: "opticaldisc") }
                }
            }
            Divider()
            Button { showAddToPlaylist = true } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
            Button { toggleLike() } label: { Label(isLiked ? "Unlike Song" : "Like Song", systemImage: isLiked ? "heart.slash" : "heart") }
            Divider()
            Button {
                if sleepTimerManager.isActive { showActiveSleepSheet = true } else { showSleepSheet = true }
            } label: {
                Label(sleepTimerManager.isActive ? "Sleep Timer (Active)" : "Sleep Timer",
                      systemImage: sleepTimerManager.isActive ? "moon.fill" : "moon")
            }
            Toggle(isOn: Binding(
                get: { equalizerManager.settings.selectedPreset != .flat },
                set: { if $0 { showEqualizerSheet = true } else { equalizerManager.applyPreset(.flat); equalizerManager.save() } }
            )) { Label("Equalizer", systemImage: "slider.horizontal.3") }
            Toggle(isOn: Binding(
                get: { crossfadeSettings.isEnabled && !audioPlayer.isAirPlayActive },
                set: { crossfadeSettings.isEnabled = $0 }
            )) {
                Label(audioPlayer.isAirPlayActive ? "Crossfade (AirPlay)" : "Crossfade", systemImage: "wave.3.right")
            }
            .disabled(sharePlayManager.isGuest || audioPlayer.isAirPlayActive)
            Divider()
            Button {
                navigationManager.collapsePlayer()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { navigationManager.navigateToListenTogether() }
            } label: {
                Label(sharePlayManager.isSessionActive ? "Listen Together (Active)" : "Listen Together", systemImage: "shareplay")
            }
            ControlGroup {
                Button { startRadio() } label: { Label("Start Radio", systemImage: "dot.radiowaves.left.and.right") }.disabled(sharePlayManager.isGuest)
                Button { createStation() } label: { Label("Save Radio", systemImage: "music.note.square.stack.fill") }.disabled(sharePlayManager.isGuest)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: controlIconLarge, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: handleButtonSize, height: handleButtonSize)
                .rotationEffect(.degrees(90))
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Song Info

    private var songInfoView: some View {
        VStack(alignment: .center, spacing: 6) {
            if let song = audioPlayer.currentSong {
                Text(song.title)
                    .font(.system(size: fullTitleFont, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    if let artistId = song.artistId {
                        navigationManager.navigateToArtist(id: artistId, name: song.artist, thumbnail: song.thumbnailUrl)
                    }
                } label: {
                    Text(song.artist)
                        .font(.system(size: fullArtistFont))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(song.artistId == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

    private func controlsView(screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        HStack(spacing: screenWidth * 0.07) {
            Button { showAirPlayPicker = true } label: {
                Image(systemName: "airplayaudio")
                    .font(.system(size: controlIcon, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: controlTapSize, height: controlTapSize)
            }
            Button { Task { await audioPlayer.playPrevious() } } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: controlIconLarge, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: controlTapSize, height: controlTapSize)
            }
            .disabled(sharePlayManager.isGuest).opacity(sharePlayManager.isGuest ? 0.4 : 1.0)
            Button { audioPlayer.togglePlayPause() } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: layout.isRegularWidth ? 38 : 32, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: layout.isRegularWidth ? 84 : 72, height: layout.isRegularWidth ? 84 : 72)
            }
            .disabled(sharePlayManager.isGuest).opacity(sharePlayManager.isGuest ? 0.4 : 1.0)
            Button { Task { await audioPlayer.playNext() } } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: controlIconLarge, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: controlTapSize, height: controlTapSize)
            }
            .disabled(sharePlayManager.isGuest).opacity(sharePlayManager.isGuest ? 0.4 : 1.0)
            Button { audioPlayer.toggleLoopMode() } label: {
                Image(systemName: audioPlayer.loopMode.icon)
                    .font(.system(size: controlIcon, weight: .medium))
                    .foregroundColor(audioPlayer.loopMode == .none ? .gray : .white)
                    .frame(width: controlTapSize, height: controlTapSize)
            }
            .disabled(sharePlayManager.isGuest).opacity(sharePlayManager.isGuest ? 0.4 : 1.0)
        }
    }

    // MARK: - Expanded Lyrics

    private func expandedLyricsContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            LyricsView(
                lyricsState: lyricsState,
                currentTime: audioPlayer.currentTime,
                isPlaying: audioPlayer.isPlaying,
                onSeek: { time in audioPlayer.seek(to: time) },
                isExpanded: true,
                onExpandToggle: { withAnimation(.easeInOut(duration: 0.35)) { lyricsExpanded = false } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, topSafeAreaInset)

            SlimProgressView(
                audioPlayer: audioPlayer,
                isCrossfadeActive: CrossfadeSettings.shared.isEnabled && audioPlayer.crossfadeEngine?.isActive == true
            )
            .padding(.horizontal, 20).padding(.bottom, 8)

            compactSongInfoView
                .padding(.horizontal, 20)
                .padding(.bottom, bottomSafeAreaInset + 14)
        }
    }

    private var compactSongInfoView: some View {
        let compactArt: CGFloat = layout.isRegularWidth ? 64 : 48
        return HStack(spacing: 12) {
            if let song = audioPlayer.currentSong {
                CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Rectangle().fill(.white.opacity(0.1))
                    }
                }
                .frame(width: compactArt, height: compactArt)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.system(size: layout.isRegularWidth ? 20 : 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(song.artist).font(.system(size: layout.isRegularWidth ? 16 : 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { audioPlayer.togglePlayPause() } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: controlIcon, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: controlTapSize, height: controlTapSize)
                }
                Button { Task { await audioPlayer.playNext() } } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: controlIcon - 2, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: controlTapSize, height: controlTapSize)
                }
            }
        }
    }

    // MARK: - Mini Progress Ring

    private struct MiniProgressRing: View {
        let audioPlayer: AudioPlayer
        let ringSize: CGFloat
        let displayedProgress: Double
        let isProgressTransitioning: Bool

        @State private var lastSyncTime: Double = 0
        @State private var lastSyncDate: Date = Date()

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0/10, paused: !audioPlayer.isPlaying)) { timeline in
                let smoothProgress: Double = {
                    guard !isProgressTransitioning else { return displayedProgress }
                    guard audioPlayer.duration > 0 else { return 0 }
                    if audioPlayer.isPlaying {
                        let elapsed = timeline.date.timeIntervalSince(lastSyncDate)
                        let predicted = lastSyncTime + elapsed
                        return min(1.0, max(0.0, predicted / audioPlayer.duration))
                    } else {
                        return min(1.0, max(0.0, audioPlayer.currentTime / audioPlayer.duration))
                    }
                }()
                Circle()
                    .trim(from: 0, to: smoothProgress)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: ringSize, height: ringSize)
                    .rotationEffect(.degrees(-90))
            }
            .onChange(of: audioPlayer.currentTime) { _, newValue in
                lastSyncTime = newValue
                lastSyncDate = Date()
            }
            .onAppear {
                lastSyncTime = audioPlayer.currentTime
                lastSyncDate = Date()
            }
        }
    }

    // MARK: - Progressive Album Art

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
                        .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay { Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(.white.opacity(0.5)) }
                }
            }
            .task { if !isHighQualityLoaded { await loadHighQuality() } }
        }

        private func loadHighQuality() async {
            guard let url = URL(string: highQualityUrl) else { return }
            if let cached = await ImageCache.shared.image(for: url) {
                await MainActor.run { displayImage = Image(uiImage: cached); isHighQualityLoaded = true }
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await ImageCache.shared.store(uiImage, for: url)
                    await MainActor.run { displayImage = Image(uiImage: uiImage); isHighQualityLoaded = true }
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
            let colors: ColorExtractor.ExtractedColors = await ColorExtractor.extractColors(from: url)
            withAnimation(.easeInOut(duration: 0.6)) {
                primaryColor = colors.primary
                secondaryColor = colors.secondary
                accentColor = colors.accent
            }
        }
    }

    private func checkLikeStatus() { likedSongsStore.loadIfNeeded(context: modelContext) }

    private func toggleLike() {
        guard let song = audioPlayer.currentSong else { return }
        likedSongsStore.toggleLike(for: song, in: modelContext)
    }

    private func fetchLyrics() {
        guard let song = audioPlayer.currentSong else { return }
        lyricsState = .loading
        lastLyricsFetchedSongId = song.id
        Task {
            let result = await LyricsService.shared.fetchLyrics(title: song.title, artist: song.artist, duration: audioPlayer.duration)
            if let synced = result.syncedLyrics, !synced.isEmpty {
                lyricsState = .synced(synced)
            } else if let plain = result.plainLyrics, !plain.isEmpty {
                lyricsState = .plain(plain)
            } else {
                lyricsState = .notFound
                withAnimation(.easeInOut(duration: 0.3)) { showLyrics = false; lyricsExpanded = false }
            }
        }
    }

    private func shareSong() {
        showShareCard = true
    }

    private func startRadio() {
        guard let currentSong = audioPlayer.currentSong else { return }
        Task {
            do {
                let similarVideos = try await NetworkManager.shared.getRelatedSongs(videoId: currentSong.videoId)
                guard !similarVideos.isEmpty else { return }
                let radioSongs = Array(similarVideos.prefix(49)).map { Song(from: $0) }
                audioPlayer.replaceUpcomingQueue(with: radioSongs)
                ToastManager.shared.show(icon: "dot.radiowaves.left.and.right", text: "Radio mode. Your queue's in good hands.")
            } catch { Logger.error("Failed to start radio", category: .network, error: error) }
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
                    let currentLocalSong = LocalSong(videoId: currentSong.videoId, title: currentSong.title, artist: currentSong.artist, thumbnailUrl: currentSong.thumbnailUrl, duration: currentSong.duration, orderIndex: 0)
                    modelContext.insert(currentLocalSong)
                    playlist.songs.append(currentLocalSong)
                    for (index, video) in similarSongsToAdd.enumerated() {
                        let localSong = LocalSong(videoId: video.id, title: video.name, artist: video.artist, thumbnailUrl: video.thumbnailUrl, duration: video.duration, orderIndex: index + 1)
                        modelContext.insert(localSong)
                        playlist.songs.append(localSong)
                    }
                    try? modelContext.save()
                    Task { await audioPlayer.playAlbum(songs: songsToPlay, startIndex: 0) }
                    navigationManager.collapsePlayer()
                    NavigationManager.shared.navigateToLocalPlaylist(playlist)
                }
            } catch { Logger.error("Failed to create station", category: .network, error: error) }
        }
    }

    private func preloadPlayerImage(for song: Song) async {
        let highQualityUrl = ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
        guard let url = URL(string: highQualityUrl) else { return }
        if await ImageCache.shared.image(for: url) != nil { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) { await ImageCache.shared.store(image, for: url) }
        } catch { }
    }
}

// MARK: - Queue View

struct QueueView: View {
    var audioPlayer: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    private var crossfadeEnabled: Bool { CrossfadeSettings.shared.isEnabled }
    private var crossfadeActive: Bool { audioPlayer.crossfadeEngine?.isActive == true }
    private var upcomingSongs: [(offset: Int, element: Song)] {
        guard audioPlayer.currentIndex + 1 < audioPlayer.queue.count else { return [] }
        return Array(audioPlayer.queue.dropFirst(audioPlayer.currentIndex + 1).enumerated())
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(audioPlayer.queue.prefix(audioPlayer.currentIndex + 1).enumerated()), id: \.element.id) { index, song in
                    CompactSongRow(song: song, isCurrentlyPlaying: index == audioPlayer.currentIndex) {
                        Task { await audioPlayer.playFromQueue(at: index) }
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .moveDisabled(true).deleteDisabled(true)

                if crossfadeEnabled && !upcomingSongs.isEmpty {
                    CrossfadeIndicatorRow(isActive: crossfadeActive)
                }

                ForEach(upcomingSongs, id: \.element.id) { localIndex, song in
                    let queueIndex = audioPlayer.currentIndex + 1 + localIndex
                    let isLockedForCrossfade = crossfadeActive && localIndex == 0
                    SwipeableQueueRow(
                        song: song, isNextSong: localIndex == 0, isLocked: isLockedForCrossfade,
                        onRemove: { audioPlayer.removeFromQueue(at: queueIndex) },
                        onPlayNext: {
                            if localIndex == 0 { Task { await audioPlayer.playFromQueue(at: queueIndex) } }
                            else { _ = audioPlayer.moveToPlayNext(fromIndex: queueIndex) }
                        },
                        onTap: { Task { await audioPlayer.playFromQueue(at: queueIndex) } }
                    )
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .moveDisabled(isLockedForCrossfade).deleteDisabled(true)
                }
                .onMove(perform: handleUpcomingMove)
            }
            .listStyle(.plain).listRowSpacing(0).scrollContentBackground(.hidden).background(.clear)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Up Next").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private func handleUpcomingMove(from source: IndexSet, to destination: Int) {
        let base = audioPlayer.currentIndex + 1
        let adjustedSource = IndexSet(source.map { $0 + base })
        let adjustedDestination = destination + base
        if adjustedDestination <= audioPlayer.currentIndex {
            audioPlayer.moveQueueItem(fromOffsets: adjustedSource, toOffset: audioPlayer.currentIndex + 1)
            Task { await audioPlayer.playFromQueue(at: audioPlayer.currentIndex + 1) }
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
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: isNextSong ? "play.fill" : "text.insert").font(.system(size: 18, weight: .semibold))
                        Text(isNextSong ? "Play Now" : "Up Next").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white).padding(.trailing, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.green).opacity(offset < 0 ? 1 : 0)

                HStack {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                        Text("Remove").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white).padding(.leading, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.85, green: 0.18, blue: 0.28)).opacity(offset > 0 ? 1 : 0)
            }

            HStack(spacing: 12) {
                CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Rectangle().fill(Color(white: 0.15))
                    }
                }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                    Text(song.artist).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
                if isLocked { Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(.clear)
            .offset(x: offset).contentShape(Rectangle())
            .onTapGesture { onTap() }
            .highPriorityGesture(
                DragGesture(minimumDistance: isLocked ? .infinity : 20)
                    .onChanged { value in
                        if !isDragging {
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            isDragging = true
                        }
                        guard isDragging else { return }
                        offset = value.translation.width
                        let isPastThreshold = abs(offset) >= threshold
                        if isPastThreshold && !passedThreshold { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); passedThreshold = true }
                        else if !isPastThreshold && passedThreshold { UIImpactFeedbackGenerator(style: .light).impactOccurred(); passedThreshold = false }
                    }
                    .onEnded { value in
                        guard isDragging else { isDragging = false; return }
                        let finalOffset = value.translation.width
                        if finalOffset < -threshold {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = -500 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPlayNext(); offset = 0 }
                        } else if finalOffset > threshold {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 500 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onRemove(); offset = 0 }
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { offset = 0 }
                        }
                        isDragging = false; passedThreshold = false
                    }
            )
        }
        .clipped()
    }
}

// MARK: - Crossfade Indicator Row

private struct CrossfadeIndicatorRow: View {
    let isActive: Bool
    @State private var shimmerPhase: CGFloat = -1
    private var pipeColor: Color { .white.opacity(isActive ? 0.4 : 0.15) }
    private let pipeX: CGFloat = 34

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(pipeColor).frame(width: 1.5).padding(.leading, pipeX - 0.75)
            HStack(spacing: 6) {
                Image(systemName: "wave.3.right").font(.system(size: 11, weight: .medium))
                Text("Crossfade").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.45))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18))
                    .overlay { if isActive {
                        RoundedRectangle(cornerRadius: 8).fill(
                            LinearGradient(colors: [.clear, .white.opacity(0.15), .clear],
                                           startPoint: UnitPoint(x: shimmerPhase, y: 0.5),
                                           endPoint: UnitPoint(x: shimmerPhase + 0.6, y: 0.5)))
                    }}
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(isActive ? 0.25 : 0.1), lineWidth: 1) }
            }
            .padding(.leading, pipeX - 16)
        }
        .frame(height: 80).frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear).listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .onChange(of: isActive) { if isActive { startShimmer() } }
        .onAppear { if isActive { startShimmer() } }
    }

    private func startShimmer() {
        shimmerPhase = -1
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmerPhase = 1.4 }
    }
}
