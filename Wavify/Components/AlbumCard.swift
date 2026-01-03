//
//  AlbumCard.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI

struct AlbumCard: View {
    let title: String
    let subtitle: String
    let imageUrl: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { onTap() }) {
            VStack(alignment: .leading, spacing: 8) {
                // Album Art
                CachedAsyncImagePhase(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Color.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            .overlay {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.secondary)
                            }
                    case .empty:
                        Rectangle()
                            .fill(Color.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                            .overlay {
                                ProgressView()
                                    .tint(.secondary)
                            }
                    @unknown default:
                        Rectangle()
                            .fill(Color.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Playlist Card (with play count)

struct PlaylistCard: View {
    let name: String
    let songCount: Int
    let imageUrl: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { onTap() }) {
            HStack(spacing: 12) {
                // Playlist Art
                Group {
                    if let imageUrl = imageUrl, !imageUrl.isEmpty {
                        CachedAsyncImagePhase(url: URL(string: imageUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                playlistPlaceholder
                            }
                        }
                    } else {
                        playlistPlaceholder
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text("\(songCount) songs")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(GlassButtonStyle())
    }
    
    private var playlistPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
}

// MARK: - Featured Card (large hero card)

struct FeaturedCard: View {
    let title: String
    let subtitle: String
    let imageUrl: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .bottomLeading) {
                // Background Image
                CachedAsyncImagePhase(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                
                // Gradient Overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(16)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple.opacity(0.8), .blue.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        ScrollView {
            VStack(spacing: 16) {
                FeaturedCard(
                    title: "Today's Top Hits",
                    subtitle: "The hottest songs right now",
                    imageUrl: ""
                ) { }
                .padding(.horizontal)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    AlbumCard(
                        title: "After Hours",
                        subtitle: "The Weeknd",
                        imageUrl: ""
                    ) { }
                    
                    AlbumCard(
                        title: "Blinding Lights",
                        subtitle: "Single",
                        imageUrl: ""
                    ) { }
                }
                .padding(.horizontal)
                
                PlaylistCard(
                    name: "My Favorites",
                    songCount: 42,
                    imageUrl: nil
                ) { }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}
