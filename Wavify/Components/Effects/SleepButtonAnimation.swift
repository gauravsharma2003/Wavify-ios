import SwiftUI

struct SleepButtonAnimation: ViewModifier {
    var trigger: Bool

    @State private var animationTime: Double = 0.0

    func body(content: Content) -> some View {
        content
            .modifier(SleepAnimationEffect(time: animationTime))
            .onChange(of: trigger) { _, newValue in
                if newValue {
                    animationTime = 0.0
                    withAnimation(.easeOut(duration: 1.05)) {
                        animationTime = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                        withAnimation(.none) {
                            animationTime = 0.0
                        }
                    }
                } else {
                    withAnimation(.none) {
                        animationTime = 0.0
                    }
                }
            }
    }
}

// MARK: - Animatable Effect

private struct SleepAnimationEffect: AnimatableModifier {
    var time: Double

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    // 5 sparkles — odd count avoids symmetry, feels more organic
    private static let stars: [(angle: Double, dist: CGFloat, size: CGFloat, delay: Double)] = [
        (angle: -.pi / 4,       dist: 20, size: 5.0, delay: 0.0),   // top-right
        (angle: .pi * 0.85,     dist: 18, size: 4.0, delay: 0.04),  // lower-left
        (angle: .pi / 6,        dist: 21, size: 3.5, delay: 0.08),  // right
        (angle: .pi * 0.55,     dist: 19, size: 4.0, delay: 0.12),  // left
        (angle: -.pi * 0.6,     dist: 17, size: 3.5, delay: 0.06),  // top-left
    ]

    func body(content: Content) -> some View {
        content
            .scaleEffect(moonScale(time))
            .background(
                ZStack {
                    ForEach(0..<Self.stars.count, id: \.self) { i in
                        let star = Self.stars[i]
                        let lt = localTime(time, delay: star.delay)

                        Image(systemName: "sparkle")
                            .font(.system(size: star.size, weight: .medium))
                            .foregroundStyle(.cyan.opacity(0.9))
                            .offset(
                                x: cos(star.angle) * star.dist,
                                y: sin(star.angle) * star.dist
                            )
                            .scaleEffect(sparkleScale(lt))
                            .opacity(sparkleOpacity(lt))
                    }
                }
                .allowsHitTesting(false)
            )
    }

    // MARK: - Helpers

    private func localTime(_ t: Double, delay: Double) -> Double {
        max(0, min(1, (t - delay) / max(0.01, 1.0 - delay)))
    }

    // MARK: - Moon

    private func moonScale(_ t: Double) -> CGFloat {
        // Gentle pop: 1.0 → 1.08 → 1.0
        if t < 0.15 {
            let p = easeOut(t / 0.15)
            return 1.0 + 0.08 * CGFloat(p)
        } else if t < 0.35 {
            let p = easeIn((t - 0.15) / 0.2)
            return 1.08 - 0.08 * CGFloat(p)
        } else {
            return 1.0
        }
    }

    // MARK: - Sparkles

    private func sparkleScale(_ t: Double) -> CGFloat {
        if t < 0.2 {
            // Ease-out pop in: 0 → 1
            return CGFloat(easeOut(t / 0.2))
        } else if t < 0.6 {
            // Gentle breathing: 0.9 ↔ 1.0
            let breath = (t - 0.2) / 0.4
            return 0.95 + 0.05 * CGFloat(sin(breath * .pi * 2))
        } else {
            // Ease-in shrink out: 1 → 0
            let p = easeIn((t - 0.6) / 0.4)
            return max(0, 1.0 - CGFloat(p))
        }
    }

    private func sparkleOpacity(_ t: Double) -> Double {
        if t < 0.15 {
            // Smooth fade in
            return easeOut(t / 0.15)
        } else if t < 0.55 {
            // Soft glow pulse: 0.7 ↔ 1.0
            let pulse = (t - 0.15) / 0.4
            return 0.85 + 0.15 * sin(pulse * .pi * 2)
        } else {
            // Gentle fade out
            return max(0, 1.0 - easeIn((t - 0.55) / 0.45))
        }
    }

    // MARK: - Easing

    private func easeOut(_ t: Double) -> Double {
        1.0 - pow(1.0 - t, 3)
    }

    private func easeIn(_ t: Double) -> Double {
        pow(t, 3)
    }
}

extension View {
    func sleepButtonAnimation(trigger: Bool) -> some View {
        self.modifier(SleepButtonAnimation(trigger: trigger))
    }
}
