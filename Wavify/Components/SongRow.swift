//
//  SongRow.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI

struct SongRow: View {
    let song: Song
    let showArtwork: Bool
    let onTap: () -> Void
    let onLike: (() -> Void)?
    var showMenu: Bool = false
    var onAddToPlaylist: (() -> Void)? = nil
    
    init(
        song: Song,
        showArtwork: Bool = true,
        onTap: @escaping () -> Void,
        onLike: (() -> Void)? = nil,
        showMenu: Bool = false,
        onAddToPlaylist: (() -> Void)? = nil
    ) {
        self.song = song
        self.showArtwork = showArtwork
        self.onTap = onTap
        self.onLike = onLike
        self.showMenu = showMenu
        self.onAddToPlaylist = onAddToPlaylist
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if showArtwork {
                    AsyncImage(url: URL(string: song.thumbnailUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(Color(white: 0.2))
                                .overlay {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            Rectangle()
                                .fill(Color(white: 0.15))
                        @unknown default:
                            Rectangle()
                                .fill(Color(white: 0.15))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !song.duration.isEmpty {
                    Text(song.duration)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                
                // Three-dot menu
                if showMenu {
                    Menu {
                        if let onAddToPlaylist = onAddToPlaylist {
                            Button {
                                onAddToPlaylist()
                            } label: {
                                Label("Add to Playlist", systemImage: "text.badge.plus")
                            }
                        }
                        
                        if let onLike = onLike {
                            Button {
                                onLike()
                            } label: {
                                Label(
                                    song.isLiked ? "Remove from Liked" : "Add to Liked",
                                    systemImage: song.isLiked ? "heart.slash" : "heart"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                } else if let onLike = onLike {
                    // Legacy like button (when menu is not shown)
                    Button(action: onLike) {
                        Image(systemName: song.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(song.isLiked ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Song Row (for queue)

struct CompactSongRow: View {
    let song: Song
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color(white: 0.15))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isCurrentlyPlaying {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white, lineWidth: 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14, weight: isCurrentlyPlaying ? .semibold : .regular))
                        .foregroundStyle(isCurrentlyPlaying ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isCurrentlyPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .symbolEffect(.variableColor.iterative)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color(white: 0.08)
            .ignoresSafeArea()
        
        VStack(spacing: 0) {
            SongRow(
                song: Song(
                    id: "1",
                    title: "Blinding Lights",
                    artist: "The Weeknd",
                    thumbnailUrl: "",
                    duration: "3:22",
                    isLiked: true
                ),
                onTap: { },
                onLike: { }
            )
            
            Divider()
                .padding(.leading, 80)
                .opacity(0.3)
            
            SongRow(
                song: Song(
                    id: "2",
                    title: "Save Your Tears",
                    artist: "The Weeknd",
                    thumbnailUrl: "",
                    duration: "3:35",
                    isLiked: false
                ),
                onTap: { },
                onLike: { }
            )
        }
        .padding()
    }
}
