//
//  LyricsService.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import Foundation

@MainActor
class LyricsService {
    static let shared = LyricsService()
    
    private let session: URLSession
    
    // Cache to avoid re-fetching lyrics for the same song
    private var lyricsCache: [String: LyricsResult] = [:]
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Fetch lyrics for a song, trying providers in priority order
    func fetchLyrics(title: String, artist: String, duration: Double) async -> LyricsResult {
        let cacheKey = "\(title.lowercased())-\(artist.lowercased())"
        
        // Check cache first
        if let cached = lyricsCache[cacheKey] {
            return cached
        }
        
        // Try LrcLib first (primary provider)
        if let result = await fetchFromLrcLib(title: title, artist: artist, duration: duration) {
            lyricsCache[cacheKey] = result
            return result
        }
        
        // Try KuGou as fallback
        if let result = await fetchFromKuGou(title: title, artist: artist, duration: duration) {
            lyricsCache[cacheKey] = result
            return result
        }
        
        // No lyrics found
        let emptyResult = LyricsResult.empty
        lyricsCache[cacheKey] = emptyResult
        return emptyResult
    }
    
    /// Clear the lyrics cache (useful when memory is low)
    func clearCache() {
        lyricsCache.removeAll()
    }
    
    // MARK: - LrcLib Provider
    
    private func fetchFromLrcLib(title: String, artist: String, duration: Double) async -> LyricsResult? {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Wavify/1.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let results = try decoder.decode([LrcLibSearchResult].self, from: data)
            
            // Find best match - prefer one with synced lyrics and similar duration
            let bestMatch = results
                .filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
                .min { result1, result2 in
                    // Prefer results with synced lyrics
                    let hasSync1 = result1.syncedLyrics != nil
                    let hasSync2 = result2.syncedLyrics != nil
                    if hasSync1 != hasSync2 { return hasSync1 }
                    
                    // Then prefer closer duration match
                    let dur1 = result1.duration ?? 0
                    let dur2 = result2.duration ?? 0
                    return abs(dur1 - duration) < abs(dur2 - duration)
                }
            
            guard let match = bestMatch else {
                return nil
            }
            
            var syncedLines: [SyncedLyricLine]? = nil
            if let syncedLyrics = match.syncedLyrics {
                syncedLines = parseLRCFormat(syncedLyrics)
            }
            
            // Return result if we have any lyrics
            if syncedLines != nil || match.plainLyrics != nil {
                return LyricsResult(
                    syncedLyrics: syncedLines,
                    plainLyrics: match.plainLyrics,
                    source: .lrcLib
                )
            }
            
            return nil
            
        } catch {
            print("LrcLib fetch error: \(error)")
            return nil
        }
    }
    
    // MARK: - KuGou Provider
    
    private func fetchFromKuGou(title: String, artist: String, duration: Double) async -> LyricsResult? {
        let keyword = "\(title) - \(artist)"
        guard let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // Duration in milliseconds
        let durationMs = Int(duration * 1000)
        
        // Step 1: Search for lyrics
        let searchUrl = "https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&duration=\(durationMs)&keyword=\(encodedKeyword)"
        
        guard let url = URL(string: searchUrl) else {
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            // Parse search response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let id = firstCandidate["id"] as? String,
                  let accesskey = firstCandidate["accesskey"] as? String else {
                return nil
            }
            
            // Step 2: Download lyrics
            let downloadUrl = "https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id=\(id)&accesskey=\(accesskey)"
            
            guard let lyricsUrl = URL(string: downloadUrl) else {
                return nil
            }
            
            var lyricsRequest = URLRequest(url: lyricsUrl)
            lyricsRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            
            let (lyricsData, lyricsResponse) = try await session.data(for: lyricsRequest)
            
            guard let lyricsHttpResponse = lyricsResponse as? HTTPURLResponse,
                  lyricsHttpResponse.statusCode == 200 else {
                return nil
            }
            
            // Parse lyrics response
            guard let lyricsJson = try JSONSerialization.jsonObject(with: lyricsData) as? [String: Any],
                  let contentBase64 = lyricsJson["content"] as? String,
                  let contentData = Data(base64Encoded: contentBase64),
                  let lrcContent = String(data: contentData, encoding: .utf8) else {
                return nil
            }
            
            let syncedLines = parseLRCFormat(lrcContent)
            
            if !syncedLines.isEmpty {
                return LyricsResult(
                    syncedLyrics: syncedLines,
                    plainLyrics: syncedLines.map { $0.text }.joined(separator: "\n"),
                    source: .kuGou
                )
            }
            
            return nil
            
        } catch {
            print("KuGou fetch error: \(error)")
            return nil
        }
    }
    
    // MARK: - LRC Parser
    
    /// Parse LRC format lyrics into timestamped lines
    /// LRC format: [mm:ss.xx]Lyrics line text
    func parseLRCFormat(_ lrcString: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        
        // Regex pattern for LRC timestamps: [mm:ss.xx] or [mm:ss.xxx]
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.+)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let lrcLines = lrcString.components(separatedBy: .newlines)
        
        for line in lrcLines {
            let range = NSRange(line.startIndex..., in: line)
            
            if let match = regex.firstMatch(in: line, options: [], range: range) {
                // Extract time components
                guard let minutesRange = Range(match.range(at: 1), in: line),
                      let secondsRange = Range(match.range(at: 2), in: line),
                      let millisecondsRange = Range(match.range(at: 3), in: line),
                      let textRange = Range(match.range(at: 4), in: line) else {
                    continue
                }
                
                let minutes = Double(line[minutesRange]) ?? 0
                let seconds = Double(line[secondsRange]) ?? 0
                var milliseconds = Double(line[millisecondsRange]) ?? 0
                
                // Normalize milliseconds (could be 2 or 3 digits)
                if line[millisecondsRange].count == 2 {
                    milliseconds *= 10 // Convert centiseconds to milliseconds
                }
                
                let timeInSeconds = minutes * 60 + seconds + milliseconds / 1000
                let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                
                // Skip empty lines
                if !text.isEmpty {
                    lines.append(SyncedLyricLine(time: timeInSeconds, text: text))
                }
            }
        }
        
        // Sort by time to ensure correct order
        return lines.sorted { $0.time < $1.time }
    }
}
