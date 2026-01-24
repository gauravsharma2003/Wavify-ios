//
//  YourFavouritesGridView.swift
//  Wavify
//
//  2-column vertical grid for "Your Favourites" section
//  Optimized with LazyVGrid for efficient view recycling
//

import SwiftUI

// MARK: - Your Favourites Grid (2-column vertical layout with LazyVGrid, max 8 items)
struct YourFavouritesGridView: View {
    let items: [SearchResult]
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    let namespace: Namespace.ID // Added for hero animations
    let refreshId: UUID // Force refresh after transition
    let onItemTap: (SearchResult) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    // Grid configuration: 2 flexible columns
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    // Always show even number of items (4, 6, or 8) for balanced columns
    private var displayItems: [SearchResult] {
        let maxItems = min(items.count, 8)
        let evenCount = maxItems - (maxItems % 2)
        return Array(items.prefix(evenCount))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Your Favourites")
                .font(.title2)
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            // 2-column vertical grid with LazyVGrid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(displayItems, id: \.id) { item in
                    FavouriteBlockCard(
                        item: item,
                        isLiked: likedSongIds.contains(item.id),
                        isInQueue: queueSongIds.contains(item.id),
                        namespace: namespace, // Pass namespace
                        refreshId: refreshId, // Pass refreshId for force refresh
                        onTap: { onItemTap(item) },
                        onAddToPlaylist: { onAddToPlaylist(item) },
                        onToggleLike: { onToggleLike(item) },
                        onPlayNext: { onPlayNext(item) },
                        onAddToQueue: { onAddToQueue(item) }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Favourite Block Card (Light grey block with image left, name right)
struct FavouriteBlockCard: View {
    let item: SearchResult
    let isLiked: Bool
    let isInQueue: Bool
    let namespace: Namespace.ID // Added
    let refreshId: UUID // Force refresh after transition
    let onTap: () -> Void
    var onAddToPlaylist: (() -> Void)? = nil
    var onToggleLike: (() -> Void)? = nil
    var onPlayNext: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    
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
    
    private var isArtist: Bool {
        item.type == .artist
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Thumbnail on the left - circular for artists
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.4)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 5)))
                .id(refreshId) // Force recreate when returning from detail
                .matchedTransitionSource(id: item.type == .album || item.type == .artist ? item.id : "non_hero_\(item.id)", in: namespace)
                
                // Name on the right, left-aligned
                Text(item.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.22))
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isArtist && item.type == .song {
                Button {
                    onAddToPlaylist?()
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
                
                Button {
                    onToggleLike?()
                } label: {
                    Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
                }
                
                Button {
                    onPlayNext?()
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                
                Button {
                    onAddToQueue?()
                } label: {
                    Label(isInQueue ? "In Queue" : "Add to Queue", systemImage: "text.append")
                }
            }
        }
    }
}

// SwiftUI helper for conditional shapes
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = { shape.path(in: $0) }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}
