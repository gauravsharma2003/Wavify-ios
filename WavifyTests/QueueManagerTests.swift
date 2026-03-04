//
//  QueueManagerTests.swift
//  WavifyTests
//
//  Unit tests for QueueManager
//

import Testing
@testable import Wavify

@Suite("QueueManager Tests")
struct QueueManagerTests {

    @Test func testInitialQueueIsEmpty() async {
        await MainActor.run {
            let manager = QueueManager()
            #expect(manager.queue.isEmpty)
        }
    }

    @Test func testInitialIndexIsZero() async {
        await MainActor.run {
            let manager = QueueManager()
            #expect(manager.currentIndex == 0)
        }
    }

    @Test func testUserQueueInitiallyEmpty() async {
        await MainActor.run {
            let manager = QueueManager()
            #expect(manager.userQueue.isEmpty)
        }
    }

    @Test func testNotPlayingFromAlbumInitially() async {
        await MainActor.run {
            let manager = QueueManager()
            #expect(manager.isPlayingFromAlbum == false)
        }
    }

    @Test func testJumpToValidIndex() async {
        await MainActor.run {
            let manager = QueueManager()
            let song1 = Song(id: "1", title: "Song 1", artist: "Artist", thumbnailUrl: "", duration: "3:00")
            let song2 = Song(id: "2", title: "Song 2", artist: "Artist", thumbnailUrl: "", duration: "3:00")
            manager.queue = [song1, song2]

            let result = manager.jumpToIndex(1)
            #expect(result == true)
            #expect(manager.currentIndex == 1)
        }
    }

    @Test func testJumpToInvalidIndexFails() async {
        await MainActor.run {
            let manager = QueueManager()
            let result = manager.jumpToIndex(5)
            #expect(result == false)
        }
    }
}
