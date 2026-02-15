//
//  ShuffleController.swift
//  Wavify
//
//  Manages shuffle and repeat mode logic
//

import Foundation

/// Controls shuffle and repeat mode behavior
@MainActor
@Observable
class ShuffleController {
    // MARK: - State
    
    /// Whether shuffle mode is active
    var isShuffleMode = false
    
    /// Current loop mode
    var loopMode: LoopMode = .none
    
    /// Shuffled indices for the queue
    private(set) var shuffleIndices: [Int] = []
    
    /// Current position in the shuffle order
    private(set) var currentShuffleIndex: Int = 0
    
    // MARK: - Shuffle Management
    
    /// Enable shuffle mode for the given queue size
    func enableShuffle(queueSize: Int, currentIndex: Int) {
        isShuffleMode = true
        shuffleIndices = Array(0..<queueSize).shuffled()
        
        // Find where current index appears in shuffle and start there
        if let idx = shuffleIndices.firstIndex(of: currentIndex) {
            currentShuffleIndex = idx
        } else {
            currentShuffleIndex = 0
        }
    }
    
    /// Enable shuffle for album/playlist (random start)
    func enableShuffleForAlbum(queueSize: Int) -> Int {
        isShuffleMode = true
        shuffleIndices = Array(0..<queueSize).shuffled()
        currentShuffleIndex = 0
        return shuffleIndices[0]
    }
    
    /// Disable shuffle mode
    func disableShuffle() {
        isShuffleMode = false
        shuffleIndices = []
        currentShuffleIndex = 0
    }
    
    /// Toggle shuffle mode
    func toggleShuffle(queueSize: Int, currentIndex: Int) {
        if isShuffleMode {
            disableShuffle()
        } else {
            enableShuffle(queueSize: queueSize, currentIndex: currentIndex)
        }
    }
    
    /// Sync shuffle index when jumping to a specific queue index
    func syncShuffleIndex(to queueIndex: Int) {
        if isShuffleMode {
            if let idx = shuffleIndices.firstIndex(of: queueIndex) {
                currentShuffleIndex = idx
            }
        }
    }
    
    // MARK: - Navigation
    
    /// Peek at the next index in shuffle order WITHOUT advancing the position
    func peekNextShuffleIndex() -> Int? {
        guard isShuffleMode && !shuffleIndices.isEmpty else { return nil }

        let nextShuffleIndex = currentShuffleIndex + 1

        if nextShuffleIndex < shuffleIndices.count {
            return shuffleIndices[nextShuffleIndex]
        } else if loopMode == .all {
            return shuffleIndices[0]
        }

        return nil
    }

    /// Get the next index in shuffle order
    /// Returns nil if at end and not looping
    func getNextShuffleIndex() -> Int? {
        guard isShuffleMode && !shuffleIndices.isEmpty else { return nil }
        
        let nextShuffleIndex = currentShuffleIndex + 1
        
        if nextShuffleIndex < shuffleIndices.count {
            currentShuffleIndex = nextShuffleIndex
            return shuffleIndices[currentShuffleIndex]
        } else if loopMode == .all {
            // Loop back to start of shuffle
            currentShuffleIndex = 0
            return shuffleIndices[0]
        }
        
        return nil
    }
    
    /// Get the previous index in shuffle order
    /// Returns nil if at start
    func getPreviousShuffleIndex() -> Int? {
        guard isShuffleMode && currentShuffleIndex > 0 else { return nil }
        
        currentShuffleIndex -= 1
        return shuffleIndices[currentShuffleIndex]
    }
    
    /// Get current queue index from shuffle
    var currentQueueIndex: Int? {
        guard isShuffleMode && currentShuffleIndex < shuffleIndices.count else { return nil }
        return shuffleIndices[currentShuffleIndex]
    }
    
    // MARK: - Loop Mode
    
    /// Toggle to next loop mode
    func toggleLoopMode() {
        loopMode = loopMode.next()
    }
    
    /// Check if we should loop the current song
    var shouldLoopCurrentSong: Bool {
        loopMode == .one
    }
    
    /// Check if we should loop the queue
    var shouldLoopQueue: Bool {
        loopMode == .all
    }
    
    /// Check if we should fetch more recommendations
    var shouldFetchRecommendations: Bool {
        loopMode == .none
    }
    
    // MARK: - Reset
    
    /// Reset all shuffle state
    func reset() {
        isShuffleMode = false
        loopMode = .none
        shuffleIndices = []
        currentShuffleIndex = 0
    }
}
