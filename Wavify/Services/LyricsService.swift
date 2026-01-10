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
            Logger.error("LrcLib fetch error", category: .lyrics, error: error)
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
            Logger.error("KuGou fetch error", category: .lyrics, error: error)
            return nil
        }
    }
    
    // MARK: - LRC Parser
    
    /// Parse LRC format lyrics into timestamped lines
    /// LRC format: [mm:ss.xx]Lyrics line text
    /// Parse LRC format lyrics into timestamped lines
    /// Supports standard LRC [mm:ss.xx], extended [mm:ss.xx][mm:ss.xx], and other common formats
    func parseLRCFormat(_ lrcString: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        let lrcLines = lrcString.components(separatedBy: .newlines)
        
        // Regex for grabbing the first timestamp in a line
        // Supports: [mm:ss.xx], [hh:mm:ss.xx], mm:ss.xx, 00:mm:ss.xx
        // Groups: 1=brackets?, 2=hh?, 3=mm, 4=ss, 5=xx
        let timePattern = #"(?:\[)?(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:\.|:)(\d{2,3})(?:\])?"#
        
        guard let regex = try? NSRegularExpression(pattern: timePattern, options: []) else {
            return []
        }
        
        for line in lrcLines {
            let nsString = line as NSString
            let range = NSRange(location: 0, length: nsString.length)
            
            // Find all timestamps in the line (standard LRC can have multiple timestamps for the same text)
            let matches = regex.matches(in: line, options: [], range: range)
            
            if matches.isEmpty { continue }
            
            // The text is everything match...
            // Wait, for lines like "00:00:09.310 ~ 00:00:11.220 Text", the second timestamp is end time.
            // We should take the FIRST timestamp as start time, and assume the rest is potentially text,
            // but we need to strip out the " ~ 00:00:11.220 " part if it exists.
            
            // Strategy:
            // 1. Parse the first match as the start time.
            // 2. Identify where the "Lyrics Text" starts.
            //    It usually starts after the last timestamp match plus some separators.
            
            guard let firstMatch = matches.first else { continue }
            
            // Parse time from first match
            let timeInSeconds = parseTime(from: firstMatch, in: line)
            
            // Determine text content
            // We'll strip ALL timestamp-like patterns and common separators from the line to get the text
            var text = line
            
            // Remove all timestamps matches
            for match in matches.reversed() {
                // Ensure we are scrubbing valid matches
                text = (text as NSString).replacingCharacters(in: match.range, with: "")
            }
            
            // Remove common separators that might remain (like "~", "-", leading spaces)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Allow removal of leading "~" or "-" which might separate start/end times
            if text.hasPrefix("~") || text.hasPrefix("-") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            
            // Skip empty lines
            if !text.isEmpty {
                 lines.append(SyncedLyricLine(time: timeInSeconds, text: text))
            }
        }
        
        return lines.sorted { $0.time < $1.time }
    }
    
    private func parseTime(from match: NSTextCheckingResult, in line: String) -> Double {
        let nsString = line as NSString
        
        // Group indices based on the pattern:
        // (?:\[)?(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:\.|:)(\d{2,3})(?:\])?
        // 1: Hours (Optional)
        // 2: Minutes
        // 3: Seconds
        // 4: Fractions
        
        var hours: Double = 0
        if let range = Range(match.range(at: 1), in: line) {
            hours = Double(line[range]) ?? 0
        }
        
        let minutes = Double(nsString.substring(with: match.range(at: 2))) ?? 0
        let seconds = Double(nsString.substring(with: match.range(at: 3))) ?? 0
        
        let fracString = nsString.substring(with: match.range(at: 4))
        var milliseconds = Double(fracString) ?? 0
        
        // Normalize milliseconds: if 2 digits, treat as centiseconds (x10)
        if fracString.count == 2 {
            milliseconds *= 10
        }
        
        return (hours * 3600) + (minutes * 60) + seconds + (milliseconds / 1000)
    }
}
