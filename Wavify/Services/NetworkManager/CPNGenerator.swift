//
//  CPNGenerator.swift
//  Wavify
//
//  Generates Client Playback Nonce for YouTube playback tracking
//

import Foundation

enum CPNGenerator {
    private static let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    static func generate() -> String {
        String((0..<16).map { _ in chars.randomElement()! })
    }
}
