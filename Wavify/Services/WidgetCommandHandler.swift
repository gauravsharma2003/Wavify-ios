//
//  WidgetCommandHandler.swift
//  Wavify
//
//  Handles widget commands via App Group shared UserDefaults
//

import Foundation
import UIKit
import Combine

/// Commands that can be sent from widget to app
enum WidgetCommand: String, Codable {
    case toggle
    case next
    case previous
    case play
    case pause
}

/// Handles inter-process communication from widget to app
@MainActor
class WidgetCommandHandler {
    static let shared = WidgetCommandHandler()
    
    private let appGroupIdentifier = "group.com.gaurav.Wavify"
    private let commandKey = "pendingWidgetCommand"
    private let commandTimestampKey = "pendingWidgetCommandTimestamp"
    
    private var timer: Timer?
    private var lastProcessedTimestamp: TimeInterval = 0
    
    private init() {}
    
    /// Start polling for widget commands
    func startListening() {
        // Check immediately
        checkForCommand()
        
        // Poll every 0.5 seconds for commands
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForCommand()
            }
        }
        
        // Also listen for app becoming active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForCommand()
            }
        }
    }
    
    /// Stop listening for widget commands
    func stopListening() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Check for and process any pending commands
    private func checkForCommand() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        // Check if there's a new command
        let timestamp = defaults.double(forKey: commandTimestampKey)
        guard timestamp > lastProcessedTimestamp else { return }
        
        // Get the command
        guard let commandString = defaults.string(forKey: commandKey),
              let command = WidgetCommand(rawValue: commandString) else {
            return
        }
        
        // Mark as processed
        lastProcessedTimestamp = timestamp
        
        // Clear the command
        defaults.removeObject(forKey: commandKey)
        defaults.removeObject(forKey: commandTimestampKey)
        
        // Execute the command
        executeCommand(command)
    }
    
    /// Execute a widget command
    private func executeCommand(_ command: WidgetCommand) {
        let player = AudioPlayer.shared
        
        switch command {
        case .toggle:
            if player.currentSong != nil {
                player.togglePlayPause()
            } else {
                resumeLastSong()
            }
            
        case .play:
            if player.currentSong != nil {
                player.play()
            } else {
                resumeLastSong()
            }
            
        case .pause:
            player.pause()
            
        case .next:
            Task {
                await player.playNext()
            }
            
        case .previous:
            Task {
                await player.playPrevious()
            }
        }
    }
    
    /// Resume the last played song
    private func resumeLastSong() {
        if let lastSong = LastPlayedSongManager.shared.loadSharedData() {
            Task {
                await AudioPlayer.shared.loadAndPlay(videoId: lastSong.videoId)
            }
        }
    }
    
    // MARK: - Static methods for sending commands (used by widget)
    
    /// Send a command from widget to app
    static func sendCommand(_ command: WidgetCommand) {
        guard let defaults = UserDefaults(suiteName: "group.com.gaurav.Wavify") else { return }
        
        defaults.set(command.rawValue, forKey: "pendingWidgetCommand")
        defaults.set(Date().timeIntervalSince1970, forKey: "pendingWidgetCommandTimestamp")
        defaults.synchronize()
    }
}
