//
//  BrowseAPIService.swift
//  Wavify
//
//  Home, charts, playlists, and browse endpoints API
//

import Foundation

/// Service for browse-related API calls (home, charts, playlists)
@MainActor
final class BrowseAPIService {
    static let shared = BrowseAPIService()
    
    private let requestManager = APIRequestManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get home page content
    func getHome() async throws -> HomePage {
        return try await browse(browseId: "FEmusic_home")
    }
    
    /// Get charts/explore page
    func getCharts(country: String? = nil) async throws -> HomePage {
        var context = YouTubeAPIContext.webContext
        if let country = country, country != "ZZ" {
            context = YouTubeAPIContext.webContext(country: country)
        }
        return try await browse(browseId: "FEmusic_explore", params: nil, context: context)
    }
    
    /// Get trending songs from explore page
    func getTrendingSongs(country: String) async throws -> [SearchResult] {
        let context = YouTubeAPIContext.webContext(country: country)
        let explorePage = try await browse(browseId: "FEmusic_explore", params: nil, context: context)
        
        // Look for sections with songs
        for section in explorePage.sections {
            let title = section.title.lowercased()
            let songs = section.items.filter { $0.type == .song }
            if !songs.isEmpty && (title.contains("new") || title.contains("trend") || title.contains("top") || title.contains("popular") || title.contains("release")) {
                return songs
            }
        }
        
        // Fallback: return first section with song items
        for section in explorePage.sections {
            let songs = section.items.filter { $0.type == .song }
            if !songs.isEmpty {
                return songs
            }
        }
        
        return explorePage.sections.first?.items ?? []
    }
    
    /// Get playlist content
    func getPlaylist(id: String) async throws -> HomePage {
        let browseId = id.hasPrefix("VL") ? id : "VL\(id)"
        return try await browse(browseId: browseId)
    }
    
    /// Load a page from a browse endpoint
    func loadPage(endpoint: BrowseEndpoint) async throws -> HomePage {
        return try await browse(browseId: endpoint.browseId, params: endpoint.params)
    }
    
    /// Get language charts from FEmusic_charts endpoint
    /// Returns array of (name, playlistId, thumbnailUrl) for each language chart
    func getLanguageCharts() async throws -> [(name: String, playlistId: String, thumbnailUrl: String)] {
        let body: [String: Any] = [
            "browseId": "FEmusic_charts",
            "context": YouTubeAPIContext.webContext
        ]
        
        let request = try requestManager.createRequest(
            endpoint: "browse",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let data = try await requestManager.execute(request, deduplicationKey: "browse_FEmusic_charts")
        return try parseLanguageCharts(data)
    }
    
    /// Parse language charts from the "Languages" section of FEmusic_charts response
    private nonisolated func parseLanguageCharts(_ data: Data) throws -> [(name: String, playlistId: String, thumbnailUrl: String)] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabContent = firstTab["tabRenderer"] as? [String: Any],
              let content = tabContent["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionList["contents"] as? [[String: Any]] else {
            throw YouTubeMusicError.parseError("Invalid charts response")
        }
        
        var languageCharts: [(name: String, playlistId: String, thumbnailUrl: String)] = []
        
        // Find the "Languages" section (typically section index 2 in the response)
        for section in sectionContents {
            if let carousel = section["musicCarouselShelfRenderer"] as? [String: Any],
               let header = carousel["header"] as? [String: Any],
               let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
               let titleData = basicHeader["title"] as? [String: Any],
               let runs = titleData["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let sectionTitle = firstRun["text"] as? String,
               sectionTitle.lowercased().contains("language") {
                
                // Found the Languages section - parse its contents
                if let carouselContents = carousel["contents"] as? [[String: Any]] {
                    for item in carouselContents {
                        if let twoRowItem = item["musicTwoRowItemRenderer"] as? [String: Any],
                           let itemTitle = twoRowItem["title"] as? [String: Any],
                           let itemRuns = itemTitle["runs"] as? [[String: Any]],
                           let firstItemRun = itemRuns.first,
                           let name = firstItemRun["text"] as? String,
                           let navEndpoint = twoRowItem["navigationEndpoint"] as? [String: Any],
                           let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                           let playlistId = browseEndpoint["browseId"] as? String {
                            
                            // Extract thumbnail
                            var thumbnailUrl = ""
                            if let thumbRenderer = twoRowItem["thumbnailRenderer"] as? [String: Any],
                               let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                               let thumbnail = musicThumb["thumbnail"] as? [String: Any],
                               let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
                               let lastThumb = thumbnails.last,
                               let url = lastThumb["url"] as? String {
                                thumbnailUrl = url
                            }
                            
                            languageCharts.append((name: name, playlistId: playlistId, thumbnailUrl: thumbnailUrl))
                        }
                    }
                }
                break // Found Languages section, no need to continue
            }
        }
        
        return languageCharts
    }
    
    // MARK: - Private Methods
    
    private func browse(browseId: String, params: String? = nil, context: [String: Any]? = nil) async throws -> HomePage {
        var body: [String: Any] = [
            "browseId": browseId,
            "context": context ?? YouTubeAPIContext.webContext
        ]
        
        if let params = params {
            body["params"] = params
        }
        
        let request = try requestManager.createRequest(
            endpoint: "browse",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let dedupeKey = params != nil ? "browse_\(browseId)_\(params!)" : "browse_\(browseId)"
        let data = try await requestManager.execute(request, deduplicationKey: dedupeKey)
        
        return try parseBrowseResponse(data)
    }
    
    // MARK: - Parsing
    
    private nonisolated func parseBrowseResponse(_ data: Data) throws -> HomePage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any] else {
            throw YouTubeMusicError.parseError("Invalid browse response")
        }
        
        var chips: [Chip] = []
        var sections: [HomeSection] = []
        var continuation: String? = nil
        
        // Handle Single Column (Home, Charts)
        if let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabContent = firstTab["tabRenderer"] as? [String: Any],
           let content = tabContent["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any] {
            
            // Parse Chips
            if let header = sectionList["header"] as? [String: Any],
               let chipCloud = header["chipCloudRenderer"] as? [String: Any],
               let chipsArray = chipCloud["chips"] as? [[String: Any]] {
                chips = parseChips(chipsArray)
            }
            
            // Parse Sections
            if let sectionContents = sectionList["contents"] as? [[String: Any]] {
                sections = parseHomeSections(sectionContents)
            }
            
            // Parse Continuation
            if let continuations = sectionList["continuations"] as? [[String: Any]],
               let firstContinuation = continuations.first,
               let nextData = firstContinuation["nextContinuationData"] as? [String: Any],
               let token = nextData["continuation"] as? String {
                continuation = token
            }
        }
        // Handle Two Column (Playlists)
        else if let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
                let secondaryContents = twoColumn["secondaryContents"] as? [String: Any],
                let sectionList = secondaryContents["sectionListRenderer"] as? [String: Any],
                let sectionContents = sectionList["contents"] as? [[String: Any]] {
            
            sections = parseHomeSections(sectionContents)
        }
        
        return HomePage(chips: chips, sections: sections, continuation: continuation)
    }
    
    private nonisolated func parseChips(_ chipsData: [[String: Any]]) -> [Chip] {
        var chips: [Chip] = []
        
        for chipData in chipsData {
            if let chipRenderer = chipData["chipCloudChipRenderer"] as? [String: Any],
               let textData = chipRenderer["text"] as? [String: Any],
               let runs = textData["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let title = firstRun["text"] as? String,
               let navEndpoint = chipRenderer["navigationEndpoint"] as? [String: Any],
               let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                
                let params = browseEndpoint["params"] as? String
                let isSelected = chipRenderer["isSelected"] as? Bool ?? false
                
                chips.append(Chip(
                    title: title,
                    endpoint: BrowseEndpoint(browseId: browseId, params: params),
                    isSelected: isSelected
                ))
            }
        }
        
        return chips
    }
    
    private nonisolated func parseHomeSections(_ sectionsData: [[String: Any]]) -> [HomeSection] {
        var sections: [HomeSection] = []
        
        for sectionData in sectionsData {
            if let carousel = sectionData["musicCarouselShelfRenderer"] as? [String: Any] {
                if let parsedSection = parseCarouselSection(carousel) {
                    sections.append(parsedSection)
                }
            }
            else if let shelf = sectionData["musicShelfRenderer"] as? [String: Any] {
                if let parsedSection = parseShelfSection(shelf) {
                    sections.append(parsedSection)
                }
            }
            else if let playlistShelf = sectionData["musicPlaylistShelfRenderer"] as? [String: Any] {
                if let parsedSection = parsePlaylistShelfSection(playlistShelf) {
                    sections.append(parsedSection)
                }
            }
        }
        
        return sections
    }
    
    private nonisolated func parseCarouselSection(_ carousel: [String: Any]) -> HomeSection? {
        var title = ""
        var strapline: String? = nil
        
        if let header = carousel["header"] as? [String: Any],
           let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any] {
            
            if let titleData = basicHeader["title"] as? [String: Any],
               let runs = titleData["runs"] as? [[String: Any]],
               let firstRun = runs.first {
                title = firstRun["text"] as? String ?? ""
            }
            
            if let straplineData = basicHeader["strapline"] as? [String: Any],
               let runs = straplineData["runs"] as? [[String: Any]],
               let firstRun = runs.first {
                strapline = firstRun["text"] as? String
            }
        }
        
        guard let contents = carousel["contents"] as? [[String: Any]] else { return nil }
        
        var items: [SearchResult] = []
        
        for item in contents {
            if let twoRowItem = item["musicTwoRowItemRenderer"] as? [String: Any],
               let parsedItem = ResponseParser.parseTwoRowItem(twoRowItem) {
                items.append(parsedItem)
            }
            else if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                    let parsedItem = ResponseParser.parseListItem(listItem) {
                items.append(parsedItem)
            }
        }
        
        if items.isEmpty { return nil }
        return HomeSection(title: title, strapline: strapline, items: items)
    }
    
    private nonisolated func parseShelfSection(_ shelf: [String: Any]) -> HomeSection? {
        var title = ""
        var strapline: String? = nil
        
        if let titleData = shelf["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first {
            title = firstRun["text"] as? String ?? ""
        }
        
        guard let contents = shelf["contents"] as? [[String: Any]] else { return nil }
        
        var items: [SearchResult] = []
        
        for item in contents {
            if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
               let parsedItem = ResponseParser.parseListItem(listItem) {
                items.append(parsedItem)
            }
        }
        
        if items.isEmpty { return nil }
        return HomeSection(title: title, strapline: strapline, items: items)
    }
    
    private nonisolated func parsePlaylistShelfSection(_ shelf: [String: Any]) -> HomeSection? {
        let title = "Songs"
        
        guard let contents = shelf["contents"] as? [[String: Any]] else { return nil }
        
        var items: [SearchResult] = []
        
        for item in contents {
            if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
               let parsedItem = ResponseParser.parseListItem(listItem) {
                items.append(parsedItem)
            }
        }
        
        if items.isEmpty { return nil }
        return HomeSection(title: title, strapline: nil, items: items)
    }
}
