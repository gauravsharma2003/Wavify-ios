//
//  CrossfadeSettings.swift
//  Wavify
//
//  Persists crossfade preferences (enabled state, fade duration, transition style).
//

import Foundation
import Observation

enum TransitionStyle: String, CaseIterable, Codable {
    case auto   = "Auto"
    case smooth = "Smooth"
    case djMix  = "DJ Mix"
    case drop   = "Drop"
}

@MainActor
@Observable
final class CrossfadeSettings {
    static let shared = CrossfadeSettings()

    private static let enabledKey = "wavify_crossfade_enabled"
    private static let durationKey = "wavify_crossfade_duration"
    private static let premiumKey = "wavify_crossfade_premium"
    private static let styleKey = "wavify_crossfade_style"
    private static let barsKey = "wavify_crossfade_bars"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var fadeDuration: Double {
        didSet { UserDefaults.standard.set(fadeDuration, forKey: Self.durationKey) }
    }

    /// Premium stem-based crossfade (instruments/bass first, vocals linger)
    var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: Self.premiumKey) }
    }

    /// Transition style preset (Smooth, DJ Mix, Drop)
    var transitionStyle: TransitionStyle {
        didSet { UserDefaults.standard.set(transitionStyle.rawValue, forKey: Self.styleKey) }
    }

    /// Fade length expressed in musical bars (4/4 time). Used by Premium when
    /// the active track's BeatTracker is confident; otherwise `fadeDuration`
    /// (seconds) is used as a fallback. Default 4 bars; clamped to [2, 8].
    var fadeBars: Int {
        didSet {
            let clamped = min(8, max(2, fadeBars))
            if clamped != fadeBars { fadeBars = clamped; return }
            UserDefaults.standard.set(fadeBars, forKey: Self.barsKey)
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let stored = UserDefaults.standard.double(forKey: Self.durationKey)
        self.fadeDuration = stored > 0 ? stored : 6.0
        self.isPremium = UserDefaults.standard.bool(forKey: Self.premiumKey)
        if let raw = UserDefaults.standard.string(forKey: Self.styleKey),
           let style = TransitionStyle(rawValue: raw) {
            self.transitionStyle = style
        } else {
            self.transitionStyle = .auto
        }
        let storedBars = UserDefaults.standard.integer(forKey: Self.barsKey)
        self.fadeBars = storedBars >= 2 && storedBars <= 8 ? storedBars : 4
    }
}
