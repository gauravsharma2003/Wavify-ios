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
    
    // Swipe gesture state
    @State private var dragOffset: CGFloat = 0
    private let swipeThreshold: CGFloat = 50
    
    // Progress tracking for smooth animations
    @State private var displayedProgress: Double = 0
    @State private var isTransitioning: Bool = false
    @State private var lastSongId: String = ""
    
    // Actual progress value
    private var actualProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(1.0, max(0.0, audioPlayer.currentTime / audioPlayer.duration))
    }
    
    var body: some View {
        if let song = audioPlayer.currentSong {
            HStack(spacing: 12) {
                // Album Art with circular progress ring
                ZStack {
                    // Background ring (track)
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        .frame(width: 50, height: 50)
                    
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: displayedProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                    
                    // Album art image
                    CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
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
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                .offset(x: dragOffset * 0.3) // Subtle offset with drag
                
                // Song Info (tappable area)
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
                    Image(systemName: "chevron.forward.dotted.chevron.forward")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            .clipShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Only track horizontal movement
                        if abs(value.translation.width) > abs(value.translation.height) {
                            // Clamp the drag offset to prevent content overflow
                            let dampened = value.translation.width * 0.4
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                                dragOffset = max(-60, min(60, dampened))
                            }
                        }
                    }
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        
                        if horizontalAmount < -swipeThreshold {
                            // Swipe left → Play next song
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            
                            Task {
                                await audioPlayer.playNext()
                            }
                        } else if horizontalAmount > swipeThreshold {
                            // Swipe right → Play previous song
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            
                            Task {
                                await audioPlayer.playPrevious()
                            }
                        }
                        
                        // Always smoothly reset to center
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
            .onTapGesture {
                onTap()
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: song.id) {
                // Preload high-quality image for NowPlayingView in background
                await preloadPlayerImage(for: song)
            }
            .onChange(of: song.id) { oldId, newId in
                // Song changed - animate backwards to 0
                guard oldId != newId, !lastSongId.isEmpty else {
                    lastSongId = newId
                    return
                }
                
                isTransitioning = true
                lastSongId = newId
                
                // Smooth backtrack animation to 0
                withAnimation(.easeOut(duration: 0.25)) {
                    displayedProgress = 0
                }
                
                // Resume normal tracking after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTransitioning = false
                }
            }
            .onChange(of: actualProgress) { _, newValue in
                // Only update if not transitioning between songs
                guard !isTransitioning else { return }
                displayedProgress = newValue
            }
            .onAppear {
                // Initialize
                lastSongId = song.id
                displayedProgress = actualProgress
            }
        }
    }
    
    /// Preloads the high-quality album art so it's cached when NowPlayingView opens
    private func preloadPlayerImage(for song: Song) async {
        let highQualityUrl = ImageUtils.thumbnailForPlayer(song.thumbnailUrl)
        guard let url = URL(string: highQualityUrl) else { return }
        
        // Check if already cached
        if await ImageCache.shared.image(for: url) != nil {
            return
        }
        
        // Load and cache in background
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await ImageCache.shared.store(image, for: url)
            }
        } catch {
            // Silently fail - image will load normally when needed
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
