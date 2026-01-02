//
//  NetworkManager.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation
import Observation

@MainActor
@Observable
class NetworkManager {
    static let shared = NetworkManager()
    
    private let baseURL = "https://music.youtube.com/youtubei/v1"
    private let session: URLSession
    
    // Client versions
    private let webRemixVersion = "1.20251208.03.00"
    private let androidVersion = "20.10.38"
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Common Headers
    
    private var webHeaders: [String: String] {
        [
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "content-type": "application/json",
            "origin": "https://music.youtube.com",
            "referer": "https://music.youtube.com/",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            "x-origin": "https://music.youtube.com"
        ]
    }
    
    private var androidHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "X-Goog-Api-Format-Version": "1",
            "X-YouTube-Client-Name": "3",
            "X-YouTube-Client-Version": androidVersion,
            "X-Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/",
            "User-Agent": "com.google.android.youtube/\(androidVersion) (Linux; U; Android 11) gzip"
        ]
    }
    
    private var webContext: [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": webRemixVersion
            ]
        ]
    }
    
    private var androidContext: [String: Any] {
        [
            "client": [
                "clientName": "ANDROID",
                "clientVersion": androidVersion,
                "gl": "US",
                "hl": "en"
            ]
        ]
    }
    
    // MARK: - Search Suggestions
    
    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion] {
        guard !query.isEmpty else { return [] }
        
        let url = URL(string: "\(baseURL)/music/get_search_suggestions?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let body: [String: Any] = [
            "input": query,
            "context": webContext
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return parseSuggestions(data)
    }
    
    private func parseSuggestions(_ data: Data) -> [SearchSuggestion] {
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
                       let result = parseListItem(listItem) {
                        suggestions.append(.result(result))
                    }
                }
            }
        }
        
        return suggestions
    }
    
    // MARK: - Search Results
    
    func search(query: String, params: String? = nil) async throws -> (topResults: [SearchResult], results: [SearchResult]) {
        guard !query.isEmpty else { return ([], []) }
        
        let url = URL(string: "\(baseURL)/search?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        var body: [String: Any] = [
            "query": query,
            "context": webContext
        ]
        
        // Add filter params if provided
        if let params = params {
            body["params"] = params
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return parseSearchResults(data)
    }
    
    private func parseSearchResults(_ data: Data) -> (topResults: [SearchResult], results: [SearchResult]) {
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
                                   let result = parseListItem(listItem) {
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
                               let result = parseListItem(listItem) {
                                results.append(result)
                            }
                        }
                    }
                }
            }
        }
        
        return (topResults, results)
    }
    
    private func parseCardShelfItem(_ cardShelf: [String: Any]) -> SearchResult? {
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
        
        // Extract subtitle for artist info
        var artist = ""
        if let subtitle = cardShelf["subtitle"] as? [String: Any],
           let subtitleRuns = subtitle["runs"] as? [[String: Any]],
           let firstSubtitleRun = subtitleRuns.first,
           let subtitleText = firstSubtitleRun["text"] as? String {
            artist = subtitleText
        }
        
        // Determine type and ID from navigation endpoint
        if let navigationEndpoint = cardShelf["onTap"] as? [String: Any] {
            if let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
               let videoId = watchEndpoint["videoId"] as? String {
                return SearchResult(id: videoId, name: name, thumbnailUrl: thumbnailUrl,
                                    isExplicit: false, year: "", artist: artist, type: .song)
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
    
    private func parseListItem(_ item: [String: Any]) -> SearchResult? {
        // Extract title from flexColumns
        guard let flexColumns = item["flexColumns"] as? [[String: Any]],
              let firstColumn = flexColumns.first,
              let columnRenderer = firstColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = columnRenderer["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]],
              let firstRun = runs.first,
              let title = firstRun["text"] as? String else { return nil }
        
        let thumbnailUrl = extractThumbnailUrl(from: item)
        let isExplicit = checkIfExplicit(item)
        let year = extractYear(from: item)
        let artistInfo = extractArtistInfo(from: item)
        let artist = artistInfo.name
        let artistId = artistInfo.id
        
        // Determine type and ID
        if let navigationEndpoint = item["navigationEndpoint"] as? [String: Any] {
            if let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
               let videoId = watchEndpoint["videoId"] as? String {
                return SearchResult(id: videoId, name: title, thumbnailUrl: thumbnailUrl,
                                    isExplicit: isExplicit, year: year, artist: artist, type: .song, artistId: artistId)
            }
            
            if let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                
                if browseId.hasPrefix("UC") {
                    return SearchResult(id: browseId, name: title, thumbnailUrl: thumbnailUrl,
                                        isExplicit: isExplicit, year: year, artist: artist, type: .artist)
                } else if browseId.hasPrefix("MPREb_") {
                    return SearchResult(id: browseId, name: title, thumbnailUrl: thumbnailUrl,
                                        isExplicit: isExplicit, year: year, artist: artist, type: .album)
                } else if browseId.hasPrefix("VL") {
                    return SearchResult(id: browseId, name: title, thumbnailUrl: thumbnailUrl,
                                        isExplicit: isExplicit, year: year, artist: artist, type: .playlist)
                }
            }
        }
        
        // Check for videoId in overlay
        if let overlay = item["overlay"] as? [String: Any],
           let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = overlayRenderer["content"] as? [String: Any],
           let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
           let playEndpoint = playButton["playNavigationEndpoint"] as? [String: Any],
           let watchEndpoint = playEndpoint["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String {
            return SearchResult(id: videoId, name: title, thumbnailUrl: thumbnailUrl,
                                isExplicit: isExplicit, year: year, artist: artist, type: .song, artistId: artistId)
        }
        
        // Check playlistItemData
        if let playlistData = item["playlistItemData"] as? [String: Any],
           let videoId = playlistData["videoId"] as? String {
            return SearchResult(id: videoId, name: title, thumbnailUrl: thumbnailUrl,
                                isExplicit: isExplicit, year: year, artist: artist, type: .song, artistId: artistId)
        }
        
        return nil
    }
    
    private func extractThumbnailUrl(from item: [String: Any]) -> String {
        if let thumbnail = item["thumbnail"] as? [String: Any],
           let musicThumbnail = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    private func checkIfExplicit(_ item: [String: Any]) -> Bool {
        if let badges = item["badges"] as? [[String: Any]] {
            for badge in badges {
                if let badgeRenderer = badge["musicInlineBadgeRenderer"] as? [String: Any],
                   let icon = badgeRenderer["icon"] as? [String: Any],
                   let iconType = icon["iconType"] as? String,
                   iconType == "MUSIC_EXPLICIT_BADGE" {
                    return true
                }
            }
        }
        return false
    }
    
    private func extractYear(from item: [String: Any]) -> String {
        if let flexColumns = item["flexColumns"] as? [[String: Any]] {
            for column in flexColumns {
                if let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                   let text = renderer["text"] as? [String: Any],
                   let runs = text["runs"] as? [[String: Any]] {
                    for run in runs {
                        if let textValue = run["text"] as? String,
                           textValue.count == 4,
                           Int(textValue) != nil {
                            return textValue
                        }
                    }
                }
            }
        }
        return ""
    }
    
    private func extractArtist(from item: [String: Any]) -> String {
        return extractArtistInfo(from: item).name
    }

    private func extractArtistInfo(from item: [String: Any]) -> (name: String, id: String?) {
        if let flexColumns = item["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
            let secondColumn = flexColumns[1]
            if let renderer = secondColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
               let text = renderer["text"] as? [String: Any],
               let runs = text["runs"] as? [[String: Any]] {
                
                // Iterate through runs to find artist
                for (index, run) in runs.enumerated() {
                    if let text = run["text"] as? String {
                        // Check if this run links to an artist channel (starts with UC)
                        if let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                           let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                           let browseId = browseEndpoint["browseId"] as? String,
                           browseId.hasPrefix("UC") {
                            return (text, browseId)
                        }
                        
                        // If it's the first run and looks like an artist (fallback if no link or different link)
                        if index == 0 {
                             return (text, nil)
                        }
                    }
                }
                
                // Fallback: return first run text as name
                if let firstRun = runs.first, let text = firstRun["text"] as? String {
                    return (text, nil)
                }
            }
        }
        return ("", nil)
    }
    
    // MARK: - Player API
    
    func getPlaybackInfo(videoId: String) async throws -> PlaybackInfo {
        let url = URL(string: "\(baseURL)/player?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        androidHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let body: [String: Any] = [
            "videoId": videoId,
            "context": androidContext
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return try parsePlaybackResponse(data)
    }
    
    private func parsePlaybackResponse(_ data: Data) throws -> PlaybackInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let playabilityStatus = json["playabilityStatus"] as? [String: Any],
              let status = playabilityStatus["status"] as? String,
              status == "OK",
              let streamingData = json["streamingData"] as? [String: Any],
              let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]],
              let videoDetails = json["videoDetails"] as? [String: Any] else {
            throw YouTubeMusicError.invalidResponse
        }
        
        // Filter for audio-only formats (no width)
        let audioFormats = adaptiveFormats.filter { format in
            guard format["width"] == nil else { return false }
            
            if let mimeType = format["mimeType"] as? String {
                return mimeType.contains("audio/mp4") || mimeType.contains("audio/m4a")
            }
            return false
        }.sorted { format1, format2 in
            let bitrate1 = format1["bitrate"] as? Int ?? 0
            let bitrate2 = format2["bitrate"] as? Int ?? 0
            return bitrate1 > bitrate2
        }
        
        // Fallback to any audio format
        let fallbackFormats = adaptiveFormats.filter { $0["width"] == nil }
        let selectedFormats = audioFormats.isEmpty ? fallbackFormats : audioFormats
        
        guard let bestFormat = selectedFormats.first,
              let audioUrl = bestFormat["url"] as? String,
              let videoId = videoDetails["videoId"] as? String,
              let title = videoDetails["title"] as? String,
              let lengthSeconds = videoDetails["lengthSeconds"] as? String,
              let author = videoDetails["author"] as? String else {
            throw YouTubeMusicError.unsupportedFormat
        }
        
        let viewCount = videoDetails["viewCount"] as? String ?? "0"
        let artistId = videoDetails["channelId"] as? String
        let thumbnailUrl = extractThumbnailFromVideoDetails(videoDetails)
        
        // Attempt to extract albumId from microformat
        var albumId: String? = nil
        if let microformat = json["microformat"] as? [String: Any],
           let renderer = microformat["playerMicroformatRenderer"] as? [String: Any] {
            // Sometimes album info is embedded or we might rely on other fields
            // For now, YouTube Music player API is tricky with album ID in player endpoint
            // It's often better fetched from 'next' endpoint (Watch Next)
        }
        
        return PlaybackInfo(
            audioUrl: audioUrl,
            videoId: videoId,
            title: title,
            duration: lengthSeconds,
            thumbnailUrl: thumbnailUrl,
            artist: author,
            viewCount: viewCount,
            artistId: artistId,
            albumId: albumId
        )
    }
    
    private func extractThumbnailFromVideoDetails(_ details: [String: Any]) -> String {
        if let thumbnail = details["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    // MARK: - Queue/Related Songs
    
    func getRelatedSongs(videoId: String) async throws -> [QueueSong] {
        // Step 1: Get playlist ID
        let playlistId = try await getPlaylistId(videoId: videoId)
        
        // Step 2: Get full queue
        return try await getQueueSongs(playlistId: playlistId)
    }
    
    private func getPlaylistId(videoId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/next?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let body: [String: Any] = [
            "videoId": videoId,
            "context": webContext
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbedRenderer = singleColumn["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbedRenderer["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let queueRenderer = content["musicQueueRenderer"] as? [String: Any],
              let queueContent = queueRenderer["content"] as? [String: Any],
              let playlistPanel = queueContent["playlistPanelRenderer"] as? [String: Any],
              let panelContents = playlistPanel["contents"] as? [[String: Any]] else {
            throw YouTubeMusicError.parseError("Failed to parse queue response")
        }
        
        for item in panelContents {
            if let videoRenderer = item["playlistPanelVideoRenderer"] as? [String: Any],
               let itemVideoId = videoRenderer["videoId"] as? String,
               itemVideoId == videoId,
               let menu = videoRenderer["menu"] as? [String: Any],
               let menuRenderer = menu["menuRenderer"] as? [String: Any],
               let items = menuRenderer["items"] as? [[String: Any]] {
                
                for menuItem in items {
                    if let navItem = menuItem["menuNavigationItemRenderer"] as? [String: Any],
                       let endpoint = navItem["navigationEndpoint"] as? [String: Any],
                       let watchEndpoint = endpoint["watchEndpoint"] as? [String: Any],
                       let playlistId = watchEndpoint["playlistId"] as? String {
                        return playlistId
                    }
                }
            }
        }
        
        throw YouTubeMusicError.parseError("Playlist ID not found")
    }
    
    private func getQueueSongs(playlistId: String) async throws -> [QueueSong] {
        let url = URL(string: "\(baseURL)/next?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let body: [String: Any] = [
            "playlistId": playlistId,
            "context": webContext
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return parseQueueResponse(data)
    }
    
    private func parseQueueResponse(_ data: Data) -> [QueueSong] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any],
              let tabbedRenderer = singleColumn["tabbedRenderer"] as? [String: Any],
              let watchNext = tabbedRenderer["watchNextTabbedResultsRenderer"] as? [String: Any],
              let tabs = watchNext["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let queueRenderer = content["musicQueueRenderer"] as? [String: Any],
              let queueContent = queueRenderer["content"] as? [String: Any],
              let playlistPanel = queueContent["playlistPanelRenderer"] as? [String: Any],
              let panelContents = playlistPanel["contents"] as? [[String: Any]] else {
            return []
        }
        
        var songs: [QueueSong] = []
        
        for item in panelContents {
            if let videoRenderer = item["playlistPanelVideoRenderer"] as? [String: Any],
               let videoId = videoRenderer["videoId"] as? String {
                
                let title = extractTitleFromVideoRenderer(videoRenderer)
                let artist = extractArtistFromVideoRenderer(videoRenderer)
                let thumbnailUrl = extractThumbnailFromVideoRenderer(videoRenderer)
                let duration = extractDurationFromVideoRenderer(videoRenderer)
                
                songs.append(QueueSong(
                    id: videoId,
                    name: title,
                    artist: artist,
                    thumbnailUrl: thumbnailUrl,
                    duration: duration
                ))
            }
        }
        
        return songs
    }
    
    private func extractTitleFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let title = renderer["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    private func extractArtistFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let byline = renderer["longBylineText"] as? [String: Any],
           let runs = byline["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    private func extractThumbnailFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let thumbnail = renderer["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    private func extractDurationFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let lengthText = renderer["lengthText"] as? [String: Any],
           let runs = lengthText["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    // MARK: - Album/Browse API
    
    func getAlbumDetails(albumId: String) async throws -> AlbumDetail {
        let url = URL(string: "\(baseURL)/browse?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        let body: [String: Any] = [
            "browseId": albumId,
            "context": webContext
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return try parseAlbumResponse(data, albumId: albumId)
    }
    
    private func parseAlbumResponse(_ data: Data, albumId: String) throws -> AlbumDetail {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = twoColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
              let content = tabRenderer["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]],
              let firstSection = sections.first,
              let header = firstSection["musicResponsiveHeaderRenderer"] as? [String: Any] else {
            throw YouTubeMusicError.parseError("Failed to parse album response")
        }
        
        // Extract album metadata
        let albumThumbnail = extractAlbumThumbnail(header)
        let albumName = extractAlbumName(header)
        let artist = extractAlbumArtist(header)
        let artistThumbnail = extractArtistThumbnail(header)
        let (songCount, duration) = extractAlbumInfo(header)
        
        // Extract songs
        var songs: [AlbumSong] = []
        if let secondaryContents = twoColumn["secondaryContents"] as? [String: Any],
           let secondarySectionList = secondaryContents["sectionListRenderer"] as? [String: Any],
           let secondarySections = secondarySectionList["contents"] as? [[String: Any]],
           let musicShelfSection = secondarySections.first,
           let musicShelf = musicShelfSection["musicShelfRenderer"] as? [String: Any],
           let shelfContents = musicShelf["contents"] as? [[String: Any]] {
            
            for item in shelfContents {
                if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                   let playlistData = listItem["playlistItemData"] as? [String: Any],
                   let videoId = playlistData["videoId"] as? String {
                    
                    let title = extractSongTitle(listItem)
                    let viewCount = extractViewCount(listItem)
                    let duration = extractSongDuration(listItem)
                    
                    songs.append(AlbumSong(id: videoId, title: title, viewCount: viewCount, duration: duration))
                }
            }
        }
        
        // Extract related albums
        var relatedAlbums: [RelatedAlbum] = []
        if let secondaryContents = twoColumn["secondaryContents"] as? [String: Any],
           let secondarySectionList = secondaryContents["sectionListRenderer"] as? [String: Any],
           let secondarySections = secondarySectionList["contents"] as? [[String: Any]] {
            
            for section in secondarySections {
                if let carousel = section["musicCarouselShelfRenderer"] as? [String: Any],
                   let carouselContents = carousel["contents"] as? [[String: Any]] {
                    
                    for item in carouselContents {
                        if let twoRow = item["musicTwoRowItemRenderer"] as? [String: Any] {
                            if let related = parseRelatedAlbum(twoRow) {
                                relatedAlbums.append(related)
                            }
                        }
                    }
                }
            }
        }
        
        return AlbumDetail(
            albumId: albumId,
            albumThumbnail: albumThumbnail,
            albumName: albumName,
            artist: artist,
            artistThumbnail: artistThumbnail,
            songCount: songCount,
            duration: duration,
            songs: songs,
            relatedAlbums: relatedAlbums
        )
    }
    
    private func extractAlbumThumbnail(_ header: [String: Any]) -> String {
        if let thumbnail = header["thumbnail"] as? [String: Any],
           let musicThumbnail = thumbnail["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    private func extractAlbumName(_ header: [String: Any]) -> String {
        if let title = header["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    private func extractAlbumArtist(_ header: [String: Any]) -> String {
        if let strapline = header["straplineTextOne"] as? [String: Any],
           let runs = strapline["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    private func extractArtistThumbnail(_ header: [String: Any]) -> String {
        if let strapline = header["straplineThumbnail"] as? [String: Any],
           let musicThumbnail = strapline["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let thumbnail = thumbnails.count > 2 ? thumbnails[2] : thumbnails.last,
           let url = thumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    private func extractAlbumInfo(_ header: [String: Any]) -> (String, String) {
        var songCount = ""
        var duration = ""
        
        if let subtitle = header["secondSubtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]] {
            
            var values: [String] = []
            for run in runs {
                if let text = run["text"] as? String, text != " • " {
                    values.append(text)
                }
            }
            
            if values.count >= 1 { songCount = values[0] }
            if values.count >= 2 { duration = values[1] }
        }
        
        return (songCount, duration)
    }
    
    private func extractSongTitle(_ item: [String: Any]) -> String {
        if let flexColumns = item["flexColumns"] as? [[String: Any]],
           let firstColumn = flexColumns.first,
           let renderer = firstColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let text = renderer["text"] as? [String: Any],
           let runs = text["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let title = firstRun["text"] as? String {
            return title
        }
        return ""
    }
    
    private func extractViewCount(_ item: [String: Any]) -> String {
        if let flexColumns = item["flexColumns"] as? [[String: Any]], flexColumns.count > 2 {
            let thirdColumn = flexColumns[2]
            if let renderer = thirdColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
               let text = renderer["text"] as? [String: Any],
               let runs = text["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let viewCount = firstRun["text"] as? String {
                return viewCount
            }
        }
        return ""
    }
    
    private func extractSongDuration(_ item: [String: Any]) -> String {
        if let fixedColumns = item["fixedColumns"] as? [[String: Any]],
           let firstColumn = fixedColumns.first,
           let renderer = firstColumn["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
           let text = renderer["text"] as? [String: Any],
           let runs = text["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let duration = firstRun["text"] as? String {
            return duration
        }
        return ""
    }
    
    private func parseRelatedAlbum(_ item: [String: Any]) -> RelatedAlbum? {
        guard let navigationEndpoint = item["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String else { return nil }
        
        var thumbnailUrl = ""
        if let thumbnailRenderer = item["thumbnailRenderer"] as? [String: Any],
           let musicThumbnail = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            thumbnailUrl = url
        }
        
        var albumName = ""
        if let title = item["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            albumName = text
        }
        
        var albumArtist = ""
        if let subtitle = item["subtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]], runs.count > 2 {
            if let text = runs[2]["text"] as? String {
                albumArtist = text
            }
        }
        
        return RelatedAlbum(id: browseId, name: albumName, thumbnailUrl: thumbnailUrl, artist: albumArtist)
    }
}

// MARK: - Home, Charts & Playlist API

extension NetworkManager {
    
    // MARK: - Public Methods
    
    func getHome() async throws -> HomePage {
        return try await browse(browseId: "FEmusic_home")
    }
    
    func getCharts(country: String? = nil) async throws -> HomePage {
        // "ggMGCgQIgAQ%3D" is the params for Charts
        var context = webContext
        if let country = country {
            context["client"] = [
                "clientName": "WEB_REMIX",
                "clientVersion": webRemixVersion,
                "gl": country,
                "hl": "en"
            ]
        }
        return try await browse(browseId: "FEmusic_charts", params: "ggMGCgQIgAQ%3D", context: context)
    }
    
    func getPlaylist(id: String) async throws -> HomePage {
        // Playlists use "VL" prefix usually, or we can just pass the ID if it's already full
        let browseId = id.hasPrefix("VL") ? id : "VL\(id)"
        return try await browse(browseId: browseId)
    }
    
    func loadPage(endpoint: BrowseEndpoint) async throws -> HomePage {
        return try await browse(browseId: endpoint.browseId, params: endpoint.params)
    }
    
    // MARK: - Generic Browse Implementation
    
    private func browse(browseId: String, params: String? = nil, context: [String: Any]? = nil) async throws -> HomePage {
        let url = URL(string: "\(baseURL)/browse?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        var body: [String: Any] = [
            "browseId": browseId,
            "context": context ?? webContext
        ]
        
        if let params = params {
            body["params"] = params
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return try parseBrowseResponse(data)
    }
    
    // MARK: - Parsing Logic
    
    private func parseBrowseResponse(_ data: Data) throws -> HomePage {
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
            
            // For playlists, we treat the track list as a section
            sections = parseHomeSections(sectionContents)
        }
        
        return HomePage(chips: chips, sections: sections, continuation: continuation)
    }
    
    private func parseChips(_ chipsData: [[String: Any]]) -> [Chip] {
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
    
    private func parseHomeSections(_ sectionsData: [[String: Any]]) -> [HomeSection] {
        var sections: [HomeSection] = []
        
        for sectionData in sectionsData {
            // Carousel (Horizontal)
            if let carousel = sectionData["musicCarouselShelfRenderer"] as? [String: Any] {
                if let parsedSection = parseCarouselSection(carousel) {
                    sections.append(parsedSection)
                }
            }
            // Shelf (Vertical/List)
            else if let shelf = sectionData["musicShelfRenderer"] as? [String: Any] {
                if let parsedSection = parseShelfSection(shelf) {
                    sections.append(parsedSection)
                }
            }
            // Playlist Shelf (Vertical)
            else if let playlistShelf = sectionData["musicPlaylistShelfRenderer"] as? [String: Any] {
                if let parsedSection = parsePlaylistShelfSection(playlistShelf) {
                    sections.append(parsedSection)
                }
            }
        }
        
        return sections
    }
    
    private func parseCarouselSection(_ carousel: [String: Any]) -> HomeSection? {
        // Header
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
            // Try Two Row Item
            if let twoRowItem = item["musicTwoRowItemRenderer"] as? [String: Any],
               let parsedItem = parseTwoRowItem(twoRowItem) {
                items.append(parsedItem)
            }
            // Try Responsive List Item (Chart numbers etc sometimes appear here in carousels)
            else if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                    let parsedItem = parseListItem(listItem) {
                items.append(parsedItem)
            }
        }
        
        if items.isEmpty { return nil }
        return HomeSection(title: title, strapline: strapline, items: items)
    }
    
    private func parseShelfSection(_ shelf: [String: Any]) -> HomeSection? {
        var title = ""
        var strapline: String? = nil
        
        if let titleData = shelf["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first {
            title = firstRun["text"] as? String ?? ""
        }
        
        /* Shelf normally doesn't have strapline in same way, but let's check basic fields if needed */
        
        guard let contents = shelf["contents"] as? [[String: Any]] else { return nil }
        
        var items: [SearchResult] = []
        
        for item in contents {
             if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                let parsedItem = parseListItem(listItem) {
                 items.append(parsedItem)
             }
        }
        
        if items.isEmpty { return nil }
        return HomeSection(title: title, strapline: strapline, items: items)
    }
    
    private func parsePlaylistShelfSection(_ shelf: [String: Any]) -> HomeSection? {
        // Playlist shelves often don't have intrinsic titles in the shelf itself (title is in page header)
        // We'll use a default or empty title
        let title = "Songs"
        
        guard let contents = shelf["contents"] as? [[String: Any]] else { return nil }
        
        var items: [SearchResult] = []
        
        for item in contents {
             if let listItem = item["musicResponsiveListItemRenderer"] as? [String: Any],
                let parsedItem = parseListItem(listItem) {
                 items.append(parsedItem)
             }
        }
        
        if items.isEmpty { return nil }
        return HomeSection(title: title, strapline: nil, items: items)
    }
    
    private func parseTwoRowItem(_ item: [String: Any]) -> SearchResult? {
        // Title
        var title = ""
        if let titleData = item["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first {
            title = firstRun["text"] as? String ?? ""
        }
        
        // Subtitle & Artist
        var artist = ""
        var isExplicit = false
        if let subtitleData = item["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]] {
             artist = runs.compactMap { $0["text"] as? String }.joined()
        }
        
        // Badges for explicit
        if let subtitleBadges = item["subtitleBadges"] as? [[String: Any]] {
            for badge in subtitleBadges {
                if let badgeRenderer = badge["musicInlineBadgeRenderer"] as? [String: Any],
                   let icon = badgeRenderer["icon"] as? [String: Any],
                   let type = icon["iconType"] as? String,
                   type == "MUSIC_EXPLICIT_BADGE" {
                    isExplicit = true
                }
            }
        }

        // Thumbnail
        var thumbnailUrl = ""
        if let thumbnailRenderer = item["thumbnailRenderer"] as? [String: Any],
           let musicThumbnail = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let lastThumb = thumbnails.last {
            thumbnailUrl = lastThumb["url"] as? String ?? ""
        }
        
        // Navigation Endpoint -> ID & Type
        guard let navEndpoint = item["navigationEndpoint"] as? [String: Any] else { return nil }
        
        // Check for Watch Endpoint (Song/Video)
        if let watchEndpoint = navEndpoint["watchEndpoint"] as? [String: Any],
           let videoId = watchEndpoint["videoId"] as? String {
            return SearchResult(id: videoId, name: title, thumbnailUrl: thumbnailUrl, isExplicit: isExplicit, year: "", artist: artist, type: .song)
        }
        
        // Check for Browse Endpoint (Album/Playlist/Artist)
        if let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
           let browseId = browseEndpoint["browseId"] as? String {
            
            if browseId.hasPrefix("UC") {
                return SearchResult(id: browseId, name: title, thumbnailUrl: thumbnailUrl, isExplicit: isExplicit, year: "", artist: artist, type: .artist)
            } else if browseId.hasPrefix("MPREb_") {
                return SearchResult(id: browseId, name: title, thumbnailUrl: thumbnailUrl, isExplicit: isExplicit, year: "", artist: artist, type: .album)
            } else if browseId.hasPrefix("VL") {
                return SearchResult(id: browseId, name: title, thumbnailUrl: thumbnailUrl, isExplicit: isExplicit, year: "", artist: artist, type: .playlist)
            }
        }
        
        return nil
    }
}

// MARK: - Artist Details

extension NetworkManager {
    func getArtistDetails(browseId: String) async throws -> ArtistDetail {
        let url = URL(string: "\(baseURL)/browse?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        // Add specific header for YouTube Client
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20251210.03.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        
        let clientContext: [String: Any] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20251210.03.00",
                "hl": "en"
            ]
        ]
        
        let body: [String: Any] = [
            "context": clientContext,
            "browseId": browseId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return try parseArtistDetails(data, browseId: browseId)
    }
    
    private func parseArtistDetails(_ data: Data, browseId: String) throws -> ArtistDetail {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("DEBUG: Failed to parse JSON data")
            throw YouTubeMusicError.parseError("Invalid JSON")
        }
        
        guard let contents = json["contents"] as? [String: Any] else {
            print("DEBUG: Missing 'contents'. Available keys: \(json.keys)")
            if let singleColumn = json["singleColumnBrowseResultsRenderer"] as? [String: Any] {
                 print("DEBUG: Found singleColumnBrowseResultsRenderer instead")
            }
            throw YouTubeMusicError.parseError("Invalid artist data format: missing contents")
        }
        
        // Try twoColumn first (Desktop/Web Remix)
        if let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = twoColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabContent = firstTab["tabRenderer"] as? [String: Any],
           let content = tabContent["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
             return parseArtistSectionList(sections, header: json["header"] as? [String: Any], browseId: browseId)
        }
        
        // Mobile structure fallback (singleColumn)
        if let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabContent = firstTab["tabRenderer"] as? [String: Any],
           let content = tabContent["content"] as? [String: Any],
           let sectionList = content["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
             return parseArtistSectionList(sections, header: json["header"] as? [String: Any], browseId: browseId)
        }
        
        print("DEBUG: Failed to match structure. Keys in contents: \(contents.keys)")
        if let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any] {
             print("DEBUG: Found twoColumn. Keys: \(twoColumn.keys)")
             if let tabs = twoColumn["tabs"] as? [[String: Any]] {
                 print("DEBUG: Found tabs. Count: \(tabs.count)")
                 if let firstTab = tabs.first {
                     print("DEBUG: First tab keys: \(firstTab.keys)")
                 }
             }
        }
        
        throw YouTubeMusicError.parseError("Invalid artist data format")
    }
    
    private func parseArtistSectionList(_ sections: [[String: Any]], header: [String: Any]?, browseId: String) -> ArtistDetail {
        // Parse Header
        var name = ""
        var subscribers = ""
        var thumbnailUrl = ""        

        
        if let header = header,
           let immersiveHeader = header["musicImmersiveHeaderRenderer"] as? [String: Any] {
            
            // Name
            if let title = immersiveHeader["title"] as? [String: Any],
               let runs = title["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String {
                name = text
            }
            
            // Subscribers
            if let subButton = immersiveHeader["subscriptionButton"] as? [String: Any],
               let subRenderer = subButton["subscribeButtonRenderer"] as? [String: Any],
               let subText = subRenderer["subscriberCountText"] as? [String: Any],
               let runs = subText["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String {
                subscribers = text
            }
            
            // Thumbnail
            if let thumbnailRenderer = immersiveHeader["thumbnail"] as? [String: Any],
               let musicThumbnail = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
               let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
               let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
               let lastThumbnail = thumbnails.last,
               let url = lastThumbnail["url"] as? String {
                thumbnailUrl = url
            }
        }
        
        // Parse Sections
        var artistSections: [ArtistSection] = []
        
        for sectionData in sections {
            if let musicShelf = sectionData["musicShelfRenderer"] as? [String: Any] {
                // Top Songs or list-based shelves
                if let parsedShelf = parseMusicShelf(musicShelf) {
                    artistSections.append(parsedShelf)
                }
            } else if let carouselShelf = sectionData["musicCarouselShelfRenderer"] as? [String: Any] {
                // Albums, Singles, Similar Artists
                if let parsedCarousel = parseCarouselShelf(carouselShelf) {
                    artistSections.append(parsedCarousel)
                }
            }
        }
        
        return ArtistDetail(
            id: browseId,
            name: name,
            description: nil,
            subscribers: subscribers,
            thumbnailUrl: thumbnailUrl,
            sections: artistSections
        )
    }
    
    private func parseMusicShelf(_ shelf: [String: Any]) -> ArtistSection? {
        // Get Title
        var title = ""
        if let titleData = shelf["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            title = text
        }
        
        // More robust detection for top songs sections
        let lowercaseTitle = title.lowercased()
        let type: ArtistSectionType = (
            lowercaseTitle.contains("song") || 
            lowercaseTitle.contains("track") || 
            lowercaseTitle.contains("popular") || 
            lowercaseTitle.contains("top")
        ) ? .topSongs : .unknown
        
        guard let contents = shelf["contents"] as? [[String: Any]] else { return nil }
        
        var items: [ArtistItem] = []
        
        for itemData in contents {
            if let listItem = itemData["musicResponsiveListItemRenderer"] as? [String: Any] {
                // Parse Song Item
                if let playlistItemData = listItem["playlistItemData"] as? [String: Any],
                   let videoId = playlistItemData["videoId"] as? String {
                    
                    // Title
                    var songTitle = ""
                    if let flexColumns = listItem["flexColumns"] as? [[String: Any]],
                       let firstCol = flexColumns.first,
                       let renderer = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                       let textData = renderer["text"] as? [String: Any],
                       let runs = textData["runs"] as? [[String: Any]],
                       let firstRun = runs.first {
                        songTitle = firstRun["text"] as? String ?? ""
                    }
                    
                    // Artist / Album (Subtitle)
                    var subtitle = ""
                    if let flexColumns = listItem["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
                       let secondCol = flexColumns[1]
                       if let renderer = secondCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                          let textData = renderer["text"] as? [String: Any],
                          let runs = textData["runs"] as? [[String: Any]] {
                            subtitle = runs.compactMap { $0["text"] as? String }.joined()
                       }
                    }
                    
                    // Thumbnail
                    var thumbUrl = ""
                    if let thumbRenderer = listItem["thumbnail"] as? [String: Any],
                       let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                       let thumbData = musicThumb["thumbnail"] as? [String: Any],
                       let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
                       let lastThumb = thumbnails.last {
                        thumbUrl = lastThumb["url"] as? String ?? ""
                    }
                    
                    items.append(ArtistItem(
                        id: videoId,
                        title: songTitle,
                        subtitle: subtitle,
                        thumbnailUrl: thumbUrl,
                        isExplicit: false,
                        videoId: videoId,
                        playlistId: nil,
                        browseId: nil
                    ))
                }
            }
        }
        
        // Helper to extract browseId and params
        var browseId: String?
        var params: String?
        
        if let bottomEndpoint = shelf["bottomEndpoint"] as? [String: Any],
           let browseEndpoint = bottomEndpoint["browseEndpoint"] as? [String: Any] {
            browseId = browseEndpoint["browseId"] as? String
            params = browseEndpoint["params"] as? String
        } else if let bottomText = shelf["bottomText"] as? [String: Any],
                  let runs = bottomText["runs"] as? [[String: Any]],
                  let firstRun = runs.first,
                  let endpoint = firstRun["navigationEndpoint"] as? [String: Any],
                  let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any] {
            browseId = browseEndpoint["browseId"] as? String
            params = browseEndpoint["params"] as? String
        }
        
        return ArtistSection(type: type, title: title, items: items, browseId: browseId, params: params)
    }
    
    private func parseCarouselShelf(_ shelf: [String: Any]) -> ArtistSection? {
        // Get Title
        var title = ""
        if let header = shelf["header"] as? [String: Any],
           let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
           let titleData = basicHeader["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            title = text
        }
        
        var type: ArtistSectionType = .unknown
        if title.lowercased().contains("album") { type = .albums }
        else if title.lowercased().contains("single") || title.lowercased().contains("ep") { type = .singles }
        else if title.lowercased().contains("fan") || title.lowercased().contains("like") { type = .similarArtists }
        else if title.lowercased().contains("video") { type = .videos }
        
        guard let contents = shelf["contents"] as? [[String: Any]] else { return nil }
        
        var items: [ArtistItem] = []
        
        for itemData in contents {
            if let twoRowItem = itemData["musicTwoRowItemRenderer"] as? [String: Any] {
                // Parse Album/Single/Artist
                
                // Browse ID
                var browseId: String?
                if let navEndpoint = twoRowItem["navigationEndpoint"] as? [String: Any],
                   let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any] {
                    browseId = browseEndpoint["browseId"] as? String
                }
                
                // Title
                var itemTitle = ""
                if let titleData = twoRowItem["title"] as? [String: Any],
                   let runs = titleData["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    itemTitle = firstRun["text"] as? String ?? ""
                }
                
                // Subtitle (Year • Album)
                var subtitle = ""
                if let subtitleData = twoRowItem["subtitle"] as? [String: Any],
                   let runs = subtitleData["runs"] as? [[String: Any]] {
                     subtitle = runs.compactMap { $0["text"] as? String }.joined()
                }
                
                // Thumbnail
                var thumbUrl = ""
                if let thumbRenderer = twoRowItem["thumbnailRenderer"] as? [String: Any],
                   let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                   let thumbData = musicThumb["thumbnail"] as? [String: Any],
                   let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last {
                    thumbUrl = lastThumb["url"] as? String ?? ""
                }
                
                items.append(ArtistItem(
                    id: browseId ?? UUID().uuidString,
                    title: itemTitle,
                    subtitle: subtitle,
                    thumbnailUrl: thumbUrl,
                    isExplicit: false,
                    videoId: nil,
                    playlistId: nil,
                    browseId: browseId
                ))
            }
        }
        
        if items.isEmpty { return nil }
        
        // Check for title endpoint (sometimes clicking title goes to See All)
        var sectionBrowseId: String?
        var sectionParams: String?
        
        if let header = shelf["header"] as? [String: Any],
           let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
           let titleData = basicHeader["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let endpoint = firstRun["navigationEndpoint"] as? [String: Any],
           let browseEndpoint = endpoint["browseEndpoint"] as? [String: Any] {
            sectionBrowseId = browseEndpoint["browseId"] as? String
            sectionParams = browseEndpoint["params"] as? String
        }
        
        return ArtistSection(type: type, title: title, items: items, browseId: sectionBrowseId, params: sectionParams)
    }
    
    // MARK: - Section Items (See All)
    
    // Generic method to fetch items for a section (Grid or List from See All)
    func getSectionItems(browseId: String, params: String? = nil) async throws -> [ArtistItem] {
        let url = URL(string: "\(baseURL)/browse?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        webHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        var body: [String: Any] = [
            "browseId": browseId,
            "context": webContext
        ]
        
        if let params = params {
            body["params"] = params
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await session.data(for: request)
        return try parseSectionItemsResponse(data)
    }
    
    private func parseSectionItemsResponse(_ data: Data) throws -> [ArtistItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
              let tabs = singleColumn["tabs"] as? [[String: Any]],
              let firstTab = tabs.first,
              let tabContent = firstTab["tabRenderer"] as? [String: Any],
              let content = tabContent["content"] as? [String: Any],
              let sectionList = content["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]],
              let firstSection = sections.first else {
            // Might be a playlist response (for Top Songs) which has different structure
            // Try parsing as playlist if section list fails
            if let playlistItems = try? parsePlaylistResponseAsItems(data) {
                return playlistItems
            }
             throw YouTubeMusicError.parseError("Invalid section items response")
        }
        
        // Check for Grid (Singles, Albums)
        if let gridRenderer = firstSection["gridRenderer"] as? [String: Any],
           let items = gridRenderer["items"] as? [[String: Any]] {
            return parseGridItems(items)
        }
        
        // Check for Music Shelf (List)
        if let musicShelf = firstSection["musicShelfRenderer"] as? [String: Any] {
             if let section = parseMusicShelf(musicShelf) {
                 return section.items
             }
        }
        
        return []
    }
    
    private func parseGridItems(_ items: [[String: Any]]) -> [ArtistItem] {
        var artistItems: [ArtistItem] = []
        
        for itemWrapper in items {
            if let twoRowItem = itemWrapper["musicTwoRowItemRenderer"] as? [String: Any] {
                // Parse similarly to parseCarouselShelf item logic
                
                // Browse ID
                var browseId: String?
                if let navEndpoint = twoRowItem["navigationEndpoint"] as? [String: Any],
                   let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any] {
                    browseId = browseEndpoint["browseId"] as? String
                }
                
                // Title
                var itemTitle = ""
                if let titleData = twoRowItem["title"] as? [String: Any],
                   let runs = titleData["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    itemTitle = firstRun["text"] as? String ?? ""
                }
                
                // Subtitle
                var subtitle = ""
                if let subtitleData = twoRowItem["subtitle"] as? [String: Any],
                   let runs = subtitleData["runs"] as? [[String: Any]] {
                     subtitle = runs.compactMap { $0["text"] as? String }.joined()
                }
                
                // Thumbnail
                 var thumbUrl = ""
                 if let thumbRenderer = twoRowItem["thumbnailRenderer"] as? [String: Any],
                    let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                    let thumbData = musicThumb["thumbnail"] as? [String: Any],
                    let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
                    let lastThumb = thumbnails.last {
                     thumbUrl = lastThumb["url"] as? String ?? ""
                 }
                
                artistItems.append(ArtistItem(
                    id: browseId ?? UUID().uuidString,
                    title: itemTitle,
                    subtitle: subtitle,
                    thumbnailUrl: thumbUrl,
                    isExplicit: false,
                    videoId: nil,
                    playlistId: nil,
                    browseId: browseId
                ))
            }
        }
        
        return artistItems
    }
    
    private func parsePlaylistResponseAsItems(_ data: Data) throws -> [ArtistItem] {
        // Reuse existing parseBrowseResponse or similar structure logic but extract items directly
        // Top Songs See All returns a playlist structure
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] as? [String: Any],
              let twoColumn = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
              let secondaryContents = twoColumn["secondaryContents"] as? [String: Any],
              let sectionList = secondaryContents["sectionListRenderer"] as? [String: Any],
              let sectionContents = sectionList["contents"] as? [[String: Any]],
              let firstSection = sectionContents.first,
              let musicPlaylistShelf = firstSection["musicPlaylistShelfRenderer"] as? [String: Any],
              let items = musicPlaylistShelf["contents"] as? [[String: Any]] else {
            throw YouTubeMusicError.parseError("Not a playlist response")
        }
        
        var artistItems: [ArtistItem] = []
        
        for itemData in items {
             if let listItem = itemData["musicResponsiveListItemRenderer"] as? [String: Any] {
                 // Reuse parseListItem logic but map to ArtistItem
                 if let searchResult = parseListItem(listItem) {
                     artistItems.append(ArtistItem(
                        id: searchResult.id,
                        title: searchResult.name,
                        subtitle: searchResult.artist,
                        thumbnailUrl: searchResult.thumbnailUrl,
                        isExplicit: searchResult.isExplicit,
                        videoId: searchResult.type == .song ? searchResult.id : nil,
                        playlistId: nil,
                        browseId: nil 
                     ))
                 }
             }
        }
        
        return artistItems
    }
}
