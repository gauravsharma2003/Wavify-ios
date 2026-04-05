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
    private let ttmlParser = TTMLParser()

    // Cache to avoid re-fetching lyrics for the same song
    private var lyricsCache: [String: LyricsResult] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetch lyrics for a song, trying providers in priority order:
    /// BetterLyrics → Paxsenix → LrcLib → KuGou → LyricsPlus
    func fetchLyrics(title: String, artist: String, duration: Double) async -> LyricsResult {
        let cacheKey = "\(title.lowercased())-\(artist.lowercased())"

        if let cached = lyricsCache[cacheKey] {
            return cached
        }

        let providers: [(String, () async -> LyricsResult?)] = [
            ("BetterLyrics", { await self.fetchFromBetterLyrics(title: title, artist: artist, duration: duration) }),
            ("Paxsenix",     { await self.fetchFromPaxsenix(title: title, artist: artist, duration: duration) }),
            ("LrcLib",       { await self.fetchFromLrcLib(title: title, artist: artist, duration: duration) }),
            ("KuGou",        { await self.fetchFromKuGou(title: title, artist: artist, duration: duration) }),
            ("LyricsPlus",   { await self.fetchFromLyricsPlus(title: title, artist: artist, duration: duration) }),
        ]

        for (name, fetch) in providers {
            if let result = await fetch() {
                Logger.debug("Lyrics found via \(name)", category: .lyrics)
                let cleaned = sanitizeLyricsResult(result)
                lyricsCache[cacheKey] = cleaned
                return cleaned
            }
        }

        let emptyResult = LyricsResult.empty
        lyricsCache[cacheKey] = emptyResult
        return emptyResult
    }

    /// Clear the lyrics cache
    func clearCache() {
        lyricsCache.removeAll()
    }

    // MARK: - BetterLyrics Provider

    private func fetchFromBetterLyrics(title: String, artist: String, duration: Double) async -> LyricsResult? {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        var urlString = "https://lyrics-api.boidu.dev/getLyrics?s=\(encodedTitle)&a=\(encodedArtist)"
        if duration > 0 {
            // Send duration in milliseconds (matching MetroList/BetterLyrics extension format)
            urlString += "&d=\(Int(duration * 1000))"
        }

        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let result = try JSONDecoder().decode(BetterLyricsResponse.self, from: data)

            guard let ttml = result.ttml, !ttml.isEmpty else { return nil }

            guard let lines = ttmlParser.parse(ttml), !lines.isEmpty else { return nil }

            let plainText = lines.map(\.text).joined(separator: "\n")
            return LyricsResult(
                syncedLyrics: lines,
                plainLyrics: plainText,
                source: .betterLyrics
            )
        } catch {
            Logger.error("BetterLyrics fetch error", category: .lyrics, error: error)
            return nil
        }
    }

    // MARK: - Paxsenix Provider

    private func fetchFromPaxsenix(title: String, artist: String, duration: Double) async -> LyricsResult? {
        let query = "\(title) \(artist)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        // Step 1: Search
        let searchUrlString = "https://lyrics.paxsenix.org/apple-music/search?q=\(encodedQuery)"
        guard let searchUrl = URL(string: searchUrlString) else { return nil }

        do {
            var searchRequest = URLRequest(url: searchUrl)
            searchRequest.setValue("Wavify/1.0", forHTTPHeaderField: "User-Agent")

            let (searchData, searchResponse) = try await session.data(for: searchRequest)

            guard let httpResponse = searchResponse as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let decoder = JSONDecoder()
            let searchResults = try decoder.decode([PaxsenixSearchResult].self, from: searchData)

            guard let bestMatch = findBestPaxsenixMatch(
                searchResults, title: title, artist: artist, durationMs: Int(duration * 1000)
            ) else {
                return nil
            }

            // Step 2: Fetch lyrics by Apple Music ID
            let lyricsUrlString = "https://lyrics.paxsenix.org/apple-music/lyrics?id=\(bestMatch.id)"
            guard let lyricsUrl = URL(string: lyricsUrlString) else { return nil }

            var lyricsRequest = URLRequest(url: lyricsUrl)
            lyricsRequest.setValue("Wavify/1.0", forHTTPHeaderField: "User-Agent")

            let (lyricsData, lyricsResponse) = try await session.data(for: lyricsRequest)

            guard let lyricsHttpResponse = lyricsResponse as? HTTPURLResponse,
                  lyricsHttpResponse.statusCode == 200 else {
                return nil
            }

            let lyricsResult = try decoder.decode(PaxsenixLyricsResponse.self, from: lyricsData)

            // Priority: ttmlContent → content[] syllable data → plain
            if let ttml = lyricsResult.ttmlContent, !ttml.isEmpty,
               let lines = ttmlParser.parse(ttml), !lines.isEmpty {
                return LyricsResult(
                    syncedLyrics: lines,
                    plainLyrics: lines.map(\.text).joined(separator: "\n"),
                    source: .paxsenix
                )
            }

            if let syllables = lyricsResult.content, !syllables.isEmpty {
                let lines = parsePaxsenixSyllables(syllables)
                if !lines.isEmpty {
                    return LyricsResult(
                        syncedLyrics: lines,
                        plainLyrics: lines.map(\.text).joined(separator: "\n"),
                        source: .paxsenix
                    )
                }
            }

            if let plain = lyricsResult.plain, !plain.isEmpty {
                return LyricsResult(
                    syncedLyrics: nil,
                    plainLyrics: plain,
                    source: .paxsenix
                )
            }

            return nil
        } catch {
            Logger.error("Paxsenix fetch error", category: .lyrics, error: error)
            return nil
        }
    }

    private func findBestPaxsenixMatch(
        _ results: [PaxsenixSearchResult],
        title: String,
        artist: String,
        durationMs: Int
    ) -> PaxsenixSearchResult? {
        guard !results.isEmpty else { return nil }

        let cleanTitle = cleanSearchTitle(title).lowercased()
        let cleanArtist = cleanSearchArtist(artist).lowercased()

        // Score each result (matching MetroList's scoring)
        let scored = results.compactMap { result -> (PaxsenixSearchResult, Int)? in
            let name = cleanSearchTitle(result.songName ?? result.trackName ?? "").lowercased()
            let art = cleanSearchArtist(result.artistName ?? "").lowercased()
            var score = 0

            // Duration score (0-100)
            let durDiffMs = abs((result.duration ?? 0) - durationMs)
            if durDiffMs <= 2000 { score += 100 }
            else if durDiffMs <= 5000 { score += 50 }
            else if durDiffMs <= 10000 { score += 10 }
            else { score -= 50 }

            // Title score (0-80)
            if name == cleanTitle { score += 80 }
            else if name.contains(cleanTitle) || cleanTitle.contains(name) { score += 40 }

            // Version penalties
            if name.contains("remix") && !cleanTitle.contains("remix") { score -= 40 }
            if name.contains("mixed") && !cleanTitle.contains("mixed") { score -= 60 }

            // Artist score (0-50)
            if art.contains(cleanArtist) || cleanArtist.contains(art) { score += 50 }

            return score > 0 ? (result, score) : nil
        }

        return scored.max(by: { $0.1 < $1.1 })?.0 ?? results.first
    }

    /// Strip parenthetical qualifiers, brackets, trailing metadata from title
    private func cleanSearchTitle(_ title: String) -> String {
        var cleaned = title
        // Remove (feat. ...), (Remix), [Deluxe], etc.
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Extract primary artist name
    private func cleanSearchArtist(_ artist: String) -> String {
        // Split on common delimiters, take first
        let delimiters = [" & ", " and ", ", ", " x ", " feat. ", " ft. ", " featuring ", " with "]
        var primary = artist
        for delim in delimiters {
            if let range = primary.range(of: delim, options: .caseInsensitive) {
                primary = String(primary[..<range.lowerBound])
            }
        }
        return primary.trimmingCharacters(in: .whitespaces)
    }

    private func parsePaxsenixSyllables(_ syllables: [PaxsenixSyllable]) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []

        for syllable in syllables {
            guard let timestamp = syllable.timestamp else { continue }
            let startTime = timestamp / 1000.0
            let endTime = syllable.endtime.map { $0 / 1000.0 }

            var words: [SyncedWord] = []
            var lineText = ""

            if let wordList = syllable.text {
                for word in wordList {
                    guard let text = word.text, !text.isEmpty,
                          let wStart = word.timestamp,
                          let wEnd = word.endtime else { continue }

                    let cleaned = cleanWordText(text)
                    guard !cleaned.isEmpty else { continue }

                    words.append(SyncedWord(
                        startTime: wStart / 1000.0,
                        endTime: wEnd / 1000.0,
                        text: cleaned
                    ))
                }
                lineText = words.map(\.text).joined(separator: " ")
            }

            // Strip section annotations (v1:, c:, b:, etc.) from assembled line text
            lineText = cleanLineText(lineText)

            if lineText.isEmpty { continue }

            // Rebuild words if line text was cleaned of a prefix
            // (the first word might have contained the annotation)
            if let first = words.first {
                let cleanedFirst = cleanLineText(first.text)
                if cleanedFirst != first.text {
                    if cleanedFirst.isEmpty {
                        words.removeFirst()
                    } else {
                        words[0] = SyncedWord(
                            startTime: first.startTime,
                            endTime: first.endTime,
                            text: cleanedFirst
                        )
                    }
                    lineText = words.map(\.text).joined(separator: " ")
                }
            }

            if lineText.isEmpty { continue }

            lines.append(SyncedLyricLine(
                time: startTime,
                text: lineText,
                endTime: endTime,
                words: words.isEmpty ? nil : words
            ))
        }

        return lines.sorted { $0.time < $1.time }
    }

    // MARK: - Lyrics Text Cleaning

    /// Strip timing markers (<>, </>, etc.) and trim whitespace from individual word text
    private func cleanWordText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespaces)

        // Remove standalone timing/onset markers: <>, </>, <br>, <br/>, etc.
        // These appear in Apple Music syllable data as timing markers
        if cleaned == "<>" || cleaned == "</>" || cleaned == "<br>" || cleaned == "<br/>" {
            return ""
        }

        // Remove <> markers embedded in word text (e.g., "<>word" → "word")
        cleaned = cleaned.replacingOccurrences(of: "<>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</>", with: "")

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Post-process any LyricsResult to ensure no artifacts remain in text,
    /// regardless of which provider returned the data.
    private func sanitizeLyricsResult(_ result: LyricsResult) -> LyricsResult {
        guard let syncedLines = result.syncedLyrics else { return result }

        let cleanedLines = syncedLines.compactMap { line -> SyncedLyricLine? in
            let cleanedText = cleanLineText(line.text)
            guard !cleanedText.isEmpty else { return nil }

            // Clean word-level text if present
            let cleanedWords: [SyncedWord]? = line.words?.compactMap { word in
                let cleaned = cleanWordText(word.text)
                guard !cleaned.isEmpty else { return nil }
                return SyncedWord(startTime: word.startTime, endTime: word.endTime, text: cleaned)
            }

            // Rebuild line text from cleaned words if we have them
            let finalText: String
            if let words = cleanedWords, !words.isEmpty {
                finalText = words.map(\.text).joined(separator: " ")
            } else {
                finalText = cleanedText
            }

            guard !finalText.isEmpty else { return nil }

            return SyncedLyricLine(
                time: line.time,
                text: finalText,
                endTime: line.endTime,
                words: cleanedWords?.isEmpty == true ? nil : cleanedWords
            )
        }

        let plainText = result.plainLyrics.map { cleanLineText($0) }

        return LyricsResult(
            syncedLyrics: cleanedLines.isEmpty ? nil : cleanedLines,
            plainLyrics: plainText,
            source: result.source
        )
    }

    /// Strip section annotations (v1:, c1:, b:, etc.) and timing artifacts from line text
    private func cleanLineText(_ text: String) -> String {
        var cleaned = text

        // Strip angle-bracket timestamps: <00:13.094>, <01:23.456>, etc.
        cleaned = cleaned.replacingOccurrences(
            of: #"<\d{1,2}:\d{1,2}[.:]\d{2,3}>"#,
            with: "",
            options: .regularExpression
        )

        // Strip verse/chorus/bridge annotations: v1:, v2:, c:, c1:, b:, b1:, p:, i:, o:, etc.
        cleaned = cleaned.replacingOccurrences(
            of: #"^(?:v\d*|c\d*|b\d*|p\d*|i\d*|o\d*|outro|intro|verse|chorus|bridge|hook|pre-chorus|post-chorus):\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip any remaining empty markers
        cleaned = cleaned.replacingOccurrences(of: "<>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "</>", with: "")

        return cleaned.trimmingCharacters(in: .whitespaces)
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

            let results = try JSONDecoder().decode([LrcLibSearchResult].self, from: data)

            let bestMatch = results
                .filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
                .min { result1, result2 in
                    let hasSync1 = result1.syncedLyrics != nil
                    let hasSync2 = result2.syncedLyrics != nil
                    if hasSync1 != hasSync2 { return hasSync1 }
                    let dur1 = result1.duration ?? 0
                    let dur2 = result2.duration ?? 0
                    return abs(dur1 - duration) < abs(dur2 - duration)
                }

            guard let match = bestMatch else { return nil }

            var syncedLines: [SyncedLyricLine]? = nil
            if let syncedLyrics = match.syncedLyrics {
                syncedLines = parseLRCFormat(syncedLyrics)
            }

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

        let durationMs = Int(duration * 1000)
        let searchUrl = "https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&duration=\(durationMs)&keyword=\(encodedKeyword)"

        guard let url = URL(string: searchUrl) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let id = firstCandidate["id"] as? String,
                  let accesskey = firstCandidate["accesskey"] as? String else {
                return nil
            }

            let downloadUrl = "https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id=\(id)&accesskey=\(accesskey)"

            guard let lyricsUrl = URL(string: downloadUrl) else { return nil }

            var lyricsRequest = URLRequest(url: lyricsUrl)
            lyricsRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            let (lyricsData, lyricsResponse) = try await session.data(for: lyricsRequest)

            guard let lyricsHttpResponse = lyricsResponse as? HTTPURLResponse,
                  lyricsHttpResponse.statusCode == 200 else {
                return nil
            }

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
                    plainLyrics: syncedLines.map(\.text).joined(separator: "\n"),
                    source: .kuGou
                )
            }

            return nil
        } catch {
            Logger.error("KuGou fetch error", category: .lyrics, error: error)
            return nil
        }
    }

    // MARK: - LyricsPlus Provider

    private static let lyricsPlusBaseURLs = [
        "https://lyricsplus.binimum.org",
        "https://lyricsplus.atomix.one",
        "https://lyricsplus-seven.vercel.app",
    ]

    private func fetchFromLyricsPlus(title: String, artist: String, duration: Double) async -> LyricsResult? {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let durationSec = duration > 0 ? Int(duration) : -1
        let path = "/v2/lyrics/get?title=\(encodedTitle)&artist=\(encodedArtist)&duration=\(durationSec)&source=apple,lyricsplus,musixmatch,spotify,musixmatch-word"

        for baseURL in Self.lyricsPlusBaseURLs {
            let urlString = "\(baseURL)\(path)"
            guard let url = URL(string: urlString) else { continue }

            do {
                var request = URLRequest(url: url)
                request.setValue("Wavify/1.0", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                let decoder = JSONDecoder()
                let result = try decoder.decode(LyricsPlusResponse.self, from: data)

                guard let lyrics = result.lyrics, !lyrics.isEmpty else { continue }

                // Convert ms → seconds, line-level only
                let lines = lyrics.compactMap { line -> SyncedLyricLine? in
                    guard let time = line.time, let text = line.text, !text.isEmpty else { return nil }
                    let endTime = line.duration.map { (time + $0) / 1000.0 }
                    return SyncedLyricLine(
                        time: time / 1000.0,
                        text: text,
                        endTime: endTime
                    )
                }

                guard !lines.isEmpty else { continue }

                let sorted = lines.sorted { $0.time < $1.time }
                return LyricsResult(
                    syncedLyrics: sorted,
                    plainLyrics: sorted.map(\.text).joined(separator: "\n"),
                    source: .lyricsPlus
                )
            } catch {
                Logger.error("LyricsPlus fetch error (\(baseURL))", category: .lyrics, error: error)
                continue
            }
        }

        return nil
    }

    // MARK: - LRC Parser

    /// Parse LRC format lyrics into timestamped lines
    /// Supports standard LRC [mm:ss.xx], extended [mm:ss.xx][mm:ss.xx], and other common formats
    /// Also handles non-standard inline word timestamps like <00:13.094> from some LrcLib entries
    func parseLRCFormat(_ lrcString: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        let lrcLines = lrcString.components(separatedBy: .newlines)

        // Standard LRC timestamps: [mm:ss.xx] or bare mm:ss.xx
        let timePattern = #"(?:\[)?(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:\.|:)(\d{2,3})(?:\])?"#

        // Angle-bracket word timestamps: <00:13.094> — strip the entire <...> including brackets
        let angleBracketTimePattern = #"<\d{1,2}:\d{1,2}[.:]\d{2,3}>"#

        guard let regex = try? NSRegularExpression(pattern: timePattern, options: []),
              let angleBracketRegex = try? NSRegularExpression(pattern: angleBracketTimePattern, options: []) else {
            return []
        }

        for line in lrcLines {
            // Step 1: Strip angle-bracket timestamps FIRST (e.g., <00:13.094>) — removes brackets too
            let cleanedLine = angleBracketRegex.stringByReplacingMatches(
                in: line,
                options: [],
                range: NSRange(location: 0, length: (line as NSString).length),
                withTemplate: ""
            )

            let nsString = cleanedLine as NSString
            let range = NSRange(location: 0, length: nsString.length)

            let matches = regex.matches(in: cleanedLine, options: [], range: range)

            if matches.isEmpty { continue }

            guard let firstMatch = matches.first else { continue }

            let timeInSeconds = parseTime(from: firstMatch, in: cleanedLine)

            var text = cleanedLine

            // Step 2: Strip standard LRC timestamps
            for match in matches.reversed() {
                text = (text as NSString).replacingCharacters(in: match.range, with: "")
            }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if text.hasPrefix("~") || text.hasPrefix("-") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            // Step 3: Clean section annotations and any remaining markers
            text = cleanLineText(text)

            if !text.isEmpty {
                lines.append(SyncedLyricLine(time: timeInSeconds, text: text))
            }
        }

        // Filter credit lines
        let creditPatterns = ["synced by", "lyrics by", "music by", "arranged by", "written by", "composed by", "produced by"]
        let filtered = lines.filter { line in
            let lower = line.text.lowercased()
            return !creditPatterns.contains { lower.contains($0) }
        }

        return filtered.sorted { $0.time < $1.time }
    }

    private func parseTime(from match: NSTextCheckingResult, in line: String) -> Double {
        let nsString = line as NSString

        var hours: Double = 0
        if let range = Range(match.range(at: 1), in: line) {
            hours = Double(line[range]) ?? 0
        }

        let minutes = Double(nsString.substring(with: match.range(at: 2))) ?? 0
        let seconds = Double(nsString.substring(with: match.range(at: 3))) ?? 0

        let fracString = nsString.substring(with: match.range(at: 4))
        var milliseconds = Double(fracString) ?? 0

        if fracString.count == 2 {
            milliseconds *= 10
        }

        return (hours * 3600) + (minutes * 60) + seconds + (milliseconds / 1000)
    }
}
