//
//  ShuffleControllerTests.swift
//  WavifyTests
//
//  Unit tests for ShuffleController
//

import Testing
@testable import Wavify

@Suite("ShuffleController Tests")
struct ShuffleControllerTests {

    @Test func testInitiallyNotShuffling() async {
        await MainActor.run {
            let controller = ShuffleController()
            #expect(controller.isShuffleMode == false)
        }
    }

    @Test func testInitialLoopModeIsNone() async {
        await MainActor.run {
            let controller = ShuffleController()
            #expect(controller.loopMode == .none)
        }
    }

    @Test func testEnableShuffle() async {
        await MainActor.run {
            let controller = ShuffleController()
            controller.enableShuffle(queueSize: 10, currentIndex: 0)
            #expect(controller.isShuffleMode == true)
        }
    }

    @Test func testDisableShuffle() async {
        await MainActor.run {
            let controller = ShuffleController()
            controller.enableShuffle(queueSize: 10, currentIndex: 0)
            controller.disableShuffle()
            #expect(controller.isShuffleMode == false)
        }
    }

    @Test func testToggleLoopMode() async {
        await MainActor.run {
            let controller = ShuffleController()
            #expect(controller.loopMode == .none)
            controller.toggleLoopMode()
            #expect(controller.loopMode == .all)
            controller.toggleLoopMode()
            #expect(controller.loopMode == .one)
            controller.toggleLoopMode()
            #expect(controller.loopMode == .none)
        }
    }

    @Test func testShuffleIndicesGenerated() async {
        await MainActor.run {
            let controller = ShuffleController()
            controller.enableShuffle(queueSize: 5, currentIndex: 0)
            let nextIndex = controller.getNextShuffleIndex()
            #expect(nextIndex != nil)
        }
    }
}
