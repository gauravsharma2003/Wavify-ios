//
//  PlayerAPIService.swift
//  Wavify
//
//  Playback info and queue/related songs API
//

import Foundation

/// Service for playback and queue-related API calls
@MainActor
final class PlayerAPIService {
    static let shared = PlayerAPIService()
    
    private let requestManager = APIRequestManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get playback info for a video (audio URL, metadata)
    func getPlaybackInfo(videoId: String) async throws -> PlaybackInfo {
        let body: [String: Any] = [
            "videoId": videoId,
            "context": YouTubeAPIContext.androidContext
        ]
        
        let request = try requestManager.createRequest(
            endpoint: "player",
            body: body,
            headers: YouTubeAPIContext.androidHeaders
        )
        
        let data = try await requestManager.execute(
            request,
            deduplicationKey: "player_\(videoId)",
            cacheable: true
        )
        
        return try parsePlaybackResponse(data)
    }
    
    /// Get related songs for a video
    func getRelatedSongs(videoId: String) async throws -> [QueueSong] {
        // Step 1: Get playlist ID
        let playlistId = try await getPlaylistId(videoId: videoId)
        
        // Step 2: Get full queue
        return try await getQueueSongs(playlistId: playlistId)
    }
    
    /// Get queue songs from a playlist
    func getQueueSongs(playlistId: String) async throws -> [QueueSong] {
        let body: [String: Any] = [
            "playlistId": playlistId,
            "context": YouTubeAPIContext.webContext
        ]
        
        let request = try requestManager.createRequest(
            endpoint: "next",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let data = try await requestManager.execute(
            request,
            deduplicationKey: "queue_\(playlistId)"
        )
        
        return parseQueueResponse(data)
    }
    
    // MARK: - Private Methods
    
    private func getPlaylistId(videoId: String) async throws -> String {
        let body: [String: Any] = [
            "videoId": videoId,
            "context": YouTubeAPIContext.webContext
        ]
        
        let request = try requestManager.createRequest(
            endpoint: "next",
            body: body,
            headers: YouTubeAPIContext.webHeaders
        )
        
        let data = try await requestManager.execute(request)
        
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
    
    // MARK: - Parsing
    
    private nonisolated func parsePlaybackResponse(_ data: Data) throws -> PlaybackInfo {
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
        let thumbnailUrl = ResponseParser.extractThumbnailFromVideoDetails(videoDetails)
        
        return PlaybackInfo(
            audioUrl: audioUrl,
            videoId: videoId,
            title: title,
            duration: lengthSeconds,
            thumbnailUrl: thumbnailUrl,
            artist: author,
            viewCount: viewCount,
            artistId: artistId,
            albumId: nil
        )
    }
    
    private nonisolated func parseQueueResponse(_ data: Data) -> [QueueSong] {
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
                
                let title = ResponseParser.extractTitleFromVideoRenderer(videoRenderer)
                let artist = ResponseParser.extractArtistFromVideoRenderer(videoRenderer)
                let thumbnailUrl = ResponseParser.extractThumbnailFromVideoRenderer(videoRenderer)
                let duration = ResponseParser.extractDurationFromVideoRenderer(videoRenderer)
                let artistId = ResponseParser.extractArtistIdFromVideoRenderer(videoRenderer)
                
                songs.append(QueueSong(
                    id: videoId,
                    name: title,
                    artist: artist,
                    thumbnailUrl: thumbnailUrl,
                    duration: duration,
                    artistId: artistId
                ))
            }
        }
        
        return songs
    }
}
