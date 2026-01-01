//
//  ColorExtractor.swift
//  Wavify
//
//  Created by Gaurav Sharma on 31/12/25.
//

import SwiftUI
import UIKit

/// Extracts dominant colors from an image for dynamic backgrounds
enum ColorExtractor {
    
    /// Extracts the primary and secondary dominant colors from a UIImage
    /// - Parameter image: The source image
    /// - Returns: A tuple of (primary, secondary) SwiftUI Colors
    static func extractColors(from image: UIImage) -> (primary: Color, secondary: Color) {
        guard let cgImage = image.cgImage else {
            return defaultColors
        }
        
        let width = 50  // Sample at smaller size for performance
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
        
        var colorCounts: [UInt32: Int] = [:]
        
        // Sample pixels and count colors
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
                
                // Quantize colors to reduce noise
                let qr = (r / 32) * 32
                let qg = (g / 32) * 32
                let qb = (b / 32) * 32
                
                let key = UInt32(qr) << 16 | UInt32(qg) << 8 | UInt32(qb)
                colorCounts[key, default: 0] += 1
            }
        }
        
        // Get top 2 most frequent colors
        let sortedColors = colorCounts.sorted { $0.value > $1.value }
        
        guard sortedColors.count >= 1 else {
            return defaultColors
        }
        
        let primary = colorFromKey(sortedColors[0].key)
        let secondary = sortedColors.count >= 2 
            ? colorFromKey(sortedColors[1].key)
            : primary.opacity(0.6)
        
        // Darken colors for better background feel
        return (
            primary: darken(primary, by: 0.4),
            secondary: darken(secondary, by: 0.5)
        )
    }
    
    private static var defaultColors: (primary: Color, secondary: Color) {
        (Color(red: 0.2, green: 0.1, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2))
    }
    
    private static func colorFromKey(_ key: UInt32) -> Color {
        let r = Double((key >> 16) & 0xFF) / 255.0
        let g = Double((key >> 8) & 0xFF) / 255.0
        let b = Double(key & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    private static func darken(_ color: Color, by amount: Double) -> Color {
        // Convert to UIColor to manipulate
        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        return Color(hue: Double(h), saturation: Double(s) * 1.2, brightness: Double(b) * (1 - amount))
    }
    
    /// Async version that loads and extracts colors from a URL
    static func extractColors(from url: URL) async -> (primary: Color, secondary: Color) {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return defaultColors
            }
            return extractColors(from: image)
        } catch {
            return defaultColors
        }
    }
}
