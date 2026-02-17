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
    
    /// Player API uses regular YouTube endpoint (not music) for ANDROID_VR client
    static let playerBaseURL = "https://www.youtube.com/youtubei/v1"
    
    // Hardcoded working visitor data from successful incognito experiment
    static let incognitoVisitorData = "CgtFZTRKTDZzemNxcyiH3N3LBjIKCgJJThIEGgAgPw%3D%3D"
    
    // Persistent visitor data across sessions
    static var visitorData: String? {
        get { UserDefaults.standard.string(forKey: "com.wavify.api.visitorData") ?? incognitoVisitorData }
        set { UserDefaults.standard.set(newValue, forKey: "com.wavify.api.visitorData") }
    }
    
    // MARK: - Client Versions
    
    static let webRemixVersion = "1.20260121.03.00"
    static let androidVersion = "19.10.38"
    static let androidVRVersion = "1.71.26"
    static let iosClientVersion = "19.29.1"
    
    // MARK: - Headers
    
    static var webHeaders: [String: String] {
        [
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "content-type": "application/json",
            "origin": "https://music.youtube.com",
            "referer": "https://music.youtube.com/",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36",
            "x-origin": "https://music.youtube.com",
            "x-youtube-client-name": "67",
            "x-youtube-client-version": webRemixVersion,
            "x-goog-visitor-id": visitorData ?? incognitoVisitorData
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
    
    
    /// ANDROID_VR client User-Agent
    static let androidVRUserAgent = "com.google.android.apps.youtube.vr.oculus/\(androidVRVersion) (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

    /// IOS client User-Agent
    static let iosUserAgent = "com.google.ios.youtube/\(iosClientVersion) (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)"

    /// ANDROID_VR client headers - no PoT required, primary playback client
    static var tvHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": androidVRUserAgent,
            "X-Youtube-Client-Name": "28",
            "X-Youtube-Client-Version": androidVRVersion,
            "Origin": "https://www.youtube.com",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }
    
    /// IOS client headers - native app client, returns direct URLs
    static var iosHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": iosUserAgent,
            "X-Youtube-Client-Name": "5",
            "X-Youtube-Client-Version": iosClientVersion,
            "Origin": "https://www.youtube.com",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }

    /// Default playback headers (IOS UA - matches primary extraction client)
    /// Note: Prefer using PlaybackInfo.playbackHeaders for stream-specific headers
    static var playbackHeaders: [String: String] {
        YouTubeStreamExtractor.playbackHeaders
    }
    
    // MARK: - Request Contexts
    
    static var webContext: [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": webRemixVersion,
                "visitorData": visitorData ?? incognitoVisitorData,
                "hl": "en",
                "gl": "IN",
                "platform": "DESKTOP",
                "osName": "Macintosh"
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
    
    /// ANDROID_VR client context - no Proof of Origin Token required
    static var tvContext: [String: Any] {
        [
            "client": [
                "clientName": "ANDROID_VR",
                "clientVersion": androidVRVersion,
                "deviceMake": "Oculus",
                "deviceModel": "Quest 3",
                "androidSdkVersion": 32,
                "userAgent": androidVRUserAgent,
                "osName": "Android",
                "osVersion": "12L",
                "hl": "en",
                "timeZone": "UTC",
                "utcOffsetMinutes": 0
            ]
        ]
    }
    
    /// IOS client context - native app client, returns direct URLs
    static var iosContext: [String: Any] {
        [
            "client": [
                "clientName": "IOS",
                "clientVersion": iosClientVersion,
                "deviceMake": "Apple",
                "deviceModel": "iPhone16,2",
                "userAgent": iosUserAgent,
                "osName": "iPhone",
                "osVersion": "17.5.1",
                "hl": "en",
                "timeZone": "UTC",
                "utcOffsetMinutes": 0
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
