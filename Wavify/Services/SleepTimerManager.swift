//
//  SleepTimerManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation
import Observation

@MainActor
@Observable
class SleepTimerManager {
    static let shared = SleepTimerManager()
    
    // MARK: - Observable Properties
    
    var isActive: Bool = false
    var remainingSeconds: Int = 0
    var selectedDurationMinutes: Int = 0
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    
    private init() {}
    
    // MARK: - Computed Properties
    
    var formattedRemainingTime: String {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Timer Control
    
    func start(minutes: Int) {
        stop() // Clear any existing timer
        
        selectedDurationMinutes = minutes
        remainingSeconds = minutes * 60
        isActive = true
        
        // Create timer on main run loop
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Ensure timer fires even when scrolling
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
        selectedDurationMinutes = 0
    }
    
    func addTime(minutes: Int) {
        guard isActive else { return }
        remainingSeconds += minutes * 60
        selectedDurationMinutes += minutes
    }
    
    // MARK: - Private Methods
    
    private func tick() {
        guard isActive else { return }
        
        remainingSeconds -= 1
        
        if remainingSeconds <= 0 {
            // Timer completed - pause audio
            AudioPlayer.shared.pause()
            stop()
        }
    }
}
