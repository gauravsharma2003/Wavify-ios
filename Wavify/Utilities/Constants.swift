//
//  Constants.swift
//  Wavify
//
//  Centralized constants for the app
//

import SwiftUI

// MARK: - App Constants

enum AppConstants {
    
    // MARK: - Animation
    
    enum Animation {
        static let defaultDuration: Double = 0.3
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.85
        static let interactiveSpringResponse: Double = 0.15
        static let longDuration: Double = 0.6
    }
    
    // MARK: - UI
    
    enum UI {
        static let cornerRadius: CGFloat = 12
        static let largeCornerRadius: CGFloat = 24
        static let sheetCornerRadius: CGFloat = 40
        static let standardPadding: CGFloat = 16
        static let compactPadding: CGFloat = 8
        static let largePadding: CGFloat = 24
        static let buttonSize: CGFloat = 44
        static let largeButtonSize: CGFloat = 60
        static let playButtonSize: CGFloat = 80
    }
    
    // MARK: - Cache
    
    enum Cache {
        static let diskSizeLimitMB = 200
        static let diskSizeLimit = diskSizeLimitMB * 1024 * 1024
        static let memoryCountLimit = 100
    }
    
    // MARK: - Network
    
    enum Network {
        static let defaultRetryAttempts = 3
        static let initialRetryDelay: TimeInterval = 1.0
        static let requestTimeout: TimeInterval = 30.0
    }
    
    // MARK: - Playback
    
    enum Playback {
        static let seekBackThreshold: Double = 3.0 // seconds
        static let dismissDragThreshold: CGFloat = 0.25 // percentage of screen
        static let dismissVelocityThreshold: CGFloat = 400
    }
    
    // MARK: - Content
    
    enum Content {
        static let maxRecentHistory = 100
        static let maxRecommendations = 20
        static let maxFavourites = 8
    }
}
