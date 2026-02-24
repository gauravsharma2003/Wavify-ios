//
//  WavifyApp.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import SwiftData

@main
struct WavifyApp: App {
    @State private var splashFinished = false
    @State private var animateIcon = false
    @State private var showIconOverlay = true
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LocalSong.self,
            LocalPlaylist.self,
            RecentHistory.self,
            SongPlayCount.self,
            AlbumPlayCount.self,
            ArtistPlayCount.self,
            CachedFormat.self,
            CloudConnection.self,
            CloudPlaylist.self,
            CloudTrack.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // MARK: - Splash Animation Overlay

    @ViewBuilder
    private var splashAnimationOverlay: some View {
        // y=0 = top of safe area (below Dynamic Island), so y≈22 = nav bar center
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2
            let navBarCenterY: CGFloat = 22

            // Background gradient — fills full screen via .ignoresSafeArea on itself
            LinearGradient(
                stops: [
                    .init(color: Color.brandGradientTop, location: 0),
                    .init(color: Color.brandBackground, location: 0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .opacity(animateIcon ? 0 : 1)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIcon)

            // Icon — flies from center to nav bar.
            // .animation() scoping: position + scale get spring, opacity gets a delayed fade.
            // The fade masks any size mismatch during the handoff to the real toolbar icon.
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .scaleEffect(animateIcon ? 0.22 : 1.0)
                .position(x: centerX, y: animateIcon ? navBarCenterY : centerY - 27)
                .animation(.spring(response: 0.65, dampingFraction: 0.82), value: animateIcon)
                // Opacity below the spring .animation() → gets its own curve
                .opacity(animateIcon ? 0 : 1)
                .animation(.easeOut(duration: 0.15).delay(0.25), value: animateIcon)

            // App name — fades out and drops
            Text("Wavify")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.white)
                .opacity(animateIcon ? 0 : 1)
                .offset(y: animateIcon ? 30 : 0)
                .position(x: centerX, y: centerY + 50)
                .animation(.easeOut(duration: 0.35), value: animateIcon)
        }
        .allowsHitTesting(!splashFinished)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // MainTabView mounts instantly when splash finishes (hidden behind overlay gradient)
                if splashFinished {
                    MainTabView()
                }

                // SplashView: just gradient + prewarming (no icon/text)
                if !splashFinished {
                    SplashView(isFinished: $splashFinished)
                }

                // Splash visual overlay: gradient + flying icon + text
                // Owns the gradient so it controls the entire visual transition
                if showIconOverlay {
                    splashAnimationOverlay
                }
            }
            .overlay(alignment: .top) {
                NetworkToastView()
            }
            .onChange(of: splashFinished) { _, finished in
                guard finished else { return }
                animateIcon = true
                // Reveal real toolbar icon after overlay icon has faded (0.25s delay + 0.15s fade)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    NavigationManager.shared.splashIconLanded = true
                }
                // Remove overlay after fade completes (0.3s delay + 0.15s duration)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showIconOverlay = false
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .task {
                // Configure background data manager with the shared container
                await BackgroundDataManager.shared.configure(with: sharedModelContainer)

                // Configure cached format store
                await CachedFormatStore.shared.configure(with: sharedModelContainer)

                // Configure cloud library manager
                await CloudLibraryManager.shared.configure(with: sharedModelContainer)

                // Scrape fresh visitor data (non-blocking)
                Task { await VisitorDataScraper.shared.scrape() }

                // Start listening for widget commands (Darwin notifications)
                WidgetCommandHandler.shared.startListening()
                
                // Listen for app going to background to update widget state
                setupAppLifecycleObservers()
                
                // Check for pending widget favorite tap
                checkPendingWidgetFavorite()
                
                // Pre-warm keyboard for smoother search experience
                await KeyboardManager.shared.prewarmKeyboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Check again when app becomes active (in case it was already running)
                checkPendingWidgetFavorite()
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(_ url: URL) {
        // Supports:
        // - Song playback: wavify://song/xyz123
        // - Widget controls: wavify://control/toggle, wavify://control/next, wavify://control/previous
        // - Resume: wavify://play (resume last song)
        // - Universal Links: https://gauravsharma2003.github.io/wavifyapp/song/xyz123
        
        guard url.scheme == "wavify" else {
            handleUniversalLink(url)
            return
        }
        
        let host = url.host ?? ""
        
        switch host {
        case "control":
            handleWidgetControl(url)
        case "play":
            handleResumePlayback()
        case "song":
            // wavify://song/xyz123 → host = "song", path = "/xyz123"
            if let videoId = url.pathComponents.last, !videoId.isEmpty {
                Task {
                    await AudioPlayer.shared.loadAndPlay(videoId: videoId)
                }
            }
        case "artist":
            // wavify://artist/xyz123 → navigate to artist page
            if let artistId = url.pathComponents.last, !artistId.isEmpty {
                NavigationManager.shared.navigateToArtist(id: artistId, name: "", thumbnail: "")
            }
        default:
            // Try parsing as generic path
            if let pathComponents = url.host.map({ [$0] + url.pathComponents.dropFirst() }),
               let songIndex = pathComponents.firstIndex(of: "song"),
               pathComponents.indices.contains(songIndex + 1) {
                let videoId = pathComponents[songIndex + 1]
                Task {
                    await AudioPlayer.shared.loadAndPlay(videoId: videoId)
                }
            }
        }
    }
    
    /// Handle widget control commands
    private func handleWidgetControl(_ url: URL) {
        let command = url.pathComponents.last ?? ""
        
        Task { @MainActor in
            let player = AudioPlayer.shared
            
            switch command {
            case "toggle":
                if player.currentSong != nil {
                    player.togglePlayPause()
                } else {
                    // No current song, try to resume last played
                    handleResumePlayback()
                }
            case "next":
                await player.playNext()
            case "previous":
                await player.playPrevious()
            case "play":
                if player.currentSong != nil {
                    player.play()
                } else {
                    handleResumePlayback()
                }
            case "pause":
                player.pause()
            default:
                break
            }
        }
    }
    
    /// Resume playback of last played song
    private func handleResumePlayback() {
        Task { @MainActor in
            // Check if already have a song loaded
            if AudioPlayer.shared.currentSong != nil {
                AudioPlayer.shared.play()
                return
            }
            
            // Try to load last played song from widget shared data
            if let lastSong = LastPlayedSongManager.shared.loadSharedData() {
                await AudioPlayer.shared.loadAndPlay(videoId: lastSong.videoId)
            }
        }
    }
    
    /// Handle universal links (https://...)
    private func handleUniversalLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }
        
        let pathComponents = components.path.split(separator: "/").map(String.init)
        
        if let songIndex = pathComponents.firstIndex(of: "song"),
           pathComponents.indices.contains(songIndex + 1) {
            let videoId = pathComponents[songIndex + 1]
            Task {
                await AudioPlayer.shared.loadAndPlay(videoId: videoId)
            }
        }
    }
    
    /// Setup observers for app lifecycle to update widget state
    private func setupAppLifecycleObservers() {
        // Update widget when app is about to terminate
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Set play state to paused in widget when app terminates
            LastPlayedSongManager.shared.updatePlayState(isPlaying: false)
        }
        
        // Also update when app enters background (user force quits often happens after this)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            // If not playing audio, set widget to paused state
            if !AudioPlayer.shared.isPlaying {
                LastPlayedSongManager.shared.updatePlayState(isPlaying: false)
            }
        }
    }
    
    /// Check for pending widget favorite tap and handle it
    private func checkPendingWidgetFavorite() {
        guard let defaults = UserDefaults(suiteName: "group.com.gaurav.Wavify"),
              let itemId = defaults.string(forKey: "pendingFavoriteId"),
              let itemType = defaults.string(forKey: "pendingFavoriteType"),
              !itemId.isEmpty else {
            return
        }
        
        // Clear the pending values
        defaults.removeObject(forKey: "pendingFavoriteId")
        defaults.removeObject(forKey: "pendingFavoriteType")
        
        Logger.debug("Handling widget favorite tap: \(itemType) - \(itemId)", category: .playback)
        
        Task { @MainActor in
            if itemType == "artist" {
                // Navigate to artist page
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToArtist"),
                    object: nil,
                    userInfo: ["artistId": itemId]
                )
            } else {
                // Play the song
                await AudioPlayer.shared.loadAndPlay(videoId: itemId)
            }
        }
    }

}

