//
//  KeepListeningGridView.swift
//  Wavify
//
//  2-row horizontal scrolling grid for "Keep Listening" section
//  Optimized with LazyHGrid for efficient view recycling
//

import SwiftUI

// MARK: - Keep Listening Grid (2 rows, horizontal scroll with LazyHGrid)
struct KeepListeningGridView: View {
    var title: String = "Keep Listening"
    let songs: [SearchResult]
    var scrollResetId: UUID = UUID() // Reset scroll position when this changes
    let onSongTap: (SearchResult) -> Void
    
    // Grid configuration: 2 fixed rows
    private let rows = [
        GridItem(.fixed(72), spacing: 12),
        GridItem(.fixed(72), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(title)
                .font(.title2)
                .bold()
                .foregroundStyle(.white)
                .padding(.horizontal)
            
            // Horizontal scrolling grid with LazyHGrid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 12) {
                    ForEach(songs, id: \.id) { song in
                        KeepListeningCard(item: song) {
                            onSongTap(song)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .id(scrollResetId) // Reset scroll position on refresh
        }
    }
}

// MARK: - Keep Listening Card (Medium size)
struct KeepListeningCard: View {
    let item: SearchResult
    let onTap: () -> Void
    
    private var thumbnailUrl: String {
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
            p = p.replacingOccurrences(of: "w120-h120", with: "w360-h360")
        } else if p.contains("w60-h60") {
            p = p.replacingOccurrences(of: "w60-h60", with: "w360-h360")
        } else if p.contains("s120") {
            p = p.replacingOccurrences(of: "s120", with: "s360")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Thumbnail - square, medium size
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Song info
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 220)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
