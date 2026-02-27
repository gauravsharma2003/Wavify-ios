//
//  AppIntent.swift
//  widget
//
//  Widget intents using system MediaPlaybackIntent
//  iOS routes these to the active audio session via MPRemoteCommandCenter
//

import AppIntents
import WidgetKit

// MARK: - Play/Pause Intent

struct PlayPauseIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles playback in Wavify")
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Next Track Intent

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track")
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Previous Track Intent

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Goes to the previous track")
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Open Favorite Intent (opens app to play song or view artist)

struct OpenFavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Favorite"
    static var description = IntentDescription("Opens a favorite in Wavify")
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Item ID")
    var itemId: String
    
    @Parameter(title: "Item Type")
    var itemType: String
    
    init() {
        self.itemId = ""
        self.itemType = ""
    }
    
    init(itemId: String, itemType: String) {
        self.itemId = itemId
        self.itemType = itemType
    }
    
    func perform() async throws -> some IntentResult {
        // Store the request in UserDefaults for the app to handle
        if let defaults = UserDefaults(suiteName: "group.com.gaurav.WavifyApp") {
            defaults.set(itemId, forKey: "pendingFavoriteId")
            defaults.set(itemType, forKey: "pendingFavoriteType")
            defaults.synchronize()
        }
        return .result()
    }
}

// MARK: - Shared Song Data (for widget display only)

struct SharedSongData: Codable {
    let videoId: String
    let title: String
    let artist: String
    let thumbnailUrl: String
    let duration: String
    var isPlaying: Bool
    var currentTime: Double
    var totalDuration: Double
    var artistId: String?
    var albumId: String?
}
