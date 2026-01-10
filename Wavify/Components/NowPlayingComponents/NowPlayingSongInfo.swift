//
//  NowPlayingSongInfo.swift
//  Wavify
//
//  Song info display components for NowPlayingView
//

import SwiftUI

// MARK: - Full Song Info View

struct NowPlayingSongInfoView: View {
    var song: Song?
    var navigationManager: NavigationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let song = song {
                Text(song.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Button {
                    if let artistId = song.artistId {
                        navigationManager.navigateToArtist(
                            id: artistId,
                            name: song.artist,
                            thumbnail: song.thumbnailUrl
                        )
                    }
                } label: {
                    Text(song.artist)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(song.artistId == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Compact Song Info (for expanded lyrics mode)

struct CompactSongInfoView: View {
    var audioPlayer: AudioPlayer
    
    var body: some View {
        HStack(spacing: 12) {
            if let song = audioPlayer.currentSong {
                // Small album art
                CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(.white.opacity(0.1))
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Play/Pause button
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
}
