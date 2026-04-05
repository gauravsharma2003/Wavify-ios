//
//  ShareColorPicker.swift
//  Wavify
//

import SwiftUI

struct ShareColorPicker: View {
    @Binding var selectedOption: ShareColorOption
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(ShareColorOption.allCases) { option in
                    colorCircle(for: option)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedOption = option
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func colorCircle(for option: ShareColorOption) -> some View {
        let isSelected = selectedOption == option
        return option.circleFill(primary: primaryColor, secondary: secondaryColor, accent: accentColor)
            .frame(width: 40, height: 40)
            .overlay {
                Circle()
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: isSelected ? 3 : 1)
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
