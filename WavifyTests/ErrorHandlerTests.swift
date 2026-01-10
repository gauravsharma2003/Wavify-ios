//
//  ErrorHandlerTests.swift
//  WavifyTests
//
//  Unit tests for ErrorHandler utility
//

import Testing
import Foundation
@testable import Wavify

@Suite("ErrorHandler Tests")
struct ErrorHandlerTests {
    
    // MARK: - User Messages
    
    @Test func testGenericErrorMessage() {
        let error = NSError(domain: "Test", code: 0)
        let message = ErrorHandler.userMessage(for: error)
        #expect(message == "Something went wrong. Please try again")
    }
    
    @Test func testURLErrorNotConnectedMessage() {
        let error = URLError(.notConnectedToInternet)
        let message = ErrorHandler.userMessage(for: error)
        #expect(message == "Check your internet connection and try again")
    }
    
    @Test func testURLErrorTimedOutMessage() {
        let error = URLError(.timedOut)
        let message = ErrorHandler.userMessage(for: error)
        #expect(message == "Request timed out. Please try again")
    }
    
    @Test func testURLErrorCannotFindHostMessage() {
        let error = URLError(.cannotFindHost)
        let message = ErrorHandler.userMessage(for: error)
        #expect(message == "Unable to connect to the server")
    }
    
    // MARK: - Error Classification
    
    @Test func testNetworkErrorIsRetryable() {
        let error = URLError(.timedOut)
        #expect(ErrorHandler.isRetryable(error) == true)
    }
    
    @Test func testNotConnectedIsRetryable() {
        let error = URLError(.notConnectedToInternet)
        #expect(ErrorHandler.isRetryable(error) == true)
    }
    
    @Test func testGenericErrorIsNotRetryable() {
        let error = NSError(domain: "Test", code: 0)
        #expect(ErrorHandler.isRetryable(error) == false)
    }
    
    @Test func testBadURLIsNotRetryable() {
        let error = URLError(.badURL)
        #expect(ErrorHandler.isRetryable(error) == false)
    }
}
