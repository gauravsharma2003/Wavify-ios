//
//  ChromaKeyDetector.swift
//  Wavify
//
//  Detects musical key from a 12-bin chroma profile using Krumhansl-Kessler templates.
//  Correlates against 24 rotated templates (12 major + 12 minor) via Pearson correlation.
//  Used during crossfade analysis to adjust overlap duration by key compatibility.
//

import Foundation

final class ChromaKeyDetector {

    // Krumhansl-Kessler key profiles (starting from C)
    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Detect key from a normalized 12-bin chroma profile.
    /// Returns key (0-11 major C..B, 12-23 minor C..B) and confidence (best/secondBest ratio).
    static func detectKey(from chroma: [Float]) -> (key: Int, confidence: Float) {
        guard chroma.count == 12 else { return (0, 0) }

        var bestKey = 0
        var bestCorr: Float = -2
        var secondBestCorr: Float = -2

        // Test 24 keys (12 major + 12 minor)
        for key in 0..<24 {
            let isMajor = key < 12
            let rotation = key % 12
            let template = isMajor ? majorProfile : minorProfile

            // Rotate template by `rotation` semitones
            var rotated = [Float](repeating: 0, count: 12)
            for i in 0..<12 {
                rotated[i] = template[(i - rotation + 12) % 12]
            }

            let corr = pearsonCorrelation(chroma, rotated)
            if corr > bestCorr {
                secondBestCorr = bestCorr
                bestCorr = corr
                bestKey = key
            } else if corr > secondBestCorr {
                secondBestCorr = corr
            }
        }

        let confidence: Float = secondBestCorr > 0 ? bestCorr / secondBestCorr : (bestCorr > 0 ? 2.0 : 0)
        return (key: bestKey, confidence: min(confidence, 2.0))
    }

    /// Compute interval in semitones between two keys (shortest path, 0-6)
    static func interval(from key1: Int, to key2: Int) -> Int {
        let pitch1 = key1 % 12
        let pitch2 = key2 % 12
        let diff = abs(pitch1 - pitch2)
        return min(diff, 12 - diff)
    }

    /// Classify interval compatibility for crossfade duration adjustment
    /// "compatible" (unison, P4, P5): extend overlap 25%
    /// "clashing" (m2, tritone): shorten 25%
    /// "neutral": no change
    static func compatibility(interval: Int) -> String {
        switch interval {
        case 0, 5, 7:  return "compatible"  // unison, perfect 4th, perfect 5th
        case 1, 6:     return "clashing"    // minor 2nd, tritone
        default:       return "neutral"
        }
    }

    // MARK: - Pearson Correlation

    private static func pearsonCorrelation(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count > 0 else { return 0 }
        let n = Float(a.count)

        var sumA: Float = 0, sumB: Float = 0
        var sumAB: Float = 0, sumA2: Float = 0, sumB2: Float = 0

        for i in 0..<a.count {
            sumA += a[i]
            sumB += b[i]
            sumAB += a[i] * b[i]
            sumA2 += a[i] * a[i]
            sumB2 += b[i] * b[i]
        }

        let num = n * sumAB - sumA * sumB
        let den = sqrtf((n * sumA2 - sumA * sumA) * (n * sumB2 - sumB * sumB))
        guard den > 1e-10 else { return 0 }
        return num / den
    }
}
