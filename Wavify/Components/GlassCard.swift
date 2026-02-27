//
//  GlassCard.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: () -> Content
    
    init(cornerRadius: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }
    
    var body: some View {
        content()
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Button Styles

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Glass Player Button

struct GlassPlayerButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    init(icon: String, size: CGFloat = 24, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size + 24, height: size + 24)
                                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Large Play Button

struct LargePlayButton: View {
    let isPlaying: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 72, height: 72)
                                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Glass Pill Button

struct GlassPillButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    
    init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue, .teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 24) {
            GlassCard {
                Text("Glass Card")
                    .padding()
            }
            
            HStack(spacing: 16) {
                GlassPlayerButton(icon: "backward.fill") { }
                LargePlayButton(isPlaying: false) { }
                GlassPlayerButton(icon: "forward.fill") { }
            }
            
            GlassPillButton(title: "Shuffle Play", icon: "shuffle") { }
        }
    }
}