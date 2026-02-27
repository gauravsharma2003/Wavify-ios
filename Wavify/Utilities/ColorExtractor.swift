//
//  ColorExtractor.swift
//  Wavify
//
//  Created by Gaurav Sharma on 31/12/25.
//

import SwiftUI
import UIKit

/// Extracts dominant colors from an image for dynamic backgrounds
/// Uses vibrancy-weighted scoring so punchy colors aren't drowned out by large earthy areas
enum ColorExtractor {

    struct ExtractedColors {
        let primary: Color
        let secondary: Color
        let accent: Color // Third vibrant color for richer gradients
    }

    /// Extracts the primary, secondary, and accent dominant colors from a UIImage
    /// Colors are scored by frequency × vibrancy, so saturated colors rank higher
    static func extractColors(from image: UIImage) -> ExtractedColors {
        guard let cgImage = image.cgImage else {
            return defaultColors
        }

        let width = 50
        let height = 50

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return defaultColors
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return defaultColors
        }

        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Track both count and raw RGB for each quantized bucket
        var colorCounts: [UInt32: Int] = [:]
        var colorSaturation: [UInt32: CGFloat] = [:]

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = (y * width + x) * 4
                let r = pointer[offset]
                let g = pointer[offset + 1]
                let b = pointer[offset + 2]

                // Skip very dark or very light colors
                let brightness = (Int(r) + Int(g) + Int(b)) / 3
                if brightness < 20 || brightness > 235 {
                    continue
                }

                // Finer quantization (16-unit steps) to preserve color distinction
                let qr = (r / 16) * 16
                let qg = (g / 16) * 16
                let qb = (b / 16) * 16

                let key = UInt32(qr) << 16 | UInt32(qg) << 8 | UInt32(qb)
                colorCounts[key, default: 0] += 1

                // Compute saturation for this pixel (only once per bucket)
                if colorSaturation[key] == nil {
                    let rf = CGFloat(qr) / 255.0
                    let gf = CGFloat(qg) / 255.0
                    let bf = CGFloat(qb) / 255.0
                    let maxC = max(rf, gf, bf)
                    let minC = min(rf, gf, bf)
                    let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                    colorSaturation[key] = sat
                }
            }
        }

        guard !colorCounts.isEmpty else {
            return defaultColors
        }

        let totalPixels = colorCounts.values.reduce(0, +)

        // Score = frequency × (1 + vibrancy_boost)
        // vibrancy_boost = saturation^0.7 × 3.0
        // This means a color with 0.8 saturation at 15% frequency can beat
        // a color with 0.1 saturation at 40% frequency
        let scored: [(key: UInt32, score: Double)] = colorCounts.map { key, count in
            let frequency = Double(count) / Double(totalPixels)
            let sat = Double(colorSaturation[key] ?? 0)
            let vibrancyBoost = pow(sat, 0.7) * 3.0
            let score = frequency * (1.0 + vibrancyBoost)
            return (key, score)
        }.sorted { $0.score > $1.score }

        // Pick top color
        let primaryKey = scored[0].key
        var picked: [UInt32] = [primaryKey]

        // Pick secondary: best score that's visually distinct from primary
        let secondaryKey = pickDistinctColor(from: scored, excluding: picked, minDistance: 60)
        picked.append(secondaryKey)

        // Pick accent: best score that's distinct from both
        let accentKey = pickDistinctColor(from: scored, excluding: picked, minDistance: 50)

        let primary = colorFromKey(primaryKey)
        let secondary = colorFromKey(secondaryKey)
        let accent = colorFromKey(accentKey)

        return ExtractedColors(
            primary: darken(primary, by: 0.35),
            secondary: darken(secondary, by: 0.45),
            accent: darken(accent, by: 0.5)
        )
    }

    /// Picks the highest-scored color that is visually distinct from all already-picked colors
    private static func pickDistinctColor(from scored: [(key: UInt32, score: Double)], excluding picked: [UInt32], minDistance: Int) -> UInt32 {
        for candidate in scored {
            let isDistinct = picked.allSatisfy { colorDistance(candidate.key, $0) >= minDistance }
            if isDistinct {
                return candidate.key
            }
        }
        // Fallback: just use the best remaining that isn't already picked
        return scored.first { c in !picked.contains(c.key) }?.key ?? scored[0].key
    }

    /// Simple RGB distance between two quantized color keys
    private static func colorDistance(_ a: UInt32, _ b: UInt32) -> Int {
        let dr = Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF)
        let dg = Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF)
        let db = Int(a & 0xFF) - Int(b & 0xFF)
        return abs(dr) + abs(dg) + abs(db)
    }

    private static var defaultColors: ExtractedColors {
        ExtractedColors(
            primary: Color(red: 0.2, green: 0.1, blue: 0.3),
            secondary: Color(red: 0.1, green: 0.1, blue: 0.2),
            accent: Color(red: 0.15, green: 0.05, blue: 0.25)
        )
    }

    private static func colorFromKey(_ key: UInt32) -> Color {
        let r = Double((key >> 16) & 0xFF) / 255.0
        let g = Double((key >> 8) & 0xFF) / 255.0
        let b = Double(key & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private static func darken(_ color: Color, by amount: Double) -> Color {
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        return Color(hue: Double(h), saturation: min(Double(s) * 1.3, 1.0), brightness: Double(b) * (1 - amount))
    }

    /// Async version — returns full 3-color extraction
    static func extractColors(from url: URL) async -> ExtractedColors {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return defaultColors
            }
            let result: ExtractedColors = extractColors(from: image)
            return result
        } catch {
            return defaultColors
        }
    }

}
