//
//  ArtistAPIService.swift
//  Wavify
//
//  Artist details and section items API
//

import Foundation

/// Service for artist-related API calls
@MainActor
final class ArtistAPIService {
    static let shared = ArtistAPIService()
    
    private let requestManager = APIRequestManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get artist details (top songs, albums, singles, similar artists)
    func getArtistDetails(browseId: String) async throws -> ArtistDetail {
        // Create custom headers for artist requests
        var headers = YouTubeAPIContext.webHeaders
        headers["X-YouTube-Client-Name"] = "67"
        headers["X-YouTube-Client-Version"] = "1.20251210.03.00"
        
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
        
        let request = try requestManager.createRequest(
            endpoint: "browse",
            body: body,
            headers: headers
        )
        
        let data = try await requestManager.execute(
            request,
            deduplicationKey: "artist_\(browseId)",
            cacheable: true
        )
        
        return try parseArtistDetails(data, browseId: browseId)
    }
    
    /// Get section items (See All for albums, singles, etc.)
    func getSectionItems(browseId: String, params: String? = nil) async throws -> [ArtistItem] {
        var body: [String: Any] = [
            "browseId": browseId,
            "context": YouTubeAPIContext.webContext
        ]
        
        if let params = params {
            body["params"] = params
        }
        
        let request = try requestManager.createRequest(
            endpoint: "browse",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let dedupeKey = params != nil ? "section_\(browseId)_\(params!)" : "section_\(browseId)"
        let data = try await requestManager.execute(request, deduplicationKey: dedupeKey)
        
        return try parseSectionItemsResponse(data)
    }
    
    // MARK: - Parsing
    
    private nonisolated func parseArtistDetails(_ data: Data, browseId: String) throws -> ArtistDetail {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YouTubeMusicError.parseError("Invalid JSON")
        }
        
        guard let contents = json["contents"] as? [String: Any] else {
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
        
        throw YouTubeMusicError.parseError("Invalid artist data format")
    }
    
    private nonisolated func parseArtistSectionList(_ sections: [[String: Any]], header: [String: Any]?, browseId: String) -> ArtistDetail {
        var name = ""
        var subscribers = ""
        var thumbnailUrl = ""
        var isChannel = false
        
        if let header = header {
            // Try musicImmersiveHeaderRenderer first (standard artist pages)
            if let immersiveHeader = header["musicImmersiveHeaderRenderer"] as? [String: Any] {
                if let title = immersiveHeader["title"] as? [String: Any],
                   let runs = title["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let text = firstRun["text"] as? String {
                    name = text
                }
                
                if let subButton = immersiveHeader["subscriptionButton"] as? [String: Any],
                   let subRenderer = subButton["subscribeButtonRenderer"] as? [String: Any],
                   let subText = subRenderer["subscriberCountText"] as? [String: Any],
                   let runs = subText["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let text = firstRun["text"] as? String {
                    subscribers = text
                }
                
                if let thumbnailRenderer = immersiveHeader["thumbnail"] as? [String: Any],
                   let musicThumbnail = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
                   let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
                   let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
                   let lastThumbnail = thumbnails.last,
                   let url = lastThumbnail["url"] as? String {
                    thumbnailUrl = url
                }
            }
            // Fallback to musicVisualHeaderRenderer (YouTube channel-based artists)
            else if let visualHeader = header["musicVisualHeaderRenderer"] as? [String: Any] {
                isChannel = true
                
                if let title = visualHeader["title"] as? [String: Any],
                   let runs = title["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let text = firstRun["text"] as? String {
                    name = text
                }
                
                if let subtitleTwo = visualHeader["subtitleTwo"] as? [String: Any],
                   let runs = subtitleTwo["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let text = firstRun["text"] as? String {
                    subscribers = text
                }
                
                if let foregroundThumbnail = visualHeader["foregroundThumbnail"] as? [String: Any],
                   let musicThumbnail = foregroundThumbnail["musicThumbnailRenderer"] as? [String: Any],
                   let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
                   let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
                   let lastThumbnail = thumbnails.last,
                   let url = lastThumbnail["url"] as? String {
                    thumbnailUrl = url
                }
            }
        }
        
        // Parse Sections
        var artistSections: [ArtistSection] = []
        
        for sectionData in sections {
            if let musicShelf = sectionData["musicShelfRenderer"] as? [String: Any] {
                if let parsedShelf = parseMusicShelf(musicShelf) {
                    artistSections.append(parsedShelf)
                }
            } else if let carouselShelf = sectionData["musicCarouselShelfRenderer"] as? [String: Any] {
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
            isChannel: isChannel,
            sections: artistSections
        )
    }
    
    private nonisolated func parseMusicShelf(_ shelf: [String: Any]) -> ArtistSection? {
        var title = ""
        if let titleData = shelf["title"] as? [String: Any],
           let runs = titleData["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            title = text
        }
        
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
                if let playlistItemData = listItem["playlistItemData"] as? [String: Any],
                   let videoId = playlistItemData["videoId"] as? String {
                    
                    var songTitle = ""
                    if let flexColumns = listItem["flexColumns"] as? [[String: Any]],
                       let firstCol = flexColumns.first,
                       let renderer = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                       let textData = renderer["text"] as? [String: Any],
                       let runs = textData["runs"] as? [[String: Any]],
                       let firstRun = runs.first {
                        songTitle = firstRun["text"] as? String ?? ""
                    }
                    
                    var subtitle = ""
                    if let flexColumns = listItem["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
                        let secondCol = flexColumns[1]
                        if let renderer = secondCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                           let textData = renderer["text"] as? [String: Any],
                           let runs = textData["runs"] as? [[String: Any]] {
                            subtitle = runs.compactMap { $0["text"] as? String }.joined()
                        }
                    }
                    
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
    
    private nonisolated func parseCarouselShelf(_ shelf: [String: Any]) -> ArtistSection? {
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
                var browseId: String?
                var videoId: String?
                if let navEndpoint = twoRowItem["navigationEndpoint"] as? [String: Any] {
                    if let watchEndpoint = navEndpoint["watchEndpoint"] as? [String: Any] {
                        videoId = watchEndpoint["videoId"] as? String
                    }
                    if let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any] {
                        browseId = browseEndpoint["browseId"] as? String
                    }
                }
                
                var itemTitle = ""
                if let titleData = twoRowItem["title"] as? [String: Any],
                   let runs = titleData["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    itemTitle = firstRun["text"] as? String ?? ""
                }
                
                var subtitle = ""
                if let subtitleData = twoRowItem["subtitle"] as? [String: Any],
                   let runs = subtitleData["runs"] as? [[String: Any]] {
                    subtitle = runs.compactMap { $0["text"] as? String }.joined()
                }
                
                var thumbUrl = ""
                if let thumbRenderer = twoRowItem["thumbnailRenderer"] as? [String: Any],
                   let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                   let thumbData = musicThumb["thumbnail"] as? [String: Any],
                   let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last {
                    thumbUrl = lastThumb["url"] as? String ?? ""
                }
                
                items.append(ArtistItem(
                    id: videoId ?? browseId ?? UUID().uuidString,
                    title: itemTitle,
                    subtitle: subtitle,
                    thumbnailUrl: thumbUrl,
                    isExplicit: false,
                    videoId: videoId,
                    playlistId: nil,
                    browseId: browseId
                ))
            }
        }
        
        if items.isEmpty { return nil }
        
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
    
    private nonisolated func parseSectionItemsResponse(_ data: Data) throws -> [ArtistItem] {
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
            print("[ArtistAPIService] parseSectionItemsResponse: Failed to parse singleColumnBrowseResultsRenderer structure")
            // Try parsing as playlist if section list fails
            if let playlistItems = try? parsePlaylistResponseAsItems(data) {
                print("[ArtistAPIService] Fallback to parsePlaylistResponseAsItems succeeded with \(playlistItems.count) items")
                return playlistItems
            }
            print("[ArtistAPIService] parsePlaylistResponseAsItems also failed")
            throw YouTubeMusicError.parseError("Invalid section items response")
        }
        
        // Log what renderer types exist in firstSection
        print("[ArtistAPIService] parseSectionItemsResponse: firstSection keys: \(firstSection.keys.joined(separator: ", "))")
        
        // Check for Grid (Singles, Albums)
        if let gridRenderer = firstSection["gridRenderer"] as? [String: Any],
           let items = gridRenderer["items"] as? [[String: Any]] {
            let result = parseGridItems(items)
            print("[ArtistAPIService] gridRenderer: parsed \(result.count) items")
            return result
        }
        
        // Check for Music Shelf (List)
        if let musicShelf = firstSection["musicShelfRenderer"] as? [String: Any] {
            if let section = parseMusicShelf(musicShelf) {
                print("[ArtistAPIService] musicShelfRenderer: parsed \(section.items.count) items")
                return section.items
            }
        }
        
        // Check for Music Playlist Shelf (Videos section)
        if let playlistShelf = firstSection["musicPlaylistShelfRenderer"] as? [String: Any],
           let items = playlistShelf["contents"] as? [[String: Any]] {
            let result = parsePlaylistShelfItems(items)
            print("[ArtistAPIService] musicPlaylistShelfRenderer: parsed \(result.count) items from \(items.count) contents")
            return result
        }
        
        // Check for Music Carousel Shelf (Videos shown in carousel format)
        if let carouselShelf = firstSection["musicCarouselShelfRenderer"] as? [String: Any],
           let items = carouselShelf["contents"] as? [[String: Any]] {
            let result = parseCarouselItems(items)
            print("[ArtistAPIService] musicCarouselShelfRenderer: parsed \(result.count) items from \(items.count) contents")
            return result
        }
        
        // Check for Item Section Renderer (may contain list items or error messages)
        if let itemSection = firstSection["itemSectionRenderer"] as? [String: Any],
           let sectionContents = itemSection["contents"] as? [[String: Any]] {
            print("[ArtistAPIService] itemSectionRenderer: has \(sectionContents.count) contents")
            var artistItems: [ArtistItem] = []
            for (index, itemData) in sectionContents.enumerated() {
                print("[ArtistAPIService] itemSectionRenderer content \(index) keys: \(itemData.keys.joined(separator: ", "))")
                // Check for video/song list items
                if let listItem = itemData["musicResponsiveListItemRenderer"] as? [String: Any] {
                    if let item = parseResponsiveListItem(listItem) {
                        artistItems.append(item)
                    }
                }
                // Check for messageRenderer (error message)
                if let messageRenderer = itemData["messageRenderer"] as? [String: Any],
                   let text = messageRenderer["text"] as? [String: Any],
                   let runs = text["runs"] as? [[String: Any]],
                   let firstRun = runs.first,
                   let message = firstRun["text"] as? String {
                    print("[ArtistAPIService] itemSectionRenderer contains error message: \(message)")
                }
            }
            print("[ArtistAPIService] itemSectionRenderer: parsed \(artistItems.count) items")
            return artistItems
        }
        
        print("[ArtistAPIService] parseSectionItemsResponse: No recognized renderer found, returning empty")
        return []
    }
    
    private nonisolated func parseGridItems(_ items: [[String: Any]]) -> [ArtistItem] {
        var artistItems: [ArtistItem] = []
        
        for itemWrapper in items {
            if let twoRowItem = itemWrapper["musicTwoRowItemRenderer"] as? [String: Any] {
                var browseId: String?
                if let navEndpoint = twoRowItem["navigationEndpoint"] as? [String: Any],
                   let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any] {
                    browseId = browseEndpoint["browseId"] as? String
                }
                
                var itemTitle = ""
                if let titleData = twoRowItem["title"] as? [String: Any],
                   let runs = titleData["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    itemTitle = firstRun["text"] as? String ?? ""
                }
                
                var subtitle = ""
                if let subtitleData = twoRowItem["subtitle"] as? [String: Any],
                   let runs = subtitleData["runs"] as? [[String: Any]] {
                    subtitle = runs.compactMap { $0["text"] as? String }.joined()
                }
                
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
    
    private nonisolated func parsePlaylistShelfItems(_ items: [[String: Any]]) -> [ArtistItem] {
        var artistItems: [ArtistItem] = []
        
        for itemData in items {
            if let listItem = itemData["musicResponsiveListItemRenderer"] as? [String: Any] {
                // Try to get videoId from playlistItemData first
                var videoId: String?
                if let playlistItemData = listItem["playlistItemData"] as? [String: Any] {
                    videoId = playlistItemData["videoId"] as? String
                }
                
                // Fallback: try overlay watchEndpoint
                if videoId == nil,
                   let overlay = listItem["overlay"] as? [String: Any],
                   let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                   let content = overlayRenderer["content"] as? [String: Any],
                   let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
                   let playEndpoint = playButton["playNavigationEndpoint"] as? [String: Any],
                   let watchEndpoint = playEndpoint["watchEndpoint"] as? [String: Any] {
                    videoId = watchEndpoint["videoId"] as? String
                }
                
                guard let id = videoId else { continue }
                
                // Parse title
                var title = ""
                if let flexColumns = listItem["flexColumns"] as? [[String: Any]],
                   let firstCol = flexColumns.first,
                   let renderer = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                   let textData = renderer["text"] as? [String: Any],
                   let runs = textData["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    title = firstRun["text"] as? String ?? ""
                }
                
                // Parse subtitle (artist name)
                var subtitle = ""
                if let flexColumns = listItem["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
                    let secondCol = flexColumns[1]
                    if let renderer = secondCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                       let textData = renderer["text"] as? [String: Any],
                       let runs = textData["runs"] as? [[String: Any]] {
                        subtitle = runs.compactMap { $0["text"] as? String }.joined()
                    }
                }
                
                // Parse thumbnail
                var thumbUrl = ""
                if let thumbRenderer = listItem["thumbnail"] as? [String: Any],
                   let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                   let thumbData = musicThumb["thumbnail"] as? [String: Any],
                   let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last {
                    thumbUrl = lastThumb["url"] as? String ?? ""
                }
                
                artistItems.append(ArtistItem(
                    id: id,
                    title: title,
                    subtitle: subtitle,
                    thumbnailUrl: thumbUrl,
                    isExplicit: false,
                    videoId: id,
                    playlistId: nil,
                    browseId: nil
                ))
            }
        }
        
        return artistItems
    }
    
    private nonisolated func parseCarouselItems(_ items: [[String: Any]]) -> [ArtistItem] {
        var artistItems: [ArtistItem] = []
        
        for itemData in items {
            if let twoRowItem = itemData["musicTwoRowItemRenderer"] as? [String: Any] {
                // Get video ID from watchEndpoint or browse ID from browseEndpoint
                var videoId: String?
                var browseId: String?
                
                if let navEndpoint = twoRowItem["navigationEndpoint"] as? [String: Any] {
                    if let watchEndpoint = navEndpoint["watchEndpoint"] as? [String: Any] {
                        videoId = watchEndpoint["videoId"] as? String
                    }
                    if let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any] {
                        browseId = browseEndpoint["browseId"] as? String
                    }
                }
                
                let itemId = videoId ?? browseId ?? UUID().uuidString
                
                var itemTitle = ""
                if let titleData = twoRowItem["title"] as? [String: Any],
                   let runs = titleData["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    itemTitle = firstRun["text"] as? String ?? ""
                }
                
                var subtitle = ""
                if let subtitleData = twoRowItem["subtitle"] as? [String: Any],
                   let runs = subtitleData["runs"] as? [[String: Any]] {
                    subtitle = runs.compactMap { $0["text"] as? String }.joined()
                }
                
                var thumbUrl = ""
                if let thumbRenderer = twoRowItem["thumbnailRenderer"] as? [String: Any],
                   let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
                   let thumbData = musicThumb["thumbnail"] as? [String: Any],
                   let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbnails.last {
                    thumbUrl = lastThumb["url"] as? String ?? ""
                }
                
                artistItems.append(ArtistItem(
                    id: itemId,
                    title: itemTitle,
                    subtitle: subtitle,
                    thumbnailUrl: thumbUrl,
                    isExplicit: false,
                    videoId: videoId,
                    playlistId: nil,
                    browseId: browseId
                ))
            }
        }
        
        return artistItems
    }
    
    private nonisolated func parseResponsiveListItem(_ listItem: [String: Any]) -> ArtistItem? {
        // Try to get videoId from playlistItemData first
        var videoId: String?
        if let playlistItemData = listItem["playlistItemData"] as? [String: Any] {
            videoId = playlistItemData["videoId"] as? String
        }
        
        // Fallback: try overlay watchEndpoint
        if videoId == nil,
           let overlay = listItem["overlay"] as? [String: Any],
           let overlayRenderer = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = overlayRenderer["content"] as? [String: Any],
           let playButton = content["musicPlayButtonRenderer"] as? [String: Any],
           let playEndpoint = playButton["playNavigationEndpoint"] as? [String: Any],
           let watchEndpoint = playEndpoint["watchEndpoint"] as? [String: Any] {
            videoId = watchEndpoint["videoId"] as? String
        }
        
        guard let id = videoId else { return nil }
        
        // Parse title
        var title = ""
        if let flexColumns = listItem["flexColumns"] as? [[String: Any]],
           let firstCol = flexColumns.first,
           let renderer = firstCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
           let textData = renderer["text"] as? [String: Any],
           let runs = textData["runs"] as? [[String: Any]],
           let firstRun = runs.first {
            title = firstRun["text"] as? String ?? ""
        }
        
        // Parse subtitle (artist name)
        var subtitle = ""
        if let flexColumns = listItem["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
            let secondCol = flexColumns[1]
            if let renderer = secondCol["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
               let textData = renderer["text"] as? [String: Any],
               let runs = textData["runs"] as? [[String: Any]] {
                subtitle = runs.compactMap { $0["text"] as? String }.joined()
            }
        }
        
        // Parse thumbnail
        var thumbUrl = ""
        if let thumbRenderer = listItem["thumbnail"] as? [String: Any],
           let musicThumb = thumbRenderer["musicThumbnailRenderer"] as? [String: Any],
           let thumbData = musicThumb["thumbnail"] as? [String: Any],
           let thumbnails = thumbData["thumbnails"] as? [[String: Any]],
           let lastThumb = thumbnails.last {
            thumbUrl = lastThumb["url"] as? String ?? ""
        }
        
        return ArtistItem(
            id: id,
            title: title,
            subtitle: subtitle,
            thumbnailUrl: thumbUrl,
            isExplicit: false,
            videoId: id,
            playlistId: nil,
            browseId: nil
        )
    }
    
    private nonisolated func parsePlaylistResponseAsItems(_ data: Data) throws -> [ArtistItem] {
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
                if let searchResult = ResponseParser.parseListItem(listItem) {
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
