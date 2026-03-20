//
//  NowPlayingProgressView.swift
//  Wavify
//
//  Progress bar components for NowPlayingView
//

import SwiftUI
import UIKit


// MARK: - Smooth Seek Bar

private struct SmoothSeekBar: View {
    var audioPlayer: AudioPlayer
    var trackHeight: CGFloat = 4

    @State private var isDragging = false
    @State private var dragTime: Double = 0
    @State private var lastSyncTime: Double = 0
    @State private var lastSyncDate: Date = Date()

    @State private var lastHapticValue: Int = 0
    @State private var lastHapticFireTime: Date = .distantPast
    @State private var feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    private func triggerHaptic(_ newValue: Double) {
        let newInt = Int(newValue)
        if newInt != lastHapticValue {
            let now = Date()
            if now.timeIntervalSince(lastHapticFireTime) > 0.05 {
                feedbackGenerator.impactOccurred(intensity: 0.5)
                lastHapticFireTime = now
                lastHapticValue = newInt
            }
        }
    }

    private func smoothTime(at date: Date) -> Double {
        if isDragging { return dragTime }
        guard audioPlayer.duration > 0 else { return 0 }
        if audioPlayer.isPlaying {
            let elapsed = date.timeIntervalSince(lastSyncDate)
            let predicted = lastSyncTime + elapsed
            return min(predicted, audioPlayer.duration)
        } else {
            return audioPlayer.currentTime
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !audioPlayer.isPlaying && !isDragging)) { timeline in
            GeometryReader { geo in
                let width = geo.size.width
                let duration = max(audioPlayer.duration, 1)
                let currentSmooth = smoothTime(at: timeline.date)
                let fraction = min(1.0, max(0.0, currentSmooth / duration))
                let filledWidth = width * fraction
                let currentTrack = isDragging ? trackHeight * 3 : trackHeight * 1.8

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: currentTrack)

                    // Filled track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(currentTrack, filledWidth), height: currentTrack)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                feedbackGenerator.prepare()
                            }
                            let fraction = min(1.0, max(0.0, value.location.x / width))
                            dragTime = fraction * duration
                            triggerHaptic(dragTime)
                        }
                        .onEnded { value in
                            let fraction = min(1.0, max(0.0, value.location.x / width))
                            let seekTime = fraction * duration
                            audioPlayer.seek(to: seekTime)
                            lastSyncTime = seekTime
                            lastSyncDate = Date()
                            isDragging = false
                        }
                )
                .animation(.easeOut(duration: 0.15), value: isDragging)
            }
            .frame(height: 30)
        }
        .onChange(of: audioPlayer.currentTime) { _, newValue in
            if !isDragging {
                lastSyncTime = newValue
                lastSyncDate = Date()
            }
        }
        .onAppear {
            lastSyncTime = audioPlayer.currentTime
            lastSyncDate = Date()
        }
    }
}


// MARK: - Full Progress View

struct NowPlayingProgressSection: View {
    var audioPlayer: AudioPlayer
    var isCrossfadeActive: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            SmoothSeekBar(audioPlayer: audioPlayer)

            // Time Labels
            HStack {
                Text(audioPlayer.currentTime.formattedTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(audioPlayer.duration.formattedTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .overlay {
                if isCrossfadeActive {
                    CrossfadeIndicatorLabel(fontSize: 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isCrossfadeActive)
        }
    }
}

// MARK: - Slim Progress View (for expanded lyrics mode)

struct SlimProgressView: View {
    var audioPlayer: AudioPlayer
    var isCrossfadeActive: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            SmoothSeekBar(audioPlayer: audioPlayer, trackHeight: 3)

            // Time Labels
            HStack {
                Text(audioPlayer.currentTime.formattedTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(audioPlayer.duration.formattedTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .overlay {
                if isCrossfadeActive {
                    CrossfadeIndicatorLabel(fontSize: 11)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.4), value: isCrossfadeActive)
        }
    }
}

// MARK: - Crossfade Indicator Label

private struct CrossfadeIndicatorLabel: View {
    let fontSize: CGFloat
    private let cycleDuration: Double = 2.5

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

            let label = HStack(spacing: 4) {
                Image(systemName: "wave.3.right")
                Text("Crossfade")
            }
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.secondary)

            label
                .overlay {
                    GeometryReader { geo in
                        let width = geo.size.width
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.7), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.4)
                        .offset(x: -width * 0.4 + (width * 1.4) * phase)
                    }
                    .mask {
                        HStack(spacing: 4) {
                            Image(systemName: "wave.3.right")
                            Text("Crossfade")
                        }
                        .font(.system(size: fontSize, weight: .medium))
                    }
                    .clipped()
                }
        }
    }
}
