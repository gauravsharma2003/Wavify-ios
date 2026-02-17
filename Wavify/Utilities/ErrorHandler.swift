//
//  ErrorHandler.swift
//  Wavify
//
//  User-friendly error handling with retry mechanisms
//

import Foundation

// MARK: - Error Handler

enum ErrorHandler {
    
    // MARK: - User Messages
    
    /// Get a user-friendly message for an error
    static func userMessage(for error: Error) -> String {
        if let streamError = error as? StreamExtractorError {
            switch streamError {
            case .allStrategiesFailed:
                return "Unable to play this song. Please try again later"
            case .urlValidationFailed:
                return "This song is temporarily unavailable"
            default:
                return "Playback error. Please try again"
            }
        }

        if let ytError = error as? YouTubeMusicError {
            return userMessage(for: ytError)
        }
        
        // Handle URL errors (network connectivity)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Check your internet connection and try again"
            case .timedOut:
                return "Request timed out. Please try again"
            case .cannotFindHost, .cannotConnectToHost:
                return "Unable to connect to the server"
            default:
                return "A network error occurred. Please try again"
            }
        }
        
        // Generic fallback
        return "Something went wrong. Please try again"
    }
    
    /// Get a user-friendly message for YouTube Music errors
    static func userMessage(for error: YouTubeMusicError) -> String {
        switch error {
        case .networkError:
            return "Check your internet connection and try again"
        case .playbackNotAvailable:
            return "This song is not available for playback"
        case .noResults:
            return "No results found. Try a different search"
        case .invalidURL:
            return "Unable to load content"
        case .unsupportedFormat:
            return "This audio format is not supported"
        case .parseError:
            return "Unable to load content. Please try again"
        case .invalidResponse:
            return "Unable to process the response. Please try again"
        case .httpError(let statusCode):
            if statusCode >= 500 {
                return "Server error. Please try again later"
            } else if statusCode == 429 {
                return "Too many requests. Please wait a moment"
            } else if statusCode == 403 {
                return "Access denied"
            } else if statusCode == 404 {
                return "Content not found"
            } else {
                return "An error occurred. Please try again"
            }
        }
    }
    
    // MARK: - Error Classification
    
    /// Check if an error is recoverable with retry
    static func isRetryable(_ error: Error) -> Bool {
        if let streamError = error as? StreamExtractorError {
            switch streamError {
            case .networkError, .urlValidationFailed, .allStrategiesFailed:
                return true
            default:
                return false
            }
        }

        if let ytError = error as? YouTubeMusicError {
            switch ytError {
            case .networkError:
                return true
            case .httpError(let code) where code >= 500 || code == 429:
                return true
            default:
                return false
            }
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Retry Logic
    
    /// Retry an async operation with exponential backoff
    static func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry if error is not retryable
                guard isRetryable(error) && attempt < maxAttempts else {
                    throw error
                }
                
                Logger.warning(
                    "Attempt \(attempt) failed, retrying in \(delay)s",
                    category: .network
                )
                
                try? await Task.sleep(for: .seconds(delay))
                delay *= 2 // Exponential backoff
            }
        }
        
        throw lastError ?? YouTubeMusicError.networkError(NSError(domain: "Unknown", code: -1))
    }
}
