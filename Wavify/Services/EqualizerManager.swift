//
//  EqualizerManager.swift
//  Wavify
//
//  Manages equalizer settings with UserDefaults persistence
//

import Foundation
import Observation
import Combine

/// Singleton manager for equalizer settings persistence and state
@MainActor
@Observable
class EqualizerManager {
    static let shared = EqualizerManager()
    
    // MARK: - Public State
    
    /// Current equalizer settings
    private(set) var settings: EqualizerSettings = .default
    
    /// Publisher for settings changes
    let settingsDidChange = PassthroughSubject<EqualizerSettings, Never>()
    
    // MARK: - Private

    private let userDefaultsKey = "wavify_equalizer_settings"

    // MARK: - Initialization

    private init() {
        // Load settings on background thread to avoid blocking main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            let loadedSettings = Self.loadSettingsFromDisk()
            await MainActor.run {
                if let loadedSettings = loadedSettings {
                    self?.settings = loadedSettings
                    self?.notifyChange()
                }
            }
        }
    }

    /// Load settings from disk (can be called from any thread)
    nonisolated private static func loadSettingsFromDisk() -> EqualizerSettings? {
        guard let data = UserDefaults.standard.data(forKey: "wavify_equalizer_settings") else {
            return nil
        }

        do {
            return try JSONDecoder().decode(EqualizerSettings.self, from: data)
        } catch {
            return nil
        }
    }
    
    // MARK: - Public API
    
    /// Apply a preset
    func applyPreset(_ preset: EqualizerPreset) {
        settings.applyPreset(preset)
        saveSettings()
        notifyChange()
    }
    
    /// Update a single band gain
    func updateBandGain(at index: Int, gain: Float) {
        settings.updateBand(at: index, gain: gain)
        saveSettings()
        notifyChange()
    }
    
    /// Toggle equalizer enabled state
    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        saveSettings()
        notifyChange()
    }
    
    /// Reset to default (flat)
    func reset() {
        settings.reset()
        saveSettings()
        notifyChange()
    }
    
    /// Save current settings
    func save() {
        saveSettings()
        notifyChange()
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return
        }
        
        do {
            settings = try JSONDecoder().decode(EqualizerSettings.self, from: data)
        } catch {
            Logger.error("Failed to decode equalizer settings", category: .playback, error: error)
            settings = .default
        }
    }
    
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Logger.error("Failed to encode equalizer settings", category: .playback, error: error)
        }
    }
    
    private func notifyChange() {
        settingsDidChange.send(settings)
    }
}
