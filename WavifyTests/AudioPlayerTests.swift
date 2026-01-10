//
//  AudioPlayerTests.swift
//  WavifyTests
//
//  Unit tests for AudioPlayer core functionality
//

import Testing
@testable import Wavify

@Suite("AudioPlayer Tests")
struct AudioPlayerTests {
    
    // MARK: - Singleton
    
    @Test func testSharedInstanceExists() {
        let player = AudioPlayer.shared
        #expect(player != nil)
    }
    
    // MARK: - Loop Mode
    
    @Test func testLoopModeInitiallyNone() async {
        await MainActor.run {
            let player = AudioPlayer.shared
            #expect(player.loopMode == .none)
        }
    }
    
    @Test func testLoopModeCycling() {
        // Test the LoopMode enum cycling logic
        var mode = LoopMode.none
        
        mode = mode.next()
        #expect(mode == .all)
        
        mode = mode.next()
        #expect(mode == .one)
        
        mode = mode.next()
        #expect(mode == .none)
    }
    
    @Test func testLoopModeIcons() {
        #expect(LoopMode.none.icon == "repeat")
        #expect(LoopMode.one.icon == "repeat.1")
        #expect(LoopMode.all.icon == "repeat")
    }
    
    // MARK: - Play State
    
    @Test func testInitialPlayingStateIsFalse() async {
        await MainActor.run {
            let player = AudioPlayer.shared
            #expect(player.isPlaying == false)
        }
    }
    
    @Test func testInitialLoadingStateIsFalse() async {
        await MainActor.run {
            let player = AudioPlayer.shared
            #expect(player.isLoading == false)
        }
    }
    
    // MARK: - Queue
    
    @Test func testQueueIsAccessible() async {
        await MainActor.run {
            let player = AudioPlayer.shared
            // Queue should be accessible (may be empty)
            #expect(player.queue.count >= 0)
        }
    }
    
    // MARK: - Shuffle
    
    @Test func testShuffleModeInitiallyOff() async {
        await MainActor.run {
            let player = AudioPlayer.shared
            #expect(player.isShuffleMode == false)
        }
    }
}
