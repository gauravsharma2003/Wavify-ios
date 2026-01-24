//
//  MusicPlayerIntents.swift
//  WavifyWidget
//
//  App Intents for widget playback controls
//

import AppIntents
import WidgetKit

// MARK: - Play/Pause Intent

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Play/Pause"
    static var description = IntentDescription("Toggles playback in Wavify")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        // Open the app with deep link to toggle playback
        // The app will handle this in the background
        if let url = URL(string: "wavify://control/toggle") {
            await openURL(url)
        }
        return .result()
    }
    
    @MainActor
    private func openURL(_ url: URL) async {
        // Use the URL to trigger the app
        // iOS will handle this via the deep link
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [.universalLinksOnly: false]) { _ in
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Next Track Intent

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track in Wavify")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "wavify://control/next") {
            await openURL(url)
        }
        return .result()
    }
    
    @MainActor
    private func openURL(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [.universalLinksOnly: false]) { _ in
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Previous Track Intent

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Goes to the previous track in Wavify")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "wavify://control/previous") {
            await openURL(url)
        }
        return .result()
    }
    
    @MainActor
    private func openURL(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [.universalLinksOnly: false]) { _ in
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
