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

    /// Reel item endpoint — the Shorts player API. Still serves direct audio URLs
    /// for the ANDROID client when the normal /player endpoint returns HTTP 400.
    static let reelItemURL = "https://youtubei.googleapis.com/youtubei/v1/reel/reel_item_watch"
    
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
    /// Newer ANDROID client version used by the reel_item_watch endpoint.
    /// Reference: Musicality-App uses v21.03.36 to bypass HTTP 400 on legacy /player.
    static let androidReelVersion = "21.03.36"
    static let androidReelUserAgent = "com.google.android.youtube/\(androidReelVersion) (Linux; U; Android 15; GB) gzip"
    static let androidVRVersion = "1.71.26"
    static let iosClientVersion = "19.29.1"
    static let tvVersion = "7.20250120.10.00"
    static let tvEmbedVersion = "2.0"
    static let webEmbedVersion = "2.20250120.01.00"
    static let mwebVersion = "2.20250120.01.00"
    
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
            "Origin": "https://www.youtube.com",
            "User-Agent": "com.google.android.youtube/\(androidVersion) (Linux; U; Android 11) gzip",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }

    /// Headers for the reel_item_watch endpoint. Intentionally minimal —
    /// the visitor ID lives in the body context, not a header here, and
    /// `x-goog-api-format-version: 2` matches the Musicality-App reference.
    static var androidReelHeaders: [String: String] {
        [
            "User-Agent": androidReelUserAgent,
            "X-Goog-Api-Format-Version": "2",
            "Content-Type": "application/json",
            "Accept-Language": "en-GB, en;q=0.9"
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

    /// Context for the reel_item_watch endpoint. Uses the newer ANDROID v21
    /// client version with WATCH screen and explicit visitorData in the body.
    static var androidReelContext: [String: Any] {
        [
            "client": [
                "clientName": "ANDROID",
                "clientVersion": androidReelVersion,
                "clientScreen": "WATCH",
                "platform": "MOBILE",
                "visitorData": visitorData ?? incognitoVisitorData,
                "osName": "Android",
                "osVersion": "16",
                "androidSdkVersion": 36,
                "hl": "en-GB",
                "gl": "GB",
                "utcOffsetMinutes": 0
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

    // MARK: - TV Client (TVHTML5)

    static var tvClientHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
            "X-Youtube-Client-Name": "7",
            "X-Youtube-Client-Version": tvVersion,
            "Origin": "https://www.youtube.com",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }

    static var tvClientContext: [String: Any] {
        [
            "client": [
                "clientName": "TVHTML5",
                "clientVersion": tvVersion,
                "hl": "en",
                "gl": "US",
                "timeZone": "UTC",
                "utcOffsetMinutes": 0
            ]
        ]
    }

    // MARK: - TV Embedded Client

    static var tvEmbedHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
            "X-Youtube-Client-Name": "85",
            "X-Youtube-Client-Version": tvEmbedVersion,
            "Origin": "https://www.youtube.com",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }

    static var tvEmbedContext: [String: Any] {
        [
            "client": [
                "clientName": "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                "clientVersion": tvEmbedVersion,
                "hl": "en",
                "gl": "US",
                "timeZone": "UTC",
                "utcOffsetMinutes": 0
            ]
        ]
    }

    // MARK: - Web Embedded Client

    static var webEmbedHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": YouTubeStreamExtractor.webUserAgent,
            "X-Youtube-Client-Name": "56",
            "X-Youtube-Client-Version": webEmbedVersion,
            "Origin": "https://www.youtube.com",
            "Referer": "https://www.youtube.com/",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }

    static var webEmbedContext: [String: Any] {
        [
            "client": [
                "clientName": "WEB_EMBEDDED_PLAYER",
                "clientVersion": webEmbedVersion,
                "hl": "en",
                "gl": "US"
            ]
        ]
    }

    // MARK: - MWEB Client

    static var mwebHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
            "X-Youtube-Client-Name": "2",
            "X-Youtube-Client-Version": mwebVersion,
            "Origin": "https://m.youtube.com",
            "Referer": "https://m.youtube.com/",
            "X-Goog-Visitor-Id": visitorData ?? incognitoVisitorData
        ]
    }

    static var mwebContext: [String: Any] {
        [
            "client": [
                "clientName": "MWEB",
                "clientVersion": mwebVersion,
                "hl": "en",
                "gl": "US"
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
