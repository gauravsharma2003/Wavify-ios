//
//  EqualizerPreset.swift
//  Wavify
//
//  Equalizer preset definitions and band configurations
//

import Foundation

// MARK: - Equalizer Preset

/// Available equalizer presets with predefined band gains
enum EqualizerPreset: String, Codable, CaseIterable, Identifiable {
    case flat = "Flat"
    case megaBass = "Mega Bass"
    case pop = "Pop"
    case jazz = "Jazz"
    case rock = "Rock"
    case classical = "Classical"
    case hiphop = "Hip Hop"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    /// SF Symbol icon for the preset
    var icon: String {
        switch self {
        case .flat: return "slider.horizontal.3"
        case .megaBass: return "speaker.wave.3.fill"
        case .pop: return "music.note"
        case .jazz: return "music.quarternote.3"
        case .rock: return "guitars.fill"
        case .classical: return "pianokeys"
        case .hiphop: return "beats.headphones"
        case .custom: return "slider.vertical.3"
        }
    }
    
    /// Pre-configured gain values for 10-band EQ (in dB, range -12 to +12)
    /// Frequencies: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    /// Note: Values kept very conservative (max ±4dB) for clean, distortion-free audio
    var bandGains: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .megaBass:
            // Deep bass boost, balanced mids and highs
            return [4, 3.5, 3, 2, 0, 0, 0, 0.5, 1, 1]
        case .pop:
            // V-shaped: gentle bass and treble lift, slight mid scoop
            return [2, 1.5, 1, 0, -0.5, -0.5, 0, 1.5, 2, 2]
        case .jazz:
            // Warm and smooth with slight sparkle
            return [1.5, 1.5, 1, 0.5, 0, 0.5, 1, 1.5, 1, 0.5]
        case .rock:
            // Punchy with forward presence
            return [3, 2.5, 2, 1, 0, 0.5, 1.5, 1.5, 1, 0.5]
        case .classical:
            // Natural with subtle high-end air
            return [0, 0, 0, 0, 0, 0, 0, 0.5, 1, 1]
        case .hiphop:
            // Deep bass with clear vocals
            return [4, 3, 2, 0.5, 0, 0, 0.5, 1, 1.5, 1.5]
        case .custom:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}

// MARK: - Equalizer Band

/// Represents a single EQ band with its frequency and current gain
struct EqualizerBand: Identifiable, Codable, Equatable {
    let id: Int
    let frequency: Float // Hz
    let label: String
    var gain: Float // dB (-12 to +12)
    
    /// Standard 10-band EQ frequencies
    static let standardBands: [EqualizerBand] = [
        EqualizerBand(id: 0, frequency: 32, label: "32", gain: 0),
        EqualizerBand(id: 1, frequency: 64, label: "64", gain: 0),
        EqualizerBand(id: 2, frequency: 125, label: "125", gain: 0),
        EqualizerBand(id: 3, frequency: 250, label: "250", gain: 0),
        EqualizerBand(id: 4, frequency: 500, label: "500", gain: 0),
        EqualizerBand(id: 5, frequency: 1000, label: "1K", gain: 0),
        EqualizerBand(id: 6, frequency: 2000, label: "2K", gain: 0),
        EqualizerBand(id: 7, frequency: 4000, label: "4K", gain: 0),
        EqualizerBand(id: 8, frequency: 8000, label: "8K", gain: 0),
        EqualizerBand(id: 9, frequency: 16000, label: "16K", gain: 0)
    ]
}

// MARK: - Equalizer Settings

/// Persistent equalizer settings
struct EqualizerSettings: Codable, Equatable {
    var selectedPreset: EqualizerPreset
    var bands: [EqualizerBand]
    var isEnabled: Bool
    
    /// Default flat settings
    static let `default` = EqualizerSettings(
        selectedPreset: .flat,
        bands: EqualizerBand.standardBands,
        isEnabled: true
    )
    
    /// Apply a preset to the bands
    mutating func applyPreset(_ preset: EqualizerPreset) {
        guard preset != .custom else { return }
        selectedPreset = preset
        let gains = preset.bandGains
        for i in bands.indices {
            bands[i].gain = gains[i]
        }
    }
    
    /// Update a single band's gain (switches to custom preset)
    mutating func updateBand(at index: Int, gain: Float) {
        guard index >= 0 && index < bands.count else { return }
        bands[index].gain = max(-12, min(12, gain))
        selectedPreset = .custom
    }
    
    /// Reset to flat
    mutating func reset() {
        selectedPreset = .flat
        for i in bands.indices {
            bands[i].gain = 0
        }
    }
}
