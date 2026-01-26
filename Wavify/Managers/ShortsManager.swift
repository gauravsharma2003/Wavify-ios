import Foundation
import Observation

/// Manages fetching and caching of "Trending in Shorts" data
@MainActor
@Observable
class ShortsManager {
    static let shared = ShortsManager()
    
    // Cached shorts data
    private(set) var shortsSongs: [SearchResult] = []
    
    // Cache keys for persistence
    private let tokenCacheKey = "com.wavify.shorts.continuationToken"
    
    // Hardcoded fallback visitor data that is known to work for Shorts in the IN context
    private let defaultVisitorData = "CgsxaFJkTkZ5aDQ1USjJxN3LBjIKCgJJThIEGgAgPw%3D%3D"
    
    // Refresh interval: 2 hours
    private var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 120 * 60
    
    private let networkManager = NetworkManager.shared
    private let browseService = BrowseAPIService.shared
    
    private init() {}
    
    /// Check if we need to refresh data
    var needsRefresh: Bool {
        guard let lastRefresh = lastRefreshTime else { return true }
        return Date().timeIntervalSince(lastRefresh) > refreshInterval
    }
    
    /// Refresh shorts data in background
    func refreshInBackground() async {
        guard needsRefresh || shortsSongs.isEmpty else { return }
        
        if YouTubeAPIContext.visitorData == nil {
            YouTubeAPIContext.visitorData = defaultVisitorData
        }
        
        // 1. Try Fast Cache
        if let cachedToken = UserDefaults.standard.string(forKey: tokenCacheKey) {
            do {
                let songs = try await fetchShortsWithToken(cachedToken)
                if !songs.isEmpty {
                    self.shortsSongs = songs
                    self.lastRefreshTime = Date()
                    return
                }
            } catch {
                Logger.debug("Shorts Sync: Cache expired.", category: .charts)
            }
        }
        
        // 2. Sequential Search
        await performSequentialFetch()
    }
    
    /// Force refresh data
    func forceRefresh() async {
        self.lastRefreshTime = nil
        await performSequentialFetch()
    }
    
    // MARK: - Private Methods
    
    private func performSequentialFetch() async {
        do {
            let home = try await browseService.getHome()
            if await searchInSections(home.sections, sourceName: "Home Initial") { return }
            
            guard var currentToken = home.continuation else { return }
            
            for _ in 1...15 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let nextData = try await browseService.loadContinuation(token: currentToken)
                
                if await searchInSections(nextData.sections, sourceName: "Pagination", usedToken: currentToken) {
                    return
                }
                
                guard let nextToken = nextData.continuation else { break }
                currentToken = nextToken
            }
            
            // Final fallback to Explore
            let explore = try await browseService.getCharts()
            _ = await searchInSections(explore.sections, sourceName: "Explore")
            
        } catch {
            Logger.error("Shorts Sync failed", category: .charts, error: error)
        }
    }
    
    private func searchInSections(_ sections: [HomeSection], sourceName: String, usedToken: String? = nil) async -> Bool {
        if let shortsSection = sections.first(where: { 
            let t = $0.title.lowercased()
            return t.contains("shorts") || t.contains("short") 
        }) {
            self.shortsSongs = shortsSection.items
            self.lastRefreshTime = Date()
            
            if let token = usedToken {
                UserDefaults.standard.set(token, forKey: tokenCacheKey)
            }
            return true
        }
        return false
    }
    
    private func fetchShortsWithToken(_ token: String) async throws -> [SearchResult] {
        let data = try await browseService.loadContinuation(token: token)
        if let shortsSection = data.sections.first(where: { 
            let t = $0.title.lowercased()
            return t.contains("shorts") || t.contains("short") 
        }) {
            return shortsSection.items
        }
        return []
    }
}
