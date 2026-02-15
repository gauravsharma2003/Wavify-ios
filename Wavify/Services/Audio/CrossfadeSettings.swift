//
//  CrossfadeSettings.swift
//  Wavify
//
//  Persists crossfade preferences (enabled state and fade duration).
//

import Foundation
import Observation

@MainActor
@Observable
final class CrossfadeSettings {
    static let shared = CrossfadeSettings()

    private static let enabledKey = "wavify_crossfade_enabled"
    private static let durationKey = "wavify_crossfade_duration"
    private static let premiumKey = "wavify_crossfade_premium"

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

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let stored = UserDefaults.standard.double(forKey: Self.durationKey)
        self.fadeDuration = stored > 0 ? stored : 6.0
        self.isPremium = UserDefaults.standard.bool(forKey: Self.premiumKey)
    }
}
