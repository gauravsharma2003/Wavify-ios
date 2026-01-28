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
        }
    }
}

// MARK: - Slim Progress View (for expanded lyrics mode)

struct SlimProgressView: View {
    var audioPlayer: AudioPlayer
    
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
        }
    }
}
