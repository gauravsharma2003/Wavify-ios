//
//  ArtistItemsGridView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI
import SwiftData

struct ArtistItemsGridView: View {
    let title: String
    let browseId: String
    let params: String?
    let artistName: String
    var audioPlayer: AudioPlayer
    
    /// Fallback items to use if the API returns empty (from initial carousel)
    var fallbackItems: [ArtistItem] = []
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var items: [ArtistItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    // Check if this is a Videos section
    private var isVideosSection: Bool {
        title.lowercased().contains("video")
    }
    
    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            
            if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                VStack {
                    Text("Failed to load \(title)")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadItems() }
                    }
                    .padding()
                }
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No \(title.lowercased()) available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(items) { item in
                            itemView(for: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if items.isEmpty {
                await loadItems()
            }
        }
    }
    
    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        
        Logger.debug("[ArtistItemsGridView] Loading \(title) with browseId: \(browseId), params: \(params ?? "nil")", category: .network)
        
        do {
            let fetchedItems = try await networkManager.getSectionItems(browseId: browseId, params: params)
            Logger.debug("[ArtistItemsGridView] Loaded \(fetchedItems.count) items for \(title)", category: .network)
            
            if fetchedItems.isEmpty {
                // Use fallback items if API returned empty
                if !fallbackItems.isEmpty {
                    Logger.debug("[ArtistItemsGridView] ⚠️ API returned empty, using \(fallbackItems.count) fallback items", category: .network)
                    self.items = fallbackItems
                } else {
                    Logger.warning("[ArtistItemsGridView] WARNING: No items returned for \(title) and no fallback available", category: .network)
                    self.items = []
                }
            } else {
                // Success! API returned items
                if !fallbackItems.isEmpty {
                    Logger.debug("[ArtistItemsGridView] ✅ API SUCCESS: Fetched \(fetchedItems.count) items (vs \(fallbackItems.count) fallback items)", category: .network)
                } else {
                    Logger.debug("[ArtistItemsGridView] ✅ API SUCCESS: Fetched \(fetchedItems.count) items", category: .network)
                }
                self.items = fetchedItems
                // Log first few items for debugging
                for (index, item) in items.prefix(3).enumerated() {
                    Logger.debug("[ArtistItemsGridView] Item \(index): \(item.title), videoId: \(item.videoId ?? "nil"), browseId: \(item.browseId ?? "nil")", category: .network)
                }
            }
        } catch {
            Logger.networkError("Error loading \(title)", error: error)
            // On error, try to use fallback items
            if !fallbackItems.isEmpty {
                Logger.debug("[ArtistItemsGridView] ❌ Error occurred, using \(fallbackItems.count) fallback items", category: .network)
                self.items = fallbackItems
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
    
    @ViewBuilder
    private func itemView(for item: ArtistItem) -> some View {
        // For videos (items with videoId), make them playable
        if let videoId = item.videoId {
            Button {
                playVideo(item)
            } label: {
                itemCardView(for: item, isVideo: true)
            }
            .buttonStyle(.plain)
        } else if let browseId = item.browseId {
            // For albums/singles, navigate to detail view
            NavigationLink {
                AlbumDetailView(
                    albumId: browseId,
                    initialName: item.title,
                    initialArtist: artistName,
                    initialThumbnail: item.thumbnailUrl,
                    audioPlayer: audioPlayer
                )
            } label: {
                itemCardView(for: item, isVideo: false)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func itemCardView(for item: ArtistItem, isVideo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImagePhase(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 160, height: isVideo ? 90 : 160)  // 16:9 for videos
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Play button overlay for videos
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(item.subtitle ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(Color(white: 0.1).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func playVideo(_ item: ArtistItem) {
        guard let videoId = item.videoId else { return }
        let song = Song(
            id: videoId,
            title: item.title,
            artist: item.subtitle ?? artistName,
            thumbnailUrl: item.thumbnailUrl,
            duration: ""
        )
        Task {
            await audioPlayer.loadAndPlay(song: song)
        }
    }
}
