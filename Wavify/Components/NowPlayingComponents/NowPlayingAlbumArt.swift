//
//  NowPlayingAlbumArt.swift
//  Wavify
//
//  Album art components for NowPlayingView
//

import SwiftUI

// MARK: - Progressive Album Art

/// Loads low quality image first, then upgrades to high quality
/// Uses SYNC cache check on init so image animates with sheet
struct ProgressiveAlbumArt: View {
    let lowQualityUrl: String
    let highQualityUrl: String
    
    @State private var displayImage: Image?
    @State private var isHighQualityLoaded = false
    
    // Check cache synchronously on init
    init(lowQualityUrl: String, highQualityUrl: String) {
        self.lowQualityUrl = lowQualityUrl
        self.highQualityUrl = highQualityUrl
        
        // SYNC check: Try high quality cache first
        if let url = URL(string: highQualityUrl),
           let cached = ImageCache.shared.memoryCachedImage(for: url) {
            _displayImage = State(initialValue: Image(uiImage: cached))
            _isHighQualityLoaded = State(initialValue: true)
        }
        // SYNC check: Fall back to low quality cache
        else if let url = URL(string: lowQualityUrl),
                let cached = ImageCache.shared.memoryCachedImage(for: url) {
            _displayImage = State(initialValue: Image(uiImage: cached))
            _isHighQualityLoaded = State(initialValue: false)
        }
    }
    
    var body: some View {
        ZStack {
            // Display image or placeholder
            if let image = displayImage {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder only if no image cached
                AlbumArtPlaceholder()
            }
        }
        .task {
            // Only load if not already loaded in init
            if !isHighQualityLoaded {
                await loadHighQuality()
            }
        }
    }
    
    private func loadHighQuality() async {
        guard let url = URL(string: highQualityUrl) else { return }
        
        // Check disk cache
        if let cached = await ImageCache.shared.image(for: url) {
            await MainActor.run {
                displayImage = Image(uiImage: cached)
                isHighQualityLoaded = true
            }
            return
        }
        
        // Load from network
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                await ImageCache.shared.store(uiImage, for: url)
                await MainActor.run {
                    displayImage = Image(uiImage: uiImage)
                    isHighQualityLoaded = true
                }
            }
        } catch {
            // Keep current image on error
        }
    }
}

// MARK: - Album Art Placeholder

struct AlbumArtPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
}
