//
//  YouTubeAPIContext.swift
//  Wavify
//
//  Shared configuration and contexts for YouTube Music API
//

import Foundation

/// Shared configuration for all YouTube Music API calls
enum YouTubeAPIContext {
    
    // MARK: - URLs
    
    static let baseURL = "https://music.youtube.com/youtubei/v1"
    
    // MARK: - Client Versions
    
    static let webRemixVersion = "1.20251208.03.00"
    static let androidVersion = "20.10.38"
    
    // MARK: - Headers
    
    static var webHeaders: [String: String] {
        [
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "content-type": "application/json",
            "origin": "https://music.youtube.com",
            "referer": "https://music.youtube.com/",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            "x-origin": "https://music.youtube.com"
        ]
    }
    
    static var androidHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "X-Goog-Api-Format-Version": "1",
            "X-YouTube-Client-Name": "3",
            "X-YouTube-Client-Version": androidVersion,
            "X-Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/",
            "User-Agent": "com.google.android.youtube/\(androidVersion) (Linux; U; Android 11) gzip"
        ]
    }
    
    // MARK: - Request Contexts
    
    static var webContext: [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": webRemixVersion
            ]
        ]
    }
    
    static var androidContext: [String: Any] {
        [
            "client": [
                "clientName": "ANDROID",
                "clientVersion": androidVersion,
                "gl": "US",
                "hl": "en"
            ]
        ]
    }
    
    /// Creates a web context with custom country/language
    static func webContext(country: String, language: String = "en") -> [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": webRemixVersion,
                "gl": country,
                "hl": language
            ]
        ]
    }
    
    // MARK: - Helper Methods
    
    /// Apply web headers to a request
    static func applyWebHeaders(to request: inout URLRequest) {
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    }
    
    /// Apply android headers to a request
    static func applyAndroidHeaders(to request: inout URLRequest) {
        androidHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    }
}
