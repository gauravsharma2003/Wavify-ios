//
//  BreathingBackground.swift
//  Wavify
//
//  Apple Music-style breathing mesh gradient for lyrics mode.
//  Uses MeshGradient with slowly drifting control points.
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
                width: 3,
                height: 3,
                points: meshPoints(at: t),
                colors: [
                    // Edges & corners: all primaryColor so no visible blobs at borders
                    primaryColor,   primaryColor,   primaryColor,
                    primaryColor,   accentColor,    secondaryColor,
                    primaryColor,   secondaryColor, primaryColor
                ]
            )
        }
    }

    // MARK: - Mesh Point Animation

    private func meshPoints(at time: Double) -> [SIMD2<Float>] {
        [
            // Row 0: top — all fixed on edge
            SIMD2(0.0, 0.0),
            SIMD2(0.5, 0.0),
            SIMD2(1.0, 0.0),

            // Row 1: middle — edges slide along their edge only, center breathes freely
            edgeDrift(base: SIMD2(0.0, 0.5), along: .y, amp: 0.08, freq: 0.40, phase: 0.5, t: time),
            drift(base: SIMD2(0.5, 0.5), ax: 0.12, ay: 0.10, fx: 0.45, fy: 0.35, px: 3.7, py: 2.8, t: time),
            edgeDrift(base: SIMD2(1.0, 0.5), along: .y, amp: 0.08, freq: 0.48, phase: 4.2, t: time),

            // Row 2: bottom — edges slide along their edge only, center breathes
            SIMD2(0.0, 1.0),
            edgeDrift(base: SIMD2(0.5, 1.0), along: .x, amp: 0.08, freq: 0.42, phase: 3.1, t: time),
            SIMD2(1.0, 1.0)
        ]
    }

    private enum Axis { case x, y }

    /// Drift along a single axis only — keeps point pinned to its edge.
    private func edgeDrift(
        base: SIMD2<Float>,
        along axis: Axis,
        amp: Float, freq: Float, phase: Float,
        t: Double
    ) -> SIMD2<Float> {
        let offset = amp * sin(Float(t) * freq + phase)
        switch axis {
        case .x: return SIMD2(min(1, max(0, base.x + offset)), base.y)
        case .y: return SIMD2(base.x, min(1, max(0, base.y + offset)))
        }
    }

    /// Free 2D drift for interior points.
    private func drift(
        base: SIMD2<Float>,
        ax: Float, ay: Float,
        fx: Float, fy: Float,
        px: Float, py: Float,
        t: Double
    ) -> SIMD2<Float> {
        let tf = Float(t)
        let x = min(1, max(0, base.x + ax * sin(tf * fx + px)))
        let y = min(1, max(0, base.y + ay * sin(tf * fy + py)))
        return SIMD2(x, y)
    }
}
