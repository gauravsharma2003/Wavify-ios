//
//  SearchAPIService.swift
//  Wavify
//
//  Search suggestions and search results API
//

import Foundation

/// Service for search-related API calls
@MainActor
final class SearchAPIService {
    static let shared = SearchAPIService()
    
    private let requestManager = APIRequestManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get search suggestions for a query
    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion] {
        guard !query.isEmpty else { return [] }
        
        let body: [String: Any] = [
            "input": query,
            "context": YouTubeAPIContext.webContext
        ]
        
        let request = try requestManager.createRequest(
            endpoint: "music/get_search_suggestions",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let data = try await requestManager.execute(
            request,
            deduplicationKey: "suggestions_\(query)"
        )
        
        return parseSuggestions(data)
    }
    
    /// Search for songs, albums, artists, playlists
    func search(query: String, params: String? = nil) async throws -> (topResults: [SearchResult], results: [SearchResult]) {
        guard !query.isEmpty else { return ([], []) }
        
        var body: [String: Any] = [
            "query": query,
            "context": YouTubeAPIContext.webContext
        ]
        
        if let params = params {
            body["params"] = params
        }
        
        let request = try requestManager.createRequest(
            endpoint: "search",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let dedupeKey = params != nil ? "search_\(query)_\(params!)" : "search_\(query)"
        let data = try await requestManager.execute(request, deduplicationKey: dedupeKey)
        
        return parseSearchResults(data)
    }
    
    // MARK: - Parsing
    
    private nonisolated func parseSuggestions(_ data: Data) -> [SearchSuggestion] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [[String: Any]] else { return [] }
        
        var suggestions: [SearchSuggestion] = []
        
        for content in contents {
            if let section = content["searchSuggestionsSectionRenderer"] as? [String: Any],
               let sectionContents = section["contents"] as? [[String: Any]] {
                
                for item in sectionContents {
                    // Parse text suggestions
                    if let renderer = item["searchSuggestionRenderer"] as? [String: Any],
                       let endpoint = renderer["navigationEndpoint"] as? [String: Any],
                       let searchEndpoint = endpoint["searchEndpoint"] as? [String: Any],
                       let query = searchEndpoint["query"] as? String {
                        suggestions.append(.text(query))
                    }
                    
                    // Parse rich results (songs, artists, etc.)
                    if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                       let result = ResponseParser.parseListItem(listItem) {
                        suggestions.append(.result(result))
                    }
                }
            }
        }
        
        return suggestions
    }
    
    private nonisolated func parseSearchResults(_ data: Data) -> (topResults: [SearchResult], results: [SearchResult]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let tabbedResults = contents["tabbedSearchResultsRenderer"] as? [String: Any],
              let tabs = tabbedResults["tabs"] as? [[String: Any]] else { return ([], []) }
        
        var topResults: [SearchResult] = []
        var results: [SearchResult] = []
        
        for tab in tabs {
            if let tabRenderer = tab["tabRenderer"] as? [String: Any],
               let content = tabRenderer["content"] as? [String: Any],
               let sectionList = content["sectionListRenderer"] as? [String: Any],
               let sections = sectionList["contents"] as? [[String: Any]] {
                
                for section in sections {
                    // Parse Top Results from musicCardShelfRenderer
                    if let cardShelf = section["musicCardShelfRenderer"] as? [String: Any] {
                        if let topResult = parseCardShelfItem(cardShelf) {
                            topResults.append(topResult)
                        }
                        // Also parse nested contents in card shelf
                        if let cardContents = cardShelf["contents"] as? [[String: Any]] {
                            for item in cardContents {
                                if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                                   let result = ResponseParser.parseListItem(listItem) {
                                    topResults.append(result)
                                }
                            }
                        }
                    }
                    
                    // Parse regular results from musicShelfRenderer
                    if let shelf = section["musicShelfRenderer"] as? [String: Any],
                       let items = shelf["contents"] as? [[String: Any]] {
                        
                        for item in items {
                            if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                               let result = ResponseParser.parseListItem(listItem) {
                                results.append(result)
                            }
                        }
                    }
                }
            }
        }
        
        return (topResults, results)
    }
    
    private nonisolated func parseCardShelfItem(_ cardShelf: [String: Any]) -> SearchResult? {
        // Extract title
        guard let title = cardShelf["title"] as? [String: Any],
              let titleRuns = title["runs"] as? [[String: Any]],
              let firstTitleRun = titleRuns.first,
              let name = firstTitleRun["text"] as? String else { return nil }
        
        // Extract thumbnail
        var thumbnailUrl = ""
        if let thumbnail = cardShelf["thumbnail"] as? [String: Any],
           let musicThumbnail = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            thumbnailUrl = url
        }
        
        // Extract subtitle for artist info AND artistId
        var artist = ""
        var artistId: String? = nil
        if let subtitle = cardShelf["subtitle"] as? [String: Any],
           let subtitleRuns = subtitle["runs"] as? [[String: Any]] {
            
            // Look for artist with navigation endpoint (UC channel or music artist)
            for run in subtitleRuns {
                if let text = run["text"] as? String,
                   text != "•" && text != " • " && !text.isEmpty {
                    if let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                       let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                       let browseId = browseEndpoint["browseId"] as? String {
                        if artist.isEmpty {
                            artist = text
                            artistId = browseId
                        }
                        break
                    }
                }
            }
            
            // Fallback
            if artist.isEmpty && subtitleRuns.count > 2, let text = subtitleRuns[2]["text"] as? String {
                artist = text
            } else if artist.isEmpty, let firstRun = subtitleRuns.first, let text = firstRun["text"] as? String, text != "Video" && text != "Song" {
                artist = text
            }
        }
        
        // Determine type and ID from navigation endpoint
        if let navigationEndpoint = cardShelf["onTap"] as? [String: Any] {
            if let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
               let videoId = watchEndpoint["videoId"] as? String {
                return SearchResult(id: videoId, name: name, thumbnailUrl: thumbnailUrl,
                                    isExplicit: false, year: "", artist: artist, type: .song, artistId: artistId)
            }
            
            if let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                
                if browseId.hasPrefix("UC") {
                    return SearchResult(id: browseId, name: name, thumbnailUrl: thumbnailUrl,
                                        isExplicit: false, year: "", artist: artist, type: .artist)
                } else if browseId.hasPrefix("MPREb_") {
                    return SearchResult(id: browseId, name: name, thumbnailUrl: thumbnailUrl,
                                        isExplicit: false, year: "", artist: artist, type: .album)
                } else if browseId.hasPrefix("VL") {
                    return SearchResult(id: browseId, name: name, thumbnailUrl: thumbnailUrl,
                                        isExplicit: false, year: "", artist: artist, type: .playlist)
                }
            }
        }
        
        return nil
    }
}
