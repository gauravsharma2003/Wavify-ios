//
//  TransitionLearner.swift
//  Wavify
//
//  Tracks skip/play-through counts per (energyProfile, fadeProfile) pair.
//  After 15+ transitions, if skip rate > 40%, tries the next-best profile.
//  Storage: UserDefaults JSON, key "wavify_transition_stats".
//

import Foundation

struct TransitionStats: Codable {
    var playThroughCount: Int = 0
    var skipCount: Int = 0

    var total: Int { playThroughCount + skipCount }

    var skipRate: Float {
        guard total > 0 else { return 0 }
        return Float(skipCount) / Float(total)
    }
}

@MainActor
final class TransitionLearner {

    private static let storageKey = "wavify_transition_stats"
    private static let minTransitions = 15
    private static let skipThreshold: Float = 0.4

    private var stats: [String: TransitionStats]

    // Fallback chains per energy profile
    private static let fallbackChains: [String: [String]] = [
        "highToHigh": ["djMix", "smooth", "drop"],
        "highToLow":  ["smooth", "djMix", "drop"],
        "lowToHigh":  ["drop", "smooth", "djMix"],
        "lowToLow":   ["smooth", "djMix", "drop"]
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: TransitionStats].self, from: data) {
            self.stats = decoded
        } else {
            self.stats = [:]
        }
    }

    func recordCompletion(energy: String, profile: String) {
        let key = "\(energy)_\(profile)"
        var entry = stats[key] ?? TransitionStats()
        entry.playThroughCount += 1
        stats[key] = entry
        save()
    }

    func recordSkip(energy: String, profile: String) {
        let key = "\(energy)_\(profile)"
        var entry = stats[key] ?? TransitionStats()
        entry.skipCount += 1
        stats[key] = entry
        save()
    }

    /// Returns an alternative FadeProfile if the proposed one has a high skip rate
    func shouldUseAlternative(energy: String, proposedProfile: String) -> TransitionChoreographer.FadeProfile? {
        let key = "\(energy)_\(proposedProfile)"
        guard let entry = stats[key],
              entry.total >= Self.minTransitions,
              entry.skipRate > Self.skipThreshold else {
            return nil
        }

        // Walk the fallback chain for this energy level
        guard let chain = Self.fallbackChains[energy] else { return nil }

        for alternative in chain {
            if alternative == proposedProfile { continue }
            let altKey = "\(energy)_\(alternative)"
            let altEntry = stats[altKey] ?? TransitionStats()
            // Use alternative if it hasn't been tried enough or has acceptable skip rate
            if altEntry.total < Self.minTransitions || altEntry.skipRate <= Self.skipThreshold {
                return Self.fadeProfile(for: alternative)
            }
        }

        return nil
    }

    /// Map profile name string to FadeProfile
    private static func fadeProfile(for name: String) -> TransitionChoreographer.FadeProfile {
        switch name {
        case "djMix":  return TransitionChoreographer.djMixProfile
        case "drop":   return TransitionChoreographer.dropProfile
        default:       return TransitionChoreographer.smoothProfile
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
