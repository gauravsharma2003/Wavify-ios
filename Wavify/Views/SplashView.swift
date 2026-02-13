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
        // Purple gradient matching HomeView — icon/text managed by WavifyApp overlay for fly-to-toolbar animation
        LinearGradient(
            stops: [
                .init(color: Color.brandGradientTop, location: 0),
                .init(color: Color.brandBackground, location: 0.45)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
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
