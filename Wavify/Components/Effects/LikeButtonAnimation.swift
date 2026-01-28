
import SwiftUI

struct LikeButtonAnimation: ViewModifier {
    var trigger: Bool
    
    // Animation States
    @State private var time: Double = 0.0
    @State private var showAnimation: Bool = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(showAnimation ? scaleForTime(time) : 1.0)
            // Ring Animation removed as per request
            // .overlay(...)
            // Sprinkles Animation (Background - Back)
            .background(
                ZStack {
                    if showAnimation {
                        SprinklesView(time: time)
                    }
                }
            )
            .onChange(of: trigger) { newValue in
                if newValue {
                    // Trigger Animation
                    showAnimation = true
                    time = 0.0
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        // Pop effect
                    }
                    
                    withAnimation(.linear(duration: 0.8)) { // Slightly longer for visibility
                        time = 1.0
                    }
                    
                    // Reset after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        if !trigger { // Only reset if we haven't toggled back (though usually we want to reset the animation state regardless)
                             showAnimation = false
                        }
                         // Or just reset showAnimation if we want to be clean
                        showAnimation = false
                        time = 0.0
                    }
                } else {
                    showAnimation = false
                    time = 0.0
                }
            }
    }
    
    func scaleForTime(_ t: Double) -> CGFloat {
        // Tweak scale curve
        if t < 0.2 {
             return 1.0 + (CGFloat(t) * 2.0) // 1.0 -> 1.4
        } else if t < 0.4 {
             return 1.4 - (CGFloat(t - 0.2) * 2.0) // 1.4 -> 1.0
        } else {
            return 1.0
        }
    }
}

// MARK: - Ring View
struct RingView: View {
    var time: Double
    
    var body: some View {
        Circle()
            .stroke(Color.red, lineWidth: 2)
            .scaleEffect(1.0 + (CGFloat(time) * 2.0)) // Scale from 1.0 to 3.0
            .opacity(time > 0.5 ? (1.0 - time) * 2 : 1.0) // Fade out later
            .frame(width: 25, height: 25) // Slightly larger base
            .allowsHitTesting(false)
    }
}

// MARK: - Sprinkles View
struct SprinklesView: View {
    var time: Double
    let particleCount = 12
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                let angle = Double.pi * 2 * Double(index) / Double(particleCount)
                let spread: CGFloat = 45.0 // Increased spread
                // Adding some randomness to distance would be cool, but keeping consistent for now
                let distance = spread * CGFloat(time)
                
                Circle()
                    .fill(particleColor(index))
                    .frame(width: 4, height: 4) // Slightly larger particles
                    .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                    .scaleEffect(1.0 - time) // Shrink
                    .opacity(1.0 - time) // Fade
            }
        }
        .allowsHitTesting(false)
    }
    
    func particleColor(_ index: Int) -> Color {
        let colors: [Color] = [.red, .purple, .blue, .cyan, .green, .yellow, .orange, .pink]
        return colors[index % colors.count]
    }
}

extension View {
    func likeButtonAnimation(trigger: Bool) -> some View {
        self.modifier(LikeButtonAnimation(trigger: trigger))
    }
}
