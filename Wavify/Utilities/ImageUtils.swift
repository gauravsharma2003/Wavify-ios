//
//  ImageUtils.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation

/// Utilities for handling image URLs
enum ImageUtils {
    
    /// Upscales Google/YouTube thumbnail URLs to a higher resolution
    /// - Parameters:
    ///   - url: The original thumbnail URL
    ///   - targetSize: The target size in pixels (default 544 for high quality)
    /// - Returns: The upscaled URL if it's a Google content URL, otherwise the original
    static func upscaleThumbnail(_ url: String, targetSize: Int = 544) -> String {
        guard !url.isEmpty else { return url }
        
        // Handle lh3.googleusercontent.com URLs (YouTube Music thumbnails)
        // Example: https://lh3.googleusercontent.com/...=w120-h120-l90-rj
        if url.contains("googleusercontent.com") || url.contains("ytimg.com") {
            var upscaled = url
            
            // Replace width parameter: =w120 → =w544
            if let range = upscaled.range(of: "=w\\d+", options: .regularExpression) {
                upscaled.replaceSubrange(range, with: "=w\(targetSize)")
            }
            
            // Replace height parameter: -h120 → -h544
            if let range = upscaled.range(of: "-h\\d+", options: .regularExpression) {
                upscaled.replaceSubrange(range, with: "-h\(targetSize)")
            }
            
            // Also handle YouTube video thumbnail format
            // Example: https://i.ytimg.com/vi/VIDEO_ID/hqdefault.jpg
            upscaled = upscaled
                .replacingOccurrences(of: "default.jpg", with: "maxresdefault.jpg")
                .replacingOccurrences(of: "mqdefault.jpg", with: "maxresdefault.jpg")
                .replacingOccurrences(of: "hqdefault.jpg", with: "maxresdefault.jpg")
                .replacingOccurrences(of: "sddefault.jpg", with: "maxresdefault.jpg")
            
            return upscaled
        }
        
        return url
    }
    
    /// Returns thumbnail URL sized appropriately for a song row (smaller)
    static func thumbnailForRow(_ url: String) -> String {
        return upscaleThumbnail(url, targetSize: 120)
    }
    
    /// Returns thumbnail URL sized appropriately for album cards
    static func thumbnailForCard(_ url: String) -> String {
        return upscaleThumbnail(url, targetSize: 300)
    }
    
    /// Returns thumbnail URL sized for the Now Playing screen (highest quality)
    static func thumbnailForPlayer(_ url: String) -> String {
        return upscaleThumbnail(url, targetSize: 544)
    }
    
    /// Resizes Google/YouTube thumbnail URLs to specific dimensions
    /// - Parameters:
    ///   - url: The original thumbnail URL
    ///   - width: Target width
    ///   - height: Target height
    /// - Returns: The resized URL
    static func resizeThumbnail(_ url: String, width: Int, height: Int) -> String {
        guard !url.isEmpty else { return url }
        
        // Handle lh3.googleusercontent.com URLs (YouTube Music thumbnails)
        if url.contains("googleusercontent.com") || url.contains("ytimg.com") {
            var resized = url
            
            // Replace width parameter
            if let range = resized.range(of: "=w\\d+", options: .regularExpression) {
                resized.replaceSubrange(range, with: "=w\(width)")
            }
            
            // Replace height parameter
            if let range = resized.range(of: "-h\\d+", options: .regularExpression) {
                resized.replaceSubrange(range, with: "-h\(height)")
            }
            
            return resized
        }
        
        return url
    }
}
