//
//  MemoryPressureHandler.swift
//  Wavify
//
//  Handles memory pressure events to free up resources
//

import UIKit

final class MemoryPressureHandler {
    static let shared = MemoryPressureHandler()
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        // Clear image cache
        ImageCache.shared.clearMemory()
        Logger.log("Cleared image cache due to memory pressure", category: .cache)
    }
    
    /// Call this early in app lifecycle to initialize the handler
    func initialize() {
        // Handler is initialized via shared singleton
        Logger.log("MemoryPressureHandler initialized", category: .cache)
    }
}
