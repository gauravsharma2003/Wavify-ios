//
//  NowPlayingControls.swift
//  Wavify
//
//  Extracted control views for NowPlayingView
//

import SwiftUI

// MARK: - Main Playback Controls

struct NowPlayingControlsView: View {
    var audioPlayer: AudioPlayer
    var isLiked: Bool
    var onToggleLike: () -> Void
    
    var body: some View {
        HStack(spacing: 32) {
            // Like Button
            Button {
                onToggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isLiked ? .red : .secondary)
            }
            
            // Previous
            GlassPlayerButton(icon: "backward.fill", size: 24) {
                Task {
                    await audioPlayer.playPrevious()
                }
            }
            
            // Play/Pause
            LargePlayButton(isPlaying: audioPlayer.isPlaying) {
                audioPlayer.togglePlayPause()
            }
            
            // Next
            GlassPlayerButton(icon: "forward.fill", size: 24) {
                Task {
                    await audioPlayer.playNext()
                }
            }
            
            // Loop Mode Toggle
            Button {
                audioPlayer.toggleLoopMode()
            } label: {
                Image(systemName: audioPlayer.loopMode.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(audioPlayer.loopMode == .none ? .gray : .white)
            }
        }
    }
}

// MARK: - Additional Controls Row

struct NowPlayingAdditionalControls: View {
    var sleepTimerManager: SleepTimerManager
    var showLyrics: Bool
    var onSleepTimer: () -> Void
    var onShare: () -> Void
    var onAirPlay: () -> Void
    var onLyricsToggle: () -> Void
    var onAddToPlaylist: () -> Void
    
    var body: some View {
        HStack(spacing: 30) {
            // Sleep Timer Button
            Button {
                onSleepTimer()
            } label: {
                Image(systemName: sleepTimerManager.isActive ? "moon.fill" : "moon")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(sleepTimerManager.isActive ? .cyan : .white)
                    .frame(width: 44, height: 44)
            }
            
            // Share Button
            Button {
                onShare()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            
            // AirPlay Button
            Button {
                onAirPlay()
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            
            // Lyrics Button
            Button {
                onLyricsToggle()
            } label: {
                Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            
            // Add to Playlist Button
            Button {
                onAddToPlaylist()
            } label: {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.top, -16)
    }
}

