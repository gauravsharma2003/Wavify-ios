//
//  SleepTimerSheet.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI

struct SleepTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMinutes: Int? = nil
    
    let onConfirm: (Int) -> Void
    
    private let timeOptions: [(label: String, minutes: Int)] = [
        ("10 min", 10),
        ("15 min", 15),
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("5 hours", 300),
        ("8 hours", 480)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header with glass buttons
            HStack {
                // Cancel button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive())
                
                Spacer()
                
                Text("Sleep Timer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Done button
                Button {
                    if let minutes = selectedMinutes {
                        onConfirm(minutes)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selectedMinutes != nil ? .white : .white.opacity(0.4))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive())
                .disabled(selectedMinutes == nil)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
            
            // Time options grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(timeOptions, id: \.minutes) { option in
                    TimeOptionButton(
                        label: option.label,
                        isSelected: selectedMinutes == option.minutes
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMinutes = option.minutes
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .background(
            Color(white: 0.06)
                .ignoresSafeArea()
        )
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Time Option Button

private struct TimeOptionButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .glassEffect(isSelected ? .regular.interactive() : .regular, in: .rect(cornerRadius: 16))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.4), lineWidth: 2)
            }
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SleepTimerSheet { minutes in
            print("Selected: \(minutes) minutes")
        }
    }
}
