//
//  LastPlayedSongManager.swift
//  Wavify
//
//  Manages saving/loading last played song data to App Groups container
//  Uses FILE-BASED storage instead of UserDefaults for better reliability
//

import Foundation
import WidgetKit
import UIKit

/// Manages the last played song state shared between app and widget
@MainActor
class LastPlayedSongManager {
    static let shared = LastPlayedSongManager()
    
    // MARK: - App Group Configuration
    
    /// App Group identifier shared between app and widget
    static let appGroupIdentifier = "group.com.gaurav.WavifyApp"
    
    /// File names
    private enum FileNames {
        static let lastPlayedSong = "lastPlayedSong.json"
        static let cachedThumbnail = "cachedThumbnail.data"
    }
    
    /// App Group container URL
    private let containerURL: URL?

    /// Track the last cached thumbnail URL to avoid redundant downloads
    private var lastCachedThumbnailUrl: String?
    
    private init() {
        containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
        if containerURL == nil {
            Logger.warning("Failed to get App Group container URL: \(Self.appGroupIdentifier)", category: .playback)
        }
    }
    
    // MARK: - File URLs
    
    private var songDataURL: URL? {
        containerURL?.appendingPathComponent(FileNames.lastPlayedSong)
    }
    
    private var thumbnailURL: URL? {
        containerURL?.appendingPathComponent(FileNames.cachedThumbnail)
    }
    
    // MARK: - Save Methods
    
    /// Save the current song state to shared storage (with playback position)
    func saveCurrentSong(_ song: Song, isPlaying: Bool, currentTime: Double = 0, totalDuration: Double = 0) {
        let sharedData = SharedSongData(
            from: song,
            isPlaying: isPlaying,
            currentTime: currentTime,
            totalDuration: totalDuration
        )
        

        
        saveSharedData(sharedData)
        
        // Also cache the thumbnail data for offline widget display
        cacheThumbnail(from: song.thumbnailUrl)
    }
    
    /// Update play state and current time
    func updatePlaybackState(isPlaying: Bool, currentTime: Double) {
        guard var data = loadSharedData() else { return }
        data.isPlaying = isPlaying
        data.currentTime = currentTime
        saveSharedData(data)
    }
    
    /// Update only the play state (for play/pause without position change)
    func updatePlayState(isPlaying: Bool) {
        guard var data = loadSharedData() else { return }
        data.isPlaying = isPlaying
        saveSharedData(data)
    }
    
    /// Update only the current time (for periodic saves)
    func updateCurrentTime(_ time: Double) {
        guard var data = loadSharedData() else { return }
        data.currentTime = time
        saveSharedData(data, reloadWidget: false) // Don't reload widget for time updates
    }
    
    /// Save shared data to App Group file
    private func saveSharedData(_ data: SharedSongData, reloadWidget: Bool = true) {
        guard let fileURL = songDataURL else {
            Logger.error("App Group container URL is nil!", category: .playback, error: nil)
            return
        }
        
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: .atomic)
            

            
            // Notify widget to refresh (only for significant changes)
            if reloadWidget {
                WidgetCenter.shared.reloadAllTimelines()

            }
        } catch {
            Logger.error("Failed to save SharedSongData to file", category: .playback, error: error)
        }
    }
    
    // MARK: - Load Methods
    
    /// Load the last played song data from shared storage
    func loadSharedData() -> SharedSongData? {
        guard let fileURL = songDataURL else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(SharedSongData.self, from: data)
        } catch {
            // File might not exist yet - that's OK
            return nil
        }
    }
    
    /// Load cached thumbnail image data
    func loadCachedThumbnail() -> Data? {
        guard let fileURL = thumbnailURL else { return nil }
        return try? Data(contentsOf: fileURL)
    }
    
    // MARK: - Thumbnail Caching
    
    /// Cache thumbnail image data for offline widget display (downscaled for widget)
    private func cacheThumbnail(from urlString: String) {
        guard let url = URL(string: urlString),
              let fileURL = thumbnailURL else { return }

        // Skip download if we already cached this exact thumbnail
        if urlString == lastCachedThumbnailUrl { return }
        lastCachedThumbnailUrl = urlString

        Task.detached(priority: .userInitiated) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Downscale image to avoid widget archival size limits
                if let originalImage = UIImage(data: data),
                   let resizedImage = Self.resizeImage(originalImage, maxSize: 200),
                   let resizedData = resizedImage.jpegData(compressionQuality: 0.8) {
                    try resizedData.write(to: fileURL, options: .atomic)
                } else {
                    // Fallback: save original if resize fails
                    try data.write(to: fileURL, options: .atomic)
                }

                // Reload widget now that the new thumbnail is saved
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                // Silently fail - widget will use placeholder
            }
        }
    }
    
    /// Resize image to fit within maxSize while maintaining aspect ratio
    private nonisolated static func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        
        // Only resize if image is larger than maxSize
        guard ratio < 1 else { return image }
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Clear Methods
    
    /// Clear all saved data (for logout/reset)
    func clearSavedData() {
        if let songURL = songDataURL {
            try? FileManager.default.removeItem(at: songURL)
        }
        if let thumbURL = thumbnailURL {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
