//
//  MiniPlayer.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI

struct MiniPlayer: View {
    @Bindable var audioPlayer: AudioPlayer
    let onTap: () -> Void
    
    var body: some View {
        if let song = audioPlayer.currentSong {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Album Art & Song Info (tappable area)
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: song.thumbnailUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                Rectangle()
                                    .fill(Color(white: 0.2))
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 50))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            Text(song.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
                    
                    Spacer()
                    
                    // Play/Pause Button
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Next Button
                    Button {
                        Task {
                            await audioPlayer.playNext()
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 20)  // Increased left padding for capsule
                .padding(.trailing, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                // Progress Bar at bottom - smaller and more padding
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                        
                        Rectangle()
                            .fill(.white.opacity(0.5))
                            .frame(
                                width: audioPlayer.duration > 0
                                    ? geometry.size.width * (audioPlayer.currentTime / audioPlayer.duration)
                                    : 0
                            )
                    }
                }
                .frame(height: 2)  // Smaller height
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .padding(.horizontal, 24)  // Increased horizontal padding
                .padding(.bottom, 10)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

#Preview {
    ZStack {
        Color(white: 0.06)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            MiniPlayer(audioPlayer: AudioPlayer.shared) { }
                .padding(.bottom, 60)
        }
    }
}
