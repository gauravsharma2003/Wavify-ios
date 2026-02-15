//
//  NowPlayingProgressView.swift
//  Wavify
//
//  Progress bar components for NowPlayingView
//

import SwiftUI
import UIKit


// MARK: - Full Progress View

struct NowPlayingProgressSection: View {
    var audioPlayer: AudioPlayer
    var isCrossfadeActive: Bool = false

    @State private var lastHapticValue: Int = 0
    @State private var lastHapticFireTime: Date = .distantPast
    @State private var feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    private func triggerHaptic(_ newValue: Double) {
        let newInt = Int(newValue)

        if newInt != lastHapticValue {
            let now = Date()
            // Rate limit: max 20 triggers per second
            if now.timeIntervalSince(lastHapticFireTime) > 0.05 {
                feedbackGenerator.impactOccurred(intensity: 0.5)
                lastHapticFireTime = now
                lastHapticValue = newInt
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Slider
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { newValue in
                        triggerHaptic(newValue)
                        audioPlayer.seek(to: newValue)
                    }
                ),
                in: 0...max(audioPlayer.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        feedbackGenerator.prepare()
                    }
                }
            )
            .tint(.white)

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

    var body: some View {
        VStack(spacing: 4) {
            // Slim Slider
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { newValue in
                        triggerHaptic(newValue)
                        audioPlayer.seek(to: newValue)
                    }
                ),
                in: 0...max(audioPlayer.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        feedbackGenerator.prepare()
                    }
                }
            )
            .tint(.white)
            .scaleEffect(y: 0.8)

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
