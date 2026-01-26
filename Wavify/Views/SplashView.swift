//
//  SplashView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 04/01/26.
//

import SwiftUI

/// Simple splash screen with static logo that handles pre-warming of services
/// Pre-warms: audio engine, network, and singleton managers
struct SplashView: View {
    @Binding var isFinished: Bool

    var body: some View {
        ZStack {
            // Same background as HomeView
            Color(hex: "1A1A1A")
                .ignoresSafeArea()

            // Same logo as HomeView loading state - static, no animation
            VStack(spacing: 20) {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)

                Text("Wavify")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.white)
            }
        }
        .onAppear {
            performPrewarming()
        }
    }

    private func performPrewarming() {
        Task {
            // Trigger singleton initialization (they now load data on background threads)
            _ = EqualizerManager.shared
            _ = FavouritesManager.shared

            // Wait for audio engine to be fully initialized
            await AudioEngineService.shared.waitForInitialization()

            // Warm network on background (fire-and-forget)
            Task.detached(priority: .utility) {
                _ = NetworkManager.shared
                _ = URLSession.shared.configuration
            }

            // Ensure minimum splash duration for smooth UX
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s minimum

            isFinished = true
        }
    }
}

#Preview {
    SplashView(isFinished: .constant(false))
}
