//
//  ShimmerModifier.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI

// MARK: - Shimmer Effect Modifier

struct ShimmerModifier: ViewModifier {
    let isAnimating: Bool
    
    @State private var phase: CGFloat = 0
    
    init(isAnimating: Bool = true) {
        self.isAnimating = isAnimating
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(isAnimating ? 0.35 : 0),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.6 - geometry.size.width * 0.3)
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

// MARK: - Glow Effect Modifier

struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.4) : .clear, radius: radius)
            .shadow(color: isActive ? color.opacity(0.2) : .clear, radius: radius * 0.5)
    }
}

// MARK: - Dynamic Blur Modifier for Lyrics

struct LyricBlurModifier: ViewModifier {
    let offsetFromCurrent: Int
    
    var blurRadius: CGFloat {
        switch offsetFromCurrent {
        case 0:
            return 0          // Current line - no blur
        case -1:
            return 1.5        // Previous line - slight blur
        case 1:
            return 1          // Next line - minimal blur
        case 2:
            return 2          // 2nd next line - slight blur
        default:
            return 3          // Far lines - moderate blur
        }
    }
    
    var opacity: Double {
        switch offsetFromCurrent {
        case 0:
            return 1.0        // Current line - full opacity
        case -1:
            return 0.6        // Previous line
        case 1:
            return 0.8        // Next line - more visible
        case 2:
            return 0.6        // 2nd next line
        default:
            return 0.4        // Far lines
        }
    }
    
    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply shimmer animation effect
    func shimmer(isAnimating: Bool = true) -> some View {
        modifier(ShimmerModifier(isAnimating: isAnimating))
    }
    
    /// Apply glow effect
    func glow(color: Color = .white, radius: CGFloat = 8, isActive: Bool = true) -> some View {
        modifier(GlowModifier(color: color, radius: radius, isActive: isActive))
    }
    
    /// Apply lyric-specific blur based on offset from current line
    func lyricBlur(offsetFromCurrent: Int) -> some View {
        modifier(LyricBlurModifier(offsetFromCurrent: offsetFromCurrent))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack(spacing: 20) {
            Text("Previous line")
                .font(.title2)
                .foregroundStyle(.white)
                .lyricBlur(offsetFromCurrent: -1)
            
            Text("Current playing line")
                .font(.title.bold())
                .foregroundStyle(.white)
                .shimmer()
                .glow(color: .white, radius: 8)
            
            Text("Next line coming up")
                .font(.title2)
                .foregroundStyle(.white)
                .lyricBlur(offsetFromCurrent: 1)
            
            Text("Another line after")
                .font(.title2)
                .foregroundStyle(.white)
                .lyricBlur(offsetFromCurrent: 2)
        }
        .padding()
    }
}
