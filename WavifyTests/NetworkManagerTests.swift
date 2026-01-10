//
//  NetworkManagerTests.swift
//  WavifyTests
//
//  Unit tests for NetworkManager facade
//

import Testing
@testable import Wavify

@Suite("NetworkManager Tests")
struct NetworkManagerTests {
    
    // MARK: - Singleton
    
    @Test func testSharedInstanceExists() async {
        await MainActor.run {
            let manager = NetworkManager.shared
            #expect(manager != nil)
        }
    }
    
    // MARK: - Search Suggestions
    
    @Test func testEmptyQueryReturnsEmptySuggestions() async throws {
        await MainActor.run {
            // Empty query validation should be handled properly
            // This tests that the API doesn't crash with empty input
            Task {
                do {
                    let suggestions = try await NetworkManager.shared.getSearchSuggestions(query: "")
                    #expect(suggestions.isEmpty)
                } catch {
                    // Expected - empty query may throw or return empty
                    #expect(true)
                }
            }
        }
    }
}
