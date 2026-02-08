//
//  MainTabView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var audioPlayer = AudioPlayer.shared
    @State private var navigationManager = NavigationManager.shared
    @State private var lastTrackedSongId: String = ""
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $navigationManager.selectedTab) {
                HomeView(audioPlayer: audioPlayer, navigationManager: navigationManager)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                SearchView(audioPlayer: audioPlayer)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                LibraryView(audioPlayer: audioPlayer)
                    .tabItem {
                        Label("Library", systemImage: "books.vertical.fill")
                    }
                    .tag(2)
            }
            .tint(.white)
            .toolbar(navigationManager.playerExpansion > 0.95 ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.2), value: navigationManager.playerExpansion > 0.95)

            // Unified Player Shell (mini ↔ full morph)
            if audioPlayer.currentSong != nil {
                PlayerShell(audioPlayer: audioPlayer, navigationManager: navigationManager)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: audioPlayer.currentSong != nil)
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.dark)
        .onAppear {
            setupAppearance()
        }
        .onChange(of: audioPlayer.currentSong?.id) { oldValue, newValue in
            if let newValue = newValue, newValue != lastTrackedSongId {
                lastTrackedSongId = newValue
                saveToHistory()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToArtist"))) { notification in
            if let artistId = notification.userInfo?["artistId"] as? String {
                // Navigate to artist page
                navigationManager.navigateToArtist(id: artistId, name: "", thumbnail: "")
            }
        }
    }
    
    // MARK: - History Tracking
    
    private func saveToHistory() {
        guard let song = audioPlayer.currentSong else { return }
        
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
    
    private func setupAppearance() {
        // Configure Tab Bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tabBarAppearance.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        
        // Configure Navigation Bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        navBarAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        navBarAppearance.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }
}

#Preview {
    MainTabView()
}
