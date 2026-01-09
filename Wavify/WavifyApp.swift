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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LocalSong.self,
            LocalPlaylist.self,
            RecentHistory.self,
            SongPlayCount.self,
            AlbumPlayCount.self,
            ArtistPlayCount.self
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
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if splashFinished {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    SplashView(isFinished: $splashFinished)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                NetworkToastView()
            }
            .animation(.easeInOut(duration: 0.3), value: splashFinished)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .task {
                // Configure background data manager with the shared container
                await BackgroundDataManager.shared.configure(with: sharedModelContainer)
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(_ url: URL) {
        // Supports both:
        // - Universal Links: https://gauravsharma2003.github.io/wavifyapp/song/xyz123
        // - Custom URL Scheme: wavify://song/xyz123
        
        var videoId: String?
        
        if url.scheme == "wavify" {
            // Custom URL scheme: wavify://song/xyz123
            // host is "song", path is "/xyz123" or path components directly
            if url.host == "song" {
                // wavify://song/xyz123 → host = "song", path = "/xyz123"
                videoId = url.pathComponents.last
            } else if let pathComponents = url.host.map({ [$0] + url.pathComponents.dropFirst() }),
                      let songIndex = pathComponents.firstIndex(of: "song"),
                      pathComponents.indices.contains(songIndex + 1) {
                videoId = pathComponents[songIndex + 1]
            }
        } else {
            // Universal Links: https://...
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                return
            }
            
            let pathComponents = components.path.split(separator: "/").map(String.init)
            
            if let songIndex = pathComponents.firstIndex(of: "song"),
               pathComponents.indices.contains(songIndex + 1) {
                videoId = pathComponents[songIndex + 1]
            }
        }
        
        guard let videoId = videoId, !videoId.isEmpty else { return }
        
        Task {
            await AudioPlayer.shared.loadAndPlay(videoId: videoId)
        }
    }

}
