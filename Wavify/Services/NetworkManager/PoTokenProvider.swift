//
//  PoTokenProvider.swift
//  Wavify
//
//  Proof of Origin Token provider placeholder.
//  Currently returns nil — IOS/ANDROID clients work without PoToken.
//  YouTube's WEB clients now require BotGuard + SABR (protobuf) protocol,
//  making PoToken unnecessary for our mobile-client approach.
//

import Foundation

actor PoTokenProvider {
    static let shared = PoTokenProvider()

    private init() {}

    /// Get a PoToken for a video.
    /// Currently always returns nil — IOS/ANDROID clients don't need PoToken.
    func getToken(videoId: String) async -> String? {
        return nil
    }
}
