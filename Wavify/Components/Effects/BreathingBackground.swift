//
//  BreathingBackground.swift
//  Wavify
//
//  Apple Music-style breathing mesh gradient for lyrics mode.
//  4x4 MeshGradient with slowly drifting interior points.
//

import SwiftUI

struct BreathingBackground: View {
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            MeshGradient(
                width: 4,
                height: 4,
                points: meshPoints(at: t),
                colors: [
                    // Row 0 — top edge: all primary
                    primaryColor,   primaryColor,    primaryColor,    primaryColor,
                    // Row 1 — accent bleeds softly from upper-left interior
                    primaryColor,   accentColor,     primaryColor,    primaryColor,
                    // Row 2 — secondary bleeds softly from lower-right interior
                    primaryColor,   primaryColor,    secondaryColor,  primaryColor,
                    // Row 3 — bottom edge: all primary
                    primaryColor,   primaryColor,    primaryColor,    primaryColor
                ]
            )
        }
    }

    // MARK: - Mesh Points (4x4 = 16 points)

    private func meshPoints(at time: Double) -> [SIMD2<Float>] {
        let t = Float(time)
        return [
            // Row 0 — top edge: fixed
            p(0.00, 0.00), p(0.33, 0.00), p(0.67, 0.00), p(1.00, 0.00),

            // Row 1 — edges fixed, 2 interior points breathe
            p(0.00, 0.33),
            breathe(0.33, 0.33, t: t, fx: 0.40, fy: 0.32, px: 0.0, py: 2.1, ax: 0.08, ay: 0.06),
            breathe(0.67, 0.33, t: t, fx: 0.35, fy: 0.38, px: 1.5, py: 4.0, ax: 0.06, ay: 0.05),
            p(1.00, 0.33),

            // Row 2 — edges fixed, 2 interior points breathe
            p(0.00, 0.67),
            breathe(0.33, 0.67, t: t, fx: 0.38, fy: 0.42, px: 3.7, py: 1.0, ax: 0.06, ay: 0.05),
            breathe(0.67, 0.67, t: t, fx: 0.33, fy: 0.36, px: 5.2, py: 2.8, ax: 0.08, ay: 0.06),
            p(1.00, 0.67),

            // Row 3 — bottom edge: fixed
            p(0.00, 1.00), p(0.33, 1.00), p(0.67, 1.00), p(1.00, 1.00)
        ]
    }

    private func p(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x, y) }

    /// Slow sinusoidal 2D drift, clamped to [0,1].
    private func breathe(
        _ bx: Float, _ by: Float,
        t: Float,
        fx: Float, fy: Float,
        px: Float, py: Float,
        ax: Float, ay: Float
    ) -> SIMD2<Float> {
        SIMD2(
            min(1, max(0, bx + ax * sin(t * fx + px))),
            min(1, max(0, by + ay * sin(t * fy + py)))
        )
    }
}
