//
//  RecommendationsGridView.swift
//  Wavify
//
//  4-row horizontal scrolling grid for recommendations sections
//  Optimized with LazyHGrid for efficient view recycling
//

import SwiftUI

// MARK: - Recommendations Grid (4 rows, horizontal scroll with LazyHGrid)
struct RecommendationsGridView: View {
    var title: String = "You might like"
    var subtitle: String = "Based on your listening"
    let songs: [SearchResult]
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    let onSongTap: (SearchResult) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    // Grid configuration: 4 fixed rows
    private let rows = [
        GridItem(.fixed(56), spacing: 8),
        GridItem(.fixed(56), spacing: 8),
        GridItem(.fixed(56), spacing: 8),
        GridItem(.fixed(56), spacing: 8)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Horizontal scrolling grid with LazyHGrid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 16) {
                    ForEach(songs, id: \.id) { song in
                        RecommendationListRow(
                            item: song,
                            isLiked: likedSongIds.contains(song.id),
                            isInQueue: queueSongIds.contains(song.id),
                            onTap: {
                                onSongTap(song)
                            },
                            onAddToPlaylist: {
                                onAddToPlaylist(song)
                            },
                            onToggleLike: {
                                onToggleLike(song)
                            },
                            onPlayNext: {
                                onPlayNext(song)
                            },
                            onAddToQueue: {
                                onAddToQueue(song)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Recommendation List Row (Compact)
struct RecommendationListRow: View {
    let item: SearchResult
    let isLiked: Bool
    let isInQueue: Bool
    let onTap: () -> Void
    let onAddToPlaylist: () -> Void
    let onToggleLike: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    
    private var thumbnailUrl: String {
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
            p = p.replacingOccurrences(of: "w120-h120", with: "w226-h226")
        } else if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w226-h226")
        } else if p.contains("s120") {
            p = p.replacingOccurrences(of: "s120", with: "s226")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Duration (if available from year field)
                if !item.year.isEmpty {
                    Text(item.year)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                
                SongOptionsMenu(
                    isLiked: isLiked,
                    isInQueue: isInQueue,
                    onAddToPlaylist: onAddToPlaylist,
                    onToggleLike: onToggleLike,
                    onPlayNext: onPlayNext,
                    onAddToQueue: onAddToQueue
                )
            }
            .frame(width: 280)
            .padding(.vertical, 4)
        }
    }
}
