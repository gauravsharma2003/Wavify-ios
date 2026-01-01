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
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
