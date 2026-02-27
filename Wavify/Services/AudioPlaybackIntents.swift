//
//  AudioPlaybackIntents.swift
//  Wavify
//
//  Shared App Intents for audio playback control from widgets and Siri
//  AudioPlaybackIntent runs in the MAIN APP PROCESS
//
//  IMPORTANT: This file should be added to BOTH the main app AND widget targets
//  so that the intents execute in the main app's process
//

import AppIntents
import WidgetKit

// MARK: - Shared Constants

private let appGroupIdentifier = "group.com.gaurav.WavifyApp"
private let lastPlayedSongKey = "lastPlayedSong"

// MARK: - Play/Pause Intent

/// When this intent runs, iOS executes it in the main app's process
/// This gives access to AudioPlayer.shared
@available(iOS 17.0, *)
struct PlayPauseIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback in Wavify")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        #if os(iOS) && !WIDGET_EXTENSION
        // Main app - control AudioPlayer directly
        let player = AudioPlayer.shared
        
        if player.currentSong != nil {
            player.togglePlayPause()
        } else {
            // Resume last played song
            await player.resumeRestoredSession()
        }
        #else
        // Widget extension - just update shared state
        togglePlayStateInSharedData()
        #endif
        
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
    
    private func togglePlayStateInSharedData() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: lastPlayedSongKey),
              var songData = try? JSONDecoder().decode(SharedSongData.self, from: data) else {
            return
        }
        
        songData.isPlaying.toggle()
        
        if let encoded = try? JSONEncoder().encode(songData) {
            defaults.set(encoded, forKey: lastPlayedSongKey)
        }
    }
}

// MARK: - Next Track Intent

@available(iOS 17.0, *)
struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track in Wavify")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        #if os(iOS) && !WIDGET_EXTENSION
        let player = AudioPlayer.shared
        
        if player.currentSong == nil {
            await player.resumeRestoredSession()
        }
        
        await player.playNext()
        #endif
        
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Previous Track Intent

@available(iOS 17.0, *)
struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Goes to the previous track in Wavify")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        #if os(iOS) && !WIDGET_EXTENSION
        let player = AudioPlayer.shared
        
        if player.currentSong == nil {
            await player.resumeRestoredSession()
        }
        
        await player.playPrevious()
        #endif
        
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 17.0, *)
struct WavifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: [
                "Toggle playback in \(.applicationName)",
                "Play or pause \(.applicationName)"
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
        
        AppShortcut(
            intent: NextTrackIntent(),
            phrases: [
                "Next track in \(.applicationName)",
                "Skip song in \(.applicationName)"
            ],
            shortTitle: "Next Track",
            systemImageName: "forward.fill"
        )
        
        AppShortcut(
            intent: PreviousTrackIntent(),
            phrases: [
                "Previous track in \(.applicationName)",
                "Go back in \(.applicationName)"
            ],
            shortTitle: "Previous Track",
            systemImageName: "backward.fill"
        )
    }
}
