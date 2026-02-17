//
//  AlbumAPIService.swift
//  Wavify
//
//  Album details and songs API
//

import Foundation

/// Service for album-related API calls
@MainActor
final class AlbumAPIService {
    static let shared = AlbumAPIService()
    
    private let requestManager = APIRequestManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get album details including songs and related albums
    func getAlbumDetails(albumId: String) async throws -> AlbumDetail {
        let body: [String: Any] = [
            "browseId": albumId,
            "context": YouTubeAPIContext.webContext
        ]
        
        let request = try requestManager.createRequest(
            endpoint: "browse",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let data = try await requestManager.execute(
            request,
            deduplicationKey: "album_\(albumId)",
            cacheable: true
        )
        
        return try parseAlbumResponse(data, albumId: albumId)
    }
    
    // MARK: - Parsing
    
    private nonisolated func parseAlbumResponse(_ data: Data, albumId: String) throws -> AlbumDetail {
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
        let year = extractAlbumYear(header)
        
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
            year: year,
            songs: songs,
            relatedAlbums: relatedAlbums
        )
    }
    
    // MARK: - Helper Methods
    
    private nonisolated func extractAlbumThumbnail(_ header: [String: Any]) -> String {
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
    
    private nonisolated func extractAlbumName(_ header: [String: Any]) -> String {
        if let title = header["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    private nonisolated func extractAlbumArtist(_ header: [String: Any]) -> String {
        if let strapline = header["straplineTextOne"] as? [String: Any],
           let runs = strapline["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String {
            return text
        }
        return ""
    }
    
    private nonisolated func extractArtistThumbnail(_ header: [String: Any]) -> String {
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
    
    private nonisolated func extractAlbumYear(_ header: [String: Any]) -> String {
        if let subtitle = header["subtitle"] as? [String: Any],
           let runs = subtitle["runs"] as? [[String: Any]] {
            // Subtitle runs are typically ["Album", " · ", "2024"] or ["Single", " · ", "2024"]
            for run in runs {
                if let text = run["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.count == 4, Int(trimmed) != nil {
                        return trimmed
                    }
                }
            }
        }
        return ""
    }

    private nonisolated func extractAlbumInfo(_ header: [String: Any]) -> (String, String) {
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
    
    private nonisolated func extractSongTitle(_ item: [String: Any]) -> String {
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
    
    private nonisolated func extractViewCount(_ item: [String: Any]) -> String {
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
    
    private nonisolated func extractSongDuration(_ item: [String: Any]) -> String {
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
    
    private nonisolated func parseRelatedAlbum(_ item: [String: Any]) -> RelatedAlbum? {
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
