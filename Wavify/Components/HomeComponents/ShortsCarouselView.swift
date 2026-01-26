import SwiftUI

struct ShortsCarouselView: View {
    var title: String = "Trending in Shorts"
    var subtitle: String = "Popular on YouTube Shorts"
    let songs: [SearchResult]
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    var scrollResetId: UUID = UUID()
    let onSongTap: (SearchResult) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    private let cardWidth: CGFloat = 170
    private let cardHeight: CGFloat = 280 // Wider and shorter profile
    
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
            
            // Horizontal carousel
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(songs, id: \.id) { song in
                        ShortsCard(
                            song: song,
                            isLiked: likedSongIds.contains(song.id),
                            isInQueue: queueSongIds.contains(song.id),
                            width: cardWidth,
                            height: cardHeight,
                            onTap: { onSongTap(song) },
                            onAddToPlaylist: { onAddToPlaylist(song) },
                            onToggleLike: { onToggleLike(song) },
                            onPlayNext: { onPlayNext(song) },
                            onAddToQueue: { onAddToQueue(song) }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .id(scrollResetId)
        }
    }
}

struct ShortsCard: View {
    let song: SearchResult
    let isLiked: Bool
    let isInQueue: Bool
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void
    let onAddToPlaylist: () -> Void
    let onToggleLike: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    
    private var thumbnailUrl: String {
        var p = song.thumbnailUrl
        // Try to get higher res if possible
        if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w540-h960")
        } else if p.contains("w120-h120") {
            p = p.replacingOccurrences(of: "w120-h120", with: "w540-h960")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background image
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped() // Ensure image is center-clipped to fit dimensions
                    } else {
                        Color(white: 0.15)
                            .frame(width: width, height: height)
                            .overlay {
                                ProgressView()
                                    .tint(.white.opacity(0.5))
                            }
                    }
                }
                
                // Shadow gradient for text readability (Stronger and higher)
                LinearGradient(
                    colors: [
                        .clear, 
                        .black.opacity(0.4), 
                        .black.opacity(0.7), 
                        .black.opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: height * 0.55)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(song.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(8)
                .frame(width: width, alignment: .bottomLeading)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onAddToPlaylist()
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            
            Button {
                onToggleLike()
            } label: {
                Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
            }
            
            Button {
                onPlayNext()
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            
            Button {
                onAddToQueue()
            } label: {
                Label(isInQueue ? "In Queue" : "Add to Queue", systemImage: "text.append")
            }
        }
    }
}
