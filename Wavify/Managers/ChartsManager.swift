import Foundation

/// Manages caching of chart data to prevent repeated API calls and UI re-renders
@MainActor
class ChartsManager {
    static let shared = ChartsManager()
    
    // Cached chart data
    private(set) var trendingSongs: [SearchResult] = []
    private(set) var topSongs: [SearchResult] = []
    private(set) var global100Songs: [SearchResult] = []
    private(set) var us100Songs: [SearchResult] = []
    private(set) var languageCharts: [LanguageChart] = []
    
    // Track if we've loaded data at least once
    private(set) var hasLoaded = false
    
    // Last refresh timestamp
    private var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 30 * 60 // 30 minutes
    
    private let networkManager = NetworkManager.shared
    
    private init() {}
    
    /// Check if cached data exists
    var hasCachedData: Bool {
        return !trendingSongs.isEmpty || !global100Songs.isEmpty || !us100Songs.isEmpty || !languageCharts.isEmpty
    }
    
    /// Check if data needs refresh (older than refresh interval)
    var needsRefresh: Bool {
        guard let lastRefresh = lastRefreshTime else { return true }
        return Date().timeIntervalSince(lastRefresh) > refreshInterval
    }
    
    /// Load cached charts (returns immediately with cached data)
    func loadCached() -> (trending: [SearchResult], top: [SearchResult], global100: [SearchResult], us100: [SearchResult]) {
        return (trendingSongs, topSongs, global100Songs, us100Songs)
    }
    
    /// Fetch charts from network (updates cache silently)
    func refreshInBackground() async {
        guard needsRefresh || !hasLoaded else { return }
        
        async let trendingTask = fetchTrendingSongs()
        async let global100Task = fetchPlaylistSongs(playlistId: "PL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i")
        async let us100Task = fetchPlaylistSongs(playlistId: "PL4fGSI1pDJn5rIKIW3OMVshdTCVy4a_EL")
        async let languageChartsTask = fetchLanguageCharts()
        
        let (trending, global100, us100, langCharts) = await (trendingTask, global100Task, us100Task, languageChartsTask)
        
        // Only update cache if we got valid data (don't clear existing cache on failure)
        if !trending.isEmpty {
            self.trendingSongs = Array(trending.prefix(20))
            self.topSongs = Array(trending.dropFirst(20).prefix(20))
        }
        if !global100.isEmpty {
            self.global100Songs = Array(global100.prefix(30))
        }
        if !us100.isEmpty {
            self.us100Songs = Array(us100.prefix(30))
        }
        if !langCharts.isEmpty {
            self.languageCharts = langCharts
        }
        
        // Only mark as loaded and update timestamp if we got at least some data
        if !trending.isEmpty || !global100.isEmpty || !us100.isEmpty || !langCharts.isEmpty {
            self.hasLoaded = true
            self.lastRefreshTime = Date()
        }
    }
    
    /// Force refresh (for pull-to-refresh)
    func forceRefresh() async {
        // Don't reset lastRefreshTime before fetch - only reset after successful fetch
        // This prevents the guard condition from blocking if first attempt fails
        let previousRefreshTime = lastRefreshTime
        lastRefreshTime = nil // Allow refresh to proceed
        
        async let trendingTask = fetchTrendingSongs()
        async let global100Task = fetchPlaylistSongs(playlistId: "PL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i")
        async let us100Task = fetchPlaylistSongs(playlistId: "PL4fGSI1pDJn5rIKIW3OMVshdTCVy4a_EL")
        async let languageChartsTask = fetchLanguageCharts()
        
        let (trending, global100, us100, langCharts) = await (trendingTask, global100Task, us100Task, languageChartsTask)
        
        // Only update cache if we got valid data
        var gotData = false
        if !trending.isEmpty {
            self.trendingSongs = Array(trending.prefix(20))
            self.topSongs = Array(trending.dropFirst(20).prefix(20))
            gotData = true
        }
        if !global100.isEmpty {
            self.global100Songs = Array(global100.prefix(30))
            gotData = true
        }
        if !us100.isEmpty {
            self.us100Songs = Array(us100.prefix(30))
            gotData = true
        }
        if !langCharts.isEmpty {
            self.languageCharts = langCharts
            gotData = true
        }
        
        if gotData {
            self.lastRefreshTime = Date()
        } else {
            // Restore previous refresh time so we don't keep trying failed refreshes
            self.lastRefreshTime = previousRefreshTime
        }
    }
    
    // MARK: - Private Fetch Methods
    
    private func fetchTrendingSongs() async -> [SearchResult] {
        do {
            let explorePage = try await networkManager.getCharts(country: nil)
            for section in explorePage.sections {
                let songs = section.items.filter { $0.type == .song }
                if !songs.isEmpty {
                    return songs
                }
            }
            return explorePage.sections.first?.items ?? []
        } catch {
            Logger.error("Trending fetch failed", category: .charts, error: error)
            return []
        }
    }
    
    private func fetchPlaylistSongs(playlistId: String) async -> [SearchResult] {
        do {
            let songs = try await networkManager.getQueueSongs(playlistId: playlistId)
            return songs.map { queueSong in
                SearchResult(
                    id: queueSong.id,
                    name: queueSong.name,
                    thumbnailUrl: queueSong.thumbnailUrl,
                    isExplicit: false,
                    year: queueSong.duration,
                    artist: queueSong.artist,
                    type: .song,
                    artistId: queueSong.artistId
                )
            }
        } catch {
            Logger.error("Playlist \(playlistId) fetch failed", category: .charts, error: error)
            return []
        }
    }
    
    /// Fetch language charts dynamically from FEmusic_charts API
    private func fetchLanguageCharts() async -> [LanguageChart] {
        do {
            let chartsData = try await networkManager.getLanguageCharts()
            
            // Fetch first 3 songs for each language chart concurrently
            var charts: [LanguageChart] = []
            
            await withTaskGroup(of: LanguageChart?.self) { group in
                for chartInfo in chartsData {
                    group.addTask {
                        // Remove VL prefix if present for fetchPlaylistSongs
                        let playlistId = chartInfo.playlistId.hasPrefix("VL") 
                            ? String(chartInfo.playlistId.dropFirst(2)) 
                            : chartInfo.playlistId
                        
                        let songs = await self.fetchPlaylistSongs(playlistId: playlistId)
                        let first3Songs = Array(songs.prefix(3))
                        
                        // Use the chart's own thumbnail from API (not first song)
                        return LanguageChart(
                            id: chartInfo.playlistId,
                            name: chartInfo.name,
                            playlistId: chartInfo.playlistId,
                            thumbnailUrl: chartInfo.thumbnailUrl,
                            songs: first3Songs
                        )
                    }
                }
                
                for await chart in group {
                    if let chart = chart, !chart.songs.isEmpty {
                        charts.append(chart)
                    }
                }
            }
            
            // Sort to maintain consistent order
            return charts.sorted { $0.name < $1.name }
        } catch {
            Logger.error("Language charts fetch failed", category: .charts, error: error)
            return []
        }
    }
}
