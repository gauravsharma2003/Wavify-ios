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
            
            // Mini Player
            VStack(spacing: 0) {
                Spacer()
                
                if audioPlayer.currentSong != nil {
                    MiniPlayer(audioPlayer: audioPlayer) {
                        navigationManager.showNowPlaying = true
                    }
                    .padding(.bottom, 58) // Tab bar height + extra spacing
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.keyboard)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: audioPlayer.currentSong != nil)
        }
        .overlay {
            if navigationManager.showNowPlaying {
                NowPlayingView(audioPlayer: audioPlayer, navigationManager: navigationManager)
            }
        }
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
