//
//  PlaylistCoverImage.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI

/// A reusable playlist cover image that displays:
/// - 4+ thumbnails: 2x2 grid of first 4 images
/// - 1-3 thumbnails: Single cover image (first thumbnail)
/// - 0 thumbnails: Gradient placeholder
struct PlaylistCoverImage: View {
    let thumbnails: [String]
    var size: CGFloat = 160
    var cornerRadius: CGFloat = 12
    
    var body: some View {
        Group {
            if thumbnails.count >= 4 {
                // 2x2 grid of first 4 thumbnails
                gridCover
            } else if let firstUrl = thumbnails.first, !firstUrl.isEmpty {
                // Single cover image
                singleCover(url: firstUrl)
            } else {
                // Placeholder
                placeholderView
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    // MARK: - Grid Cover (4+ songs)
    
    private var gridCover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                gridCell(url: thumbnails[0])
                gridCell(url: thumbnails[1])
            }
            HStack(spacing: 0) {
                gridCell(url: thumbnails[2])
                gridCell(url: thumbnails[3])
            }
        }
    }
    
    private func gridCell(url: String) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedAsyncImagePhase(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        cellPlaceholder
                    }
                }
            }
            .clipped()
    }
    
    // MARK: - Single Cover (1-3 songs)
    
    private func singleCover(url: String) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedAsyncImagePhase(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholderView
                    }
                }
            }
            .clipped()
    }
    
    // MARK: - Placeholders
    
    private var placeholderView: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: size / 4))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
    
    private var cellPlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.15))
    }
}

#Preview {
    VStack(spacing: 20) {
        // 4+ songs
        PlaylistCoverImage(thumbnails: [
            "https://example.com/1.jpg",
            "https://example.com/2.jpg",
            "https://example.com/3.jpg",
            "https://example.com/4.jpg"
        ])
        .frame(width: 160, height: 160)
        
        // 1-3 songs
        PlaylistCoverImage(thumbnails: ["https://example.com/1.jpg"])
            .frame(width: 160, height: 160)
        
        // Empty
        PlaylistCoverImage(thumbnails: [])
            .frame(width: 160, height: 160)
    }
    .padding()
    .background(Color.black)
}
