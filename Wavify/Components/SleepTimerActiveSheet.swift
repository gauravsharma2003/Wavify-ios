//
//  SleepTimerActiveSheet.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI

struct SleepTimerActiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    var sleepTimerManager: SleepTimerManager = .shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Countdown display
                Text(sleepTimerManager.formattedRemainingTime)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                
                // Control buttons
                HStack(spacing: 20) {
                    // Stop button
                    Button {
                        sleepTimerManager.stop()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Stop")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 120, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    
                    // +10 min button
                    Button {
                        sleepTimerManager.addTime(minutes: 10)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("10")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 100, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(
                Color(white: 0.06)
                    .ignoresSafeArea()
            )
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SleepTimerActiveSheet()
    }
}
