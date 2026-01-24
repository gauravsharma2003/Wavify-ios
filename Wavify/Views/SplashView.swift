//
//  SplashView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 04/01/26.
//

import SwiftUI

/// Simple splash screen with static logo that handles keyboard pre-warming
/// Audio session is NOT configured here to avoid conflicts with AudioPlayer
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
            // Only pre-warm keyboard (safe, no audio session conflicts)
            await prewarmKeyboard()
            
            // Short delay to show splash
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
            
            isFinished = true
        }
    }
    
    private func prewarmKeyboard() async {
        await MainActor.run {
            let inputController = UIInputViewController()
            _ = inputController.view
            
            let textChecker = UITextChecker()
            _ = textChecker.completions(
                forPartialWordRange: NSRange(location: 0, length: 1),
                in: "a",
                language: "en"
            )
        }
    }
}

#Preview {
    SplashView(isFinished: .constant(false))
}
