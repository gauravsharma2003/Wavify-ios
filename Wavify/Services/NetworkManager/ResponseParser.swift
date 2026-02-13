//
//  ResponseParser.swift
//  Wavify
//
//  Shared parsing utilities for YouTube Music API responses
//

import Foundation

/// Shared parsing utilities for YouTube Music API responses
enum ResponseParser {
    
    // MARK: - List Item Parsing
    
    static func parseListItem(_ item: [String: Any]) -> SearchResult? {
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
    
    // MARK: - Thumbnail Extraction
    
    static func extractThumbnailUrl(from item: [String: Any]) -> String {
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
    
    static func extractThumbnailFromVideoDetails(_ details: [String: Any]) -> String {
        if let thumbnail = details["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    // MARK: - Explicit Badge
    
    static func checkIfExplicit(_ item: [String: Any]) -> Bool {
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
    
    // MARK: - Year Extraction
    
    static func extractYear(from item: [String: Any]) -> String {
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
    
    // MARK: - Artist Extraction
    
    static func extractArtistInfo(from item: [String: Any]) -> (name: String, id: String?) {
        if let flexColumns = item["flexColumns"] as? [[String: Any]], flexColumns.count > 1 {
            let secondColumn = flexColumns[1]
            if let renderer = secondColumn["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
               let text = renderer["text"] as? [String: Any],
               let runs = text["runs"] as? [[String: Any]] {
                
                // 1. Robust check: Look for MUSIC_PAGE_TYPE_ARTIST
                for run in runs {
                    if let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                       let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                       let configs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
                       let musicConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                       let pageType = musicConfig["pageType"] as? String,
                       pageType == "MUSIC_PAGE_TYPE_ARTIST",
                       let text = run["text"] as? String,
                       let browseId = browseEndpoint["browseId"] as? String {
                        return (text, browseId)
                    }
                }
                
                // 2. Check explicitly for known artist run structure (often index 2: Type • Artist)
                if runs.count > 2, let text = runs[2]["text"] as? String {
                    if text != "•" && text != " • " {
                        var artistId: String? = nil
                        if let navEndpoint = runs[2]["navigationEndpoint"] as? [String: Any],
                           let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                           let browseId = browseEndpoint["browseId"] as? String {
                            // Only use this ID if it's actually an artist (UC prefix or MUSIC_PAGE_TYPE_ARTIST)
                            if browseId.hasPrefix("UC") {
                                artistId = browseId
                            } else if let configs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
                                      let musicConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                                      let pageType = musicConfig["pageType"] as? String,
                                      pageType == "MUSIC_PAGE_TYPE_ARTIST" {
                                artistId = browseId
                            }
                            // Skip album IDs (MPREb_), playlist IDs (VL), etc.
                        }
                        return (text, artistId)
                    }
                }
                
                // 3. Fallback: Iterate through runs to find any artist channel (UC...)
                for run in runs {
                    if let text = run["text"] as? String,
                       let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                       let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                       let browseId = browseEndpoint["browseId"] as? String,
                       browseId.hasPrefix("UC") {
                        return (text, browseId)
                    }
                }
            }
        }
        return ("", nil)
    }
    
    // MARK: - Video Renderer Parsing
    
    static func extractTitleFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let title = renderer["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    static func extractArtistFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let byline = renderer["longBylineText"] as? [String: Any],
           let runs = byline["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    static func extractArtistIdFromVideoRenderer(_ renderer: [String: Any]) -> String? {
        if let byline = renderer["longBylineText"] as? [String: Any],
           let runs = byline["runs"] as? [[String: Any]] {
            for run in runs {
                if let text = run["text"] as? String,
                   text != "•" && text != " • " && !text.isEmpty,
                   let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                   let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                   let browseId = browseEndpoint["browseId"] as? String {
                    
                    // Check if this is an artist page type
                    if let configs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
                       let musicConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                       let pageType = musicConfig["pageType"] as? String,
                       pageType == "MUSIC_PAGE_TYPE_ARTIST" {
                        return browseId
                    }
                    
                    // Fallback: check if browseId starts with UC (artist channel)
                    if browseId.hasPrefix("UC") {
                        return browseId
                    }
                    
                    // Skip album IDs (MPREb_), playlist IDs (VL), etc.
                }
            }
        }
        return nil
    }
    
    static func extractAlbumInfoFromVideoRenderer(_ renderer: [String: Any]) -> (albumId: String, albumName: String)? {
        if let byline = renderer["longBylineText"] as? [String: Any],
           let runs = byline["runs"] as? [[String: Any]] {
            for run in runs {
                guard let text = run["text"] as? String,
                      text != "•" && text != " • " && !text.isEmpty,
                      let navEndpoint = run["navigationEndpoint"] as? [String: Any],
                      let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
                      let browseId = browseEndpoint["browseId"] as? String else { continue }

                // Check for MUSIC_PAGE_TYPE_ALBUM
                if let configs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
                   let musicConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                   let pageType = musicConfig["pageType"] as? String,
                   pageType == "MUSIC_PAGE_TYPE_ALBUM" {
                    return (browseId, text)
                }

                // Fallback: check if browseId starts with MPREb_ (album prefix)
                if browseId.hasPrefix("MPREb_") {
                    return (browseId, text)
                }
            }
        }
        return nil
    }

    static func extractThumbnailFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let thumbnail = renderer["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            return url
        }
        return ""
    }
    
    static func extractDurationFromVideoRenderer(_ renderer: [String: Any]) -> String {
        if let lengthText = renderer["lengthText"] as? [String: Any],
           let runs = lengthText["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    // MARK: - Two Row Item Parsing
    
    static func parseTwoRowItem(_ item: [String: Any]) -> SearchResult? {
        // Title
        var name = ""
        if let title = item["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstRun = runs.first {
            name = firstRun["text"] as? String ?? ""
        }
        
        // Thumbnail
        var thumbnailUrl = ""
        if let thumbnailRenderer = item["thumbnailRenderer"] as? [String: Any],
           let musicThumbnail = thumbnailRenderer["musicThumbnailRenderer"] as? [String: Any],
           let thumbnailData = musicThumbnail["thumbnail"] as? [String: Any],
           let thumbnails = thumbnailData["thumbnails"] as? [[String: Any]],
           let lastThumbnail = thumbnails.last,
           let url = lastThumbnail["url"] as? String {
            thumbnailUrl = url
        }
        
        // Artist from subtitle
        var artist = ""
        if let subtitle = item["subtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]] {
            artist = runs.compactMap { $0["text"] as? String }.joined()
        }
        
        // Navigation endpoint
        if let navigationEndpoint = item["navigationEndpoint"] as? [String: Any] {
            if let watchEndpoint = navigationEndpoint["watchEndpoint"] as? [String: Any],
               let videoId = watchEndpoint["videoId"] as? String {
                return SearchResult(id: videoId, name: name, thumbnailUrl: thumbnailUrl,
                                    isExplicit: false, year: "", artist: artist, type: .song)
            }
            
            if let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
               let browseId = browseEndpoint["browseId"] as? String {
                let type: SearchResultType
                if browseId.hasPrefix("UC") {
                    type = .artist
                } else if browseId.hasPrefix("MPREb_") {
                    type = .album
                } else if browseId.hasPrefix("VL") {
                    type = .playlist
                } else {
                    type = .playlist
                }
                return SearchResult(id: browseId, name: name, thumbnailUrl: thumbnailUrl,
                                    isExplicit: false, year: "", artist: artist, type: type)
            }
        }
        
        return nil
    }
}
