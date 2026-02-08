//
//  APIRequestManager.swift
//  Wavify
//
//  Centralized request handling with deduplication and connection pooling
//

import Foundation

/// Actor-based request manager with deduplication support
actor APIRequestManager {
    static let shared = APIRequestManager()
    
    // MARK: - Properties
    
    /// Shared URL session with optimized configuration
    nonisolated let session: URLSession
    
    /// In-flight requests for deduplication (keyed by request identifier)
    private var inFlightRequests: [String: Task<Data, Error>] = [:]
    
    /// Request cache for short-term caching (keyed by request identifier)
    private var requestCache: [String: CachedResponse] = [:]
    
    /// Cache duration in seconds
    private let cacheDuration: TimeInterval = 30
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        config.urlCache = URLCache(
            memoryCapacity: 50_000_000,  // 50 MB
            diskCapacity: 100_000_000,    // 100 MB
            diskPath: "youtube_api_cache"
        )
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Request Execution
    
    /// Execute a request with optional deduplication
    /// - Parameters:
    ///   - request: The URLRequest to execute
    ///   - deduplicationKey: Optional key for deduplication. If provided, concurrent identical requests will share the same network call
    ///   - cacheable: Whether to cache the response
    /// - Returns: Response data
    func execute(
        _ request: URLRequest,
        deduplicationKey: String? = nil,
        cacheable: Bool = false
    ) async throws -> Data {
        let key = deduplicationKey ?? UUID().uuidString
        
        // Check cache first
        if cacheable, let cached = requestCache[key], !cached.isExpired {
            return cached.data
        }
        
        // Check for in-flight request
        if let existingTask = inFlightRequests[key] {
            return try await existingTask.value
        }
        
        // Create new request task
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(for: request)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw YouTubeMusicError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw YouTubeMusicError.httpError(httpResponse.statusCode)
            }
            
            return data
        }
        
        // Store in-flight request
        inFlightRequests[key] = task
        
        do {
            let data = try await task.value
            
            // Cache if requested
            if cacheable {
                requestCache[key] = CachedResponse(data: data, timestamp: Date())
            }
            
            // Remove from in-flight
            inFlightRequests.removeValue(forKey: key)
            
            return data
        } catch {
            // Remove from in-flight on error
            inFlightRequests.removeValue(forKey: key)
            throw error
        }
    }
    
    /// Clear expired cache entries
    func clearExpiredCache() {
        let now = Date()
        requestCache = requestCache.filter { !$0.value.isExpired(at: now) }
    }
    
    /// Clear all cache
    func clearCache() {
        requestCache.removeAll()
    }

    /// Clear a specific cache entry by key
    func clearCacheEntry(forKey key: String) {
        requestCache.removeValue(forKey: key)
    }
    
    // MARK: - Convenience Methods
    
    /// Create a POST request with JSON body
    nonisolated func createRequest(
        endpoint: String,
        body: [String: Any],
        headers: [String: String],
        baseURL: String = YouTubeAPIContext.baseURL
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?prettyPrint=false") else {
            throw YouTubeMusicError.parseError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return request
    }
}

// MARK: - Supporting Types

private struct CachedResponse {
    let data: Data
    let timestamp: Date
    
    var isExpired: Bool {
        isExpired(at: Date())
    }
    
    func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince(timestamp) > 30 // 30 second cache
    }
}
