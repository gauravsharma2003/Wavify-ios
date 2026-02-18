//
//  YouTubeStreamExtractor.swift
//  Wavify
//
//  Native YouTube audio stream extraction with signature deobfuscation
//  Replaces YouTubeKit dependency and WKWebView fallback
//

import Foundation
import JavaScriptCore

// MARK: - Errors

enum StreamExtractorError: Error, LocalizedError {
    case noURLAvailable
    case noCompatibleFormat
    case invalidCipher
    case deobfuscationFailed(String)
    case playerLoadFailed(String)
    case networkError(String)
    case playabilityError(String)
    case urlValidationFailed(Int)
    case allStrategiesFailed([String])

    var errorDescription: String? {
        switch self {
        case .noURLAvailable: return "No audio URL available for this video"
        case .noCompatibleFormat: return "No compatible audio format found"
        case .invalidCipher: return "Invalid signature cipher"
        case .deobfuscationFailed(let detail): return "Deobfuscation failed: \(detail)"
        case .playerLoadFailed(let detail): return "Player load failed: \(detail)"
        case .networkError(let detail): return "Network error: \(detail)"
        case .playabilityError(let detail): return "Playability error: \(detail)"
        case .urlValidationFailed(let status): return "URL validation failed with HTTP \(status)"
        case .allStrategiesFailed(let reasons): return "All extraction strategies failed: \(reasons.joined(separator: "; "))"
        }
    }
}

// MARK: - Stream Extractor

/// Native YouTube audio stream extraction engine
/// Handles signature deobfuscation and n-parameter throttling via JavaScriptCore
actor YouTubeStreamExtractor {

    static let shared = YouTubeStreamExtractor()

    // MARK: - User Agents

    /// Chrome desktop UA - used for WEB client extraction and embed page fetching
    static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    /// Playback headers - empty because TV embedded URLs work with AVPlayer's default UA
    static var playbackHeaders: [String: String] {
        [:]
    }

    // MARK: - Types

    struct ResolvedStream {
        let url: URL
        let itag: Int
        let mimeType: String
        let bitrate: Int
        let playbackHeaders: [String: String]
    }

    private struct CachedStream {
        let stream: ResolvedStream
        let expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt }
    }

    private struct AudioFormat {
        let itag: Int
        let url: String?
        let signatureCipher: String?
        let mimeType: String
        let bitrate: Int
    }

    struct ClientStrategy {
        let name: String
        let context: [String: Any]
        let headers: [String: String]
        let requiresCipher: Bool
        let requiresPoToken: Bool
    }

    // MARK: - Strategy Chain
    //
    // Only clients that return direct URLs (no cipher) and don't require PoToken.
    // Web-based clients (WEB, MWEB, WEB_EMBED) require PoToken for media access
    // which needs WebView + BotGuard — not feasible natively. Removed.

    private static let strategies: [ClientStrategy] = [
        // 1. IOS — most reliable, direct URLs, no PoToken needed
        ClientStrategy(
            name: "IOS",
            context: YouTubeAPIContext.iosContext,
            headers: YouTubeAPIContext.iosHeaders,
            requiresCipher: false,
            requiresPoToken: false
        ),
        // 2. ANDROID — direct URLs, no PoToken needed
        ClientStrategy(
            name: "ANDROID",
            context: YouTubeAPIContext.androidContext,
            headers: YouTubeAPIContext.androidHeaders,
            requiresCipher: false,
            requiresPoToken: false
        ),
        // 3. ANDROID_VR — can trigger bot detection on some videos
        ClientStrategy(
            name: "ANDROID_VR",
            context: YouTubeAPIContext.tvContext,
            headers: YouTubeAPIContext.tvHeaders,
            requiresCipher: false,
            requiresPoToken: false
        )
    ]

    // MARK: - State

    private var urlCache: [String: CachedStream] = [:]
    private let jsPlayer = YouTubeJSPlayer()

    private init() {}

    // MARK: - Public API

    /// Resolve a playable audio URL for a YouTube video
    /// Tries client strategies in order: IOS → ANDROID → ANDROID_VR
    func resolveAudioURL(videoId: String) async throws -> ResolvedStream {
        // Check cache first
        if let cached = urlCache[videoId], !cached.isExpired {
            Logger.log("[StreamExtractor] Cache hit for \(videoId), expires in \(Int(cached.expiresAt.timeIntervalSinceNow))s", category: .playback)
            return cached.stream
        }

        let overallStart = CFAbsoluteTimeGetCurrent()
        let strategies = Self.strategies
        var failureReasons: [String] = []

        // Try each client strategy
        for (index, strategy) in strategies.enumerated() {
            let strategyNum = index + 1
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let cpn = CPNGenerator.generate()

                var poToken: String?
                if strategy.requiresPoToken {
                    poToken = await PoTokenProvider.shared.getToken(videoId: videoId)
                }

                let stream = try await resolveViaGenericClient(
                    strategy: strategy,
                    videoId: videoId,
                    cpn: cpn,
                    poToken: poToken
                )
                let validated = try await validateStreamURL(stream)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                Logger.log("[StreamExtractor] Strategy \(strategyNum)/\(strategies.count): \(strategy.name) succeeded in \(String(format: "%.2f", elapsed))s, itag \(validated.itag)", category: .playback)
                return validated
            } catch {
                let elapsed = CFAbsoluteTimeGetCurrent() - overallStart
                let reason = describeError(error)
                failureReasons.append("\(strategy.name): \(reason)")
                Logger.warning("[StreamExtractor] Strategy \(strategyNum)/\(strategies.count): \(strategy.name) failed (\(String(format: "%.2f", elapsed))s): \(reason)", category: .playback)
            }
        }

        // Trigger visitor data refresh on total failure
        Task { await VisitorDataScraper.shared.scrape() }

        let totalElapsed = CFAbsoluteTimeGetCurrent() - overallStart
        Logger.error("[StreamExtractor] All \(strategies.count) strategies failed for \(videoId) in \(String(format: "%.2f", totalElapsed))s", category: .playback)
        throw StreamExtractorError.allStrategiesFailed(failureReasons)
    }

    /// Invalidate cached URL for a video (call on playback failure)
    func invalidateCache(videoId: String) {
        urlCache.removeValue(forKey: videoId)
    }

    /// Clear all cached URLs
    func clearCache() {
        urlCache.removeAll()
    }

    /// Invalidate the JS player cache (call when deobfuscation starts failing)
    func invalidatePlayer() async {
        await jsPlayer.invalidate()
    }

    // MARK: - Generic Client Resolution

    private func resolveViaGenericClient(
        strategy: ClientStrategy,
        videoId: String,
        cpn: String,
        poToken: String?
    ) async throws -> ResolvedStream {
        var body: [String: Any] = [
            "videoId": videoId,
            "context": strategy.context,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]

        // Inject PoToken if available
        if let poToken = poToken {
            body["serviceIntegrityDimensions"] = ["poToken": poToken]
        }

        // For cipher-requiring clients, load JS player and add signatureTimestamp
        if strategy.requiresCipher {
            let playerInfo = try await jsPlayer.ensureLoaded()
            var playbackContext = body["playbackContext"] as? [String: Any] ?? [:]
            var contentContext = playbackContext["contentPlaybackContext"] as? [String: Any] ?? [:]
            contentContext["signatureTimestamp"] = playerInfo.signatureTimestamp
            playbackContext["contentPlaybackContext"] = contentContext
            body["playbackContext"] = playbackContext
        }

        let formats = try await callPlayerAPI(body: body, headers: strategy.headers)
        Logger.log("[StreamExtractor] \(strategy.name) returned \(formats.count) audio formats for \(videoId)", category: .playback)

        if strategy.requiresCipher {
            // Cipher clients: may need deobfuscation
            let format = try selectBestAudioFormat(from: formats)

            var resolvedURL: URL
            if let directUrl = format.url, let url = URL(string: directUrl) {
                resolvedURL = url
            } else if let cipherString = format.signatureCipher {
                resolvedURL = try await deobfuscateCipher(cipherString: cipherString)
            } else {
                throw StreamExtractorError.noURLAvailable
            }

            resolvedURL = await deobfuscateNParameter(url: resolvedURL)

            // Append CPN to URL
            resolvedURL = appendQueryParam(to: resolvedURL, name: "cpn", value: cpn)

            let stream = ResolvedStream(
                url: resolvedURL,
                itag: format.itag,
                mimeType: format.mimeType,
                bitrate: format.bitrate,
                playbackHeaders: ["User-Agent": Self.webUserAgent]
            )

            let expiry = extractExpiryDate(from: resolvedURL)
            urlCache[videoId] = CachedStream(stream: stream, expiresAt: expiry)
            return stream
        } else {
            // Direct URL clients
            let directFormats = formats.filter { $0.url != nil }
            guard let format = selectBestFormat(from: directFormats) else {
                Logger.warning("[StreamExtractor] \(strategy.name): no compatible direct formats (total: \(formats.count), direct: \(directFormats.count))", category: .playback)
                throw StreamExtractorError.noCompatibleFormat
            }

            guard let urlString = format.url, var url = URL(string: urlString) else {
                throw StreamExtractorError.noURLAvailable
            }

            // Append CPN to URL
            url = appendQueryParam(to: url, name: "cpn", value: cpn)

            Logger.log("[StreamExtractor] \(strategy.name): selected itag \(format.itag), host: \(url.host ?? "nil")", category: .playback)

            let stream = ResolvedStream(
                url: url,
                itag: format.itag,
                mimeType: format.mimeType,
                bitrate: format.bitrate,
                playbackHeaders: [:]
            )

            let expiry = extractExpiryDate(from: url)
            urlCache[videoId] = CachedStream(stream: stream, expiresAt: expiry)
            return stream
        }
    }

    // MARK: - InnerTube API

    private func callPlayerAPI(body: [String: Any], headers: [String: String]) async throws -> [AudioFormat] {
        let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StreamExtractorError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamExtractorError.networkError("Invalid JSON response")
        }

        // Check playability
        if let playabilityStatus = json["playabilityStatus"] as? [String: Any] {
            let status = playabilityStatus["status"] as? String ?? "unknown"
            if status != "OK" {
                let reason = playabilityStatus["reason"] as? String ?? "Unknown reason"
                throw StreamExtractorError.playabilityError("\(status): \(reason)")
            }
        }

        guard let streamingData = json["streamingData"] as? [String: Any],
              let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] else {
            throw StreamExtractorError.noCompatibleFormat
        }

        // Parse audio formats
        return adaptiveFormats.compactMap { format -> AudioFormat? in
            guard format["width"] == nil else { return nil }
            guard let mimeType = format["mimeType"] as? String else { return nil }

            let isCompatible = mimeType.contains("audio/mp4") || mimeType.contains("audio/m4a")
            let isIncompatible = mimeType.contains("webm") || mimeType.contains("opus")
            guard isCompatible && !isIncompatible else { return nil }

            let directUrl = format["url"] as? String
            let cipher = (format["signatureCipher"] as? String) ?? (format["cipher"] as? String)
            guard directUrl != nil || cipher != nil else { return nil }

            let itag = format["itag"] as? Int ?? 0
            let bitrate = format["bitrate"] as? Int ?? 0

            return AudioFormat(
                itag: itag,
                url: directUrl,
                signatureCipher: cipher,
                mimeType: mimeType,
                bitrate: bitrate
            )
        }
    }

    // MARK: - Format Selection

    private func selectBestAudioFormat(from formats: [AudioFormat]) throws -> AudioFormat {
        guard let format = selectBestFormat(from: formats) else {
            throw StreamExtractorError.noCompatibleFormat
        }
        return format
    }

    private func selectBestFormat(from formats: [AudioFormat]) -> AudioFormat? {
        // Select highest bitrate audio/mp4 for best quality
        return formats.sorted { $0.bitrate > $1.bitrate }.first
    }

    // MARK: - Signature Deobfuscation

    private func deobfuscateCipher(cipherString: String) async throws -> URL {
        // Parse signatureCipher query string: "s=...&sp=...&url=..."
        let params = parseQueryString(cipherString)

        guard let encodedSig = params["s"],
              let baseUrlString = params["url"] else {
            throw StreamExtractorError.invalidCipher
        }

        let signatureParam = params["sp"] ?? "signature"

        // Decode the scrambled signature
        guard let scrambledSig = encodedSig.removingPercentEncoding else {
            throw StreamExtractorError.invalidCipher
        }

        // Run through JS deobfuscation
        let deobfuscatedSig = try await jsPlayer.deobfuscateSignature(scrambledSig)

        // Build final URL
        guard let decodedBaseUrl = baseUrlString.removingPercentEncoding,
              var components = URLComponents(string: decodedBaseUrl) else {
            throw StreamExtractorError.invalidCipher
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: signatureParam, value: deobfuscatedSig))
        components.queryItems = queryItems

        guard let finalURL = components.url else {
            throw StreamExtractorError.invalidCipher
        }

        return finalURL
    }

    // MARK: - N-Parameter Deobfuscation

    private func deobfuscateNParameter(url: URL) async -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let nIndex = queryItems.firstIndex(where: { $0.name == "n" }),
              let nValue = queryItems[nIndex].value else {
            return url // No n-parameter, return as-is
        }

        do {
            let deobfuscatedN = try await jsPlayer.deobfuscateNParameter(nValue)

            if deobfuscatedN != nValue {
                // Successfully deobfuscated — use new value
                var mutableItems = queryItems
                mutableItems[nIndex] = URLQueryItem(name: "n", value: deobfuscatedN)
                components.queryItems = mutableItems
                return components.url ?? url
            } else {
                // Passthrough (deobfuscation returned same value) — remove n-param entirely.
                // YouTube rejects untransformed n-values with 403 but may accept without it.
                var mutableItems = queryItems
                mutableItems.remove(at: nIndex)
                components.queryItems = mutableItems.isEmpty ? nil : mutableItems
                Logger.debug("N-parameter passthrough detected, removing from URL", category: .playback)
                return components.url ?? url
            }
        } catch {
            // Deobfuscation failed — remove n-parameter rather than keeping wrong value
            Logger.warning("N-parameter deobfuscation failed: \(error.localizedDescription), removing from URL", category: .playback)
            var mutableItems = queryItems
            mutableItems.remove(at: nIndex)
            components.queryItems = mutableItems.isEmpty ? nil : mutableItems
            return components.url ?? url
        }
    }

    // MARK: - URL Validation

    /// Validate that a resolved stream URL is accessible (not 403/gone)
    private func validateStreamURL(_ stream: ResolvedStream) async throws -> ResolvedStream {
        var request = URLRequest(url: stream.url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        for (key, value) in stream.playbackHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                if statusCode == 403 {
                    Logger.warning("[StreamExtractor] URL validation: 403 Forbidden for itag \(stream.itag), host: \(stream.url.host ?? "nil")", category: .playback)
                    throw StreamExtractorError.urlValidationFailed(statusCode)
                }
                if statusCode == 410 {
                    Logger.warning("[StreamExtractor] URL validation: 410 Gone for itag \(stream.itag)", category: .playback)
                    throw StreamExtractorError.urlValidationFailed(statusCode)
                }
                Logger.debug("[StreamExtractor] URL validation: HTTP \(statusCode) for itag \(stream.itag)", category: .playback)
            }
        } catch let error as StreamExtractorError {
            throw error
        } catch {
            // Network error during HEAD — some CDNs reject HEAD but serve GET fine
            Logger.debug("[StreamExtractor] URL validation: HEAD failed (\(error.localizedDescription)), proceeding anyway", category: .playback)
        }

        return stream
    }

    // MARK: - Helpers

    /// Produce a concise description of why a strategy failed
    private func describeError(_ error: Error) -> String {
        if let e = error as? StreamExtractorError {
            switch e {
            case .noCompatibleFormat: return "no compatible audio/mp4 formats"
            case .noURLAvailable: return "no URL in response"
            case .playabilityError(let detail): return "playability: \(detail)"
            case .networkError(let detail): return "network: \(detail)"
            case .urlValidationFailed(let status): return "URL returned HTTP \(status)"
            case .invalidCipher: return "invalid cipher data"
            case .deobfuscationFailed(let detail): return "deobfuscation: \(detail)"
            case .playerLoadFailed(let detail): return "player load: \(detail)"
            case .allStrategiesFailed: return "all strategies exhausted"
            }
        }
        return error.localizedDescription
    }

    private func appendQueryParam(to url: URL, name: String, value: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? url
    }

    private func parseQueryString(_ queryString: String) -> [String: String] {
        var params: [String: String] = [:]
        let query = queryString.contains("?") ? String(queryString.split(separator: "?", maxSplits: 1).last ?? "") : queryString

        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1])
                params[key] = value
            }
        }
        return params
    }

    private func extractExpiryDate(from url: URL) -> Date {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let expireString = components.queryItems?.first(where: { $0.name == "expire" })?.value,
           let expireTimestamp = TimeInterval(expireString) {
            // Subtract 5 minutes safety margin
            return Date(timeIntervalSince1970: expireTimestamp - 300)
        }
        // Fallback: 5 hours from now
        return Date().addingTimeInterval(5 * 3600)
    }
}

// MARK: - YouTube JS Player

/// Downloads, caches, and executes YouTube's JS player for deobfuscation
private actor YouTubeJSPlayer {

    struct PlayerInfo {
        let signatureTimestamp: Int
    }

    private var cachedPlayerInfo: PlayerInfo?
    private var cachedPlayerURL: String?
    private var jsContext: JSContext?
    private var loadTask: Task<PlayerInfo, Error>?

    // MARK: - Public API

    func ensureLoaded() async throws -> PlayerInfo {
        if let cached = cachedPlayerInfo {
            return cached
        }

        // Coalesce concurrent loads
        if let existing = loadTask {
            return try await existing.value
        }

        let task = Task<PlayerInfo, Error> { [self] in
            try await self.loadPlayer()
        }

        loadTask = task
        do {
            let result = try await task.value
            cachedPlayerInfo = result
            loadTask = nil
            return result
        } catch {
            loadTask = nil
            throw error
        }
    }

    func deobfuscateSignature(_ scrambled: String) async throws -> String {
        guard let ctx = jsContext else {
            throw StreamExtractorError.deobfuscationFailed("JS player not loaded")
        }

        let escaped = scrambled
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        guard let result = ctx.evaluateScript("deobfuscateSignature('\(escaped)')"),
              !result.isUndefined,
              !result.isNull,
              let value = result.toString(),
              !value.isEmpty,
              value != "undefined" else {
            throw StreamExtractorError.deobfuscationFailed("signature returned invalid result")
        }
        return value
    }

    func deobfuscateNParameter(_ nValue: String) async throws -> String {
        guard let ctx = jsContext else {
            throw StreamExtractorError.deobfuscationFailed("JS player not loaded")
        }

        let escaped = nValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        guard let result = ctx.evaluateScript("deobfuscateN('\(escaped)')"),
              !result.isUndefined,
              !result.isNull,
              let value = result.toString(),
              !value.isEmpty,
              value != "undefined" else {
            throw StreamExtractorError.deobfuscationFailed("n-parameter returned invalid result")
        }
        return value
    }

    func invalidate() {
        cachedPlayerInfo = nil
        cachedPlayerURL = nil
        jsContext = nil
        loadTask = nil
    }

    // MARK: - Player Loading

    private func loadPlayer() async throws -> PlayerInfo {
        // Step 1: Get JS player URL from embed page
        let playerURL = try await fetchPlayerURL()
        Logger.log("Found JS player: \(playerURL.lastPathComponent)", category: .playback)

        // Step 2: Download JS player code
        let jsCode = try await downloadPlayerJS(url: playerURL)
        Logger.log("Downloaded JS player: \(jsCode.count) bytes", category: .playback)

        // Step 3: Extract signature timestamp
        let sigTimestamp = extractSignatureTimestamp(from: jsCode) ?? 0
        Logger.log("Signature timestamp: \(sigTimestamp)", category: .playback)

        // Step 4: Extract and setup deobfuscation functions
        try setupJSContext(jsCode: jsCode)
        Logger.log("JS deobfuscation functions ready", category: .playback)

        cachedPlayerURL = playerURL.absoluteString

        return PlayerInfo(signatureTimestamp: sigTimestamp)
    }

    // MARK: - Fetch Player URL

    private func fetchPlayerURL() async throws -> URL {
        // Use embed page (lighter than full watch page)
        let embedURL = URL(string: "https://www.youtube.com/embed/jNQXAC9IVRw")!
        var request = URLRequest(url: embedURL)
        request.setValue(YouTubeStreamExtractor.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw StreamExtractorError.playerLoadFailed("Could not decode embed page")
        }

        // Pattern: /s/player/HASH/player_ias.vflset/LANG/base.js (or player_es6.vflset)
        let patterns = [
            #"/s/player/[a-zA-Z0-9_-]+/player_ias\.vflset/[a-zA-Z_]+/base\.js"#,
            #"/s/player/[a-zA-Z0-9_-]+/player_es6\.vflset/[a-zA-Z_]+/base\.js"#,
            #"/s/player/[a-zA-Z0-9_-]+/[a-zA-Z0-9_/.]+/base\.js"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range, in: html) {
                let path = String(html[range])
                return URL(string: "https://www.youtube.com\(path)")!
            }
        }

        throw StreamExtractorError.playerLoadFailed("JS player URL not found in embed page")
    }

    // MARK: - Download Player JS

    private func downloadPlayerJS(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(YouTubeStreamExtractor.webUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let jsCode = String(data: data, encoding: .utf8), !jsCode.isEmpty else {
            throw StreamExtractorError.playerLoadFailed("Could not decode JS player")
        }
        return jsCode
    }

    // MARK: - Extract Signature Timestamp

    private func extractSignatureTimestamp(from jsCode: String) -> Int? {
        let patterns = [
            #"(?:signatureTimestamp|sts)\s*:\s*(\d{5})"#,
            #"signatureTimestamp[=:](\d{5})"#,
            #"(?:sts)\s*=\s*(\d{5})"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
               let range = Range(match.range(at: 1), in: jsCode),
               let timestamp = Int(jsCode[range]) {
                return timestamp
            }
        }
        return nil
    }

    // MARK: - Setup JSContext with Deobfuscation Functions

    private func setupJSContext(jsCode: String) throws {
        let ctx = JSContext()!

        ctx.exceptionHandler = { _, exception in
            if let exc = exception {
                Logger.warning("JSContext exception: \(exc)", category: .playback)
            }
        }

        // Detect string lookup array (modern YouTube player 2024+)
        // Example: var y="call{clone{/file/index.m3u8{...}".split("{")
        let arrayInfo = extractStringLookupArray(from: jsCode)
        if let (name, decl) = arrayInfo {
            ctx.evaluateScript(decl + ";")
            Logger.debug("[JSPlayer] Loaded string lookup array '\(name)'", category: .playback)
        }

        // Extract and load signature deobfuscation function
        let sigJS = try extractSignatureJS(from: jsCode, arrayName: arrayInfo?.name)
        ctx.evaluateScript(sigJS)

        // Extract and load n-parameter deobfuscation function
        let nJS = extractNParameterJS(from: jsCode)
        ctx.evaluateScript(nJS)

        // Verify signature function exists
        let sigCheck = ctx.evaluateScript("typeof deobfuscateSignature")
        if sigCheck?.toString() != "function" {
            throw StreamExtractorError.deobfuscationFailed("Signature function not set up correctly")
        }

        self.jsContext = ctx
    }

    // MARK: - String Lookup Array Detection

    /// Detect the string lookup array used by modern YouTube player (2024+).
    /// Modern players store all method/property names in a single array and access
    /// them by index, e.g., `W[y[23]](y[5])` instead of `W.split("")`.
    private func extractStringLookupArray(from jsCode: String) -> (name: String, declaration: String)? {
        // Match: var NAME = "LONG_STRING".split("DELIMITER")
        // The string must be long enough (100+ chars) to avoid false positives
        let pattern = #"(var\s+(\w+)\s*=\s*"[^"]{100,}"\s*\.split\s*\(\s*"[^"]{1}"\s*\))"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
              let fullRange = Range(match.range(at: 1), in: jsCode),
              let nameRange = Range(match.range(at: 2), in: jsCode) else {
            return nil
        }

        let name = String(jsCode[nameRange])
        let declaration = String(jsCode[fullRange])
        return (name, declaration)
    }

    // MARK: - Extract Signature Deobfuscation JS

    private func extractSignatureJS(from jsCode: String, arrayName: String?) throws -> String {
        // Try modern approach first (2024+ YouTube player with string lookup array)
        if let arrayName = arrayName,
           let modernJS = extractModernSignatureJS(from: jsCode, arrayName: arrayName) {
            Logger.debug("[JSPlayer] Using modern signature extraction", category: .playback)
            return modernJS
        }

        // Fall back to legacy approach (pre-2024 players with direct function names)
        Logger.debug("[JSPlayer] Falling back to legacy signature extraction", category: .playback)
        return try extractLegacySignatureJS(from: jsCode)
    }

    // MARK: - Modern Signature Extraction (2024+ YouTube player)

    /// Extracts signature deobfuscation JS for modern YouTube players that use
    /// a string lookup array for all method/property names.
    /// The string lookup array must already be loaded into JSContext.
    private func extractModernSignatureJS(from jsCode: String, arrayName: String) -> String? {
        // Step 1: Find signature function via its invocation pattern
        // YouTube calls: FUNC(NUM, decodeURIComponent(VAR.s))
        let invocationPattern = #"(\w+)\(\d+\s*,\s*decodeURIComponent\(\w+\.s\)\)"#
        guard let regex = try? NSRegularExpression(pattern: invocationPattern),
              let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
              let nameRange = Range(match.range(at: 1), in: jsCode) else {
            Logger.debug("[JSPlayer] Modern sig: invocation pattern not found", category: .playback)
            return nil
        }
        let sigFuncName = String(jsCode[nameRange])

        // Step 2: Extract the full function definition
        guard let fullFunc = extractFullFunction(named: sigFuncName, from: jsCode) else {
            Logger.debug("[JSPlayer] Modern sig: function body not found for '\(sigFuncName)'", category: .playback)
            return nil
        }

        // Step 3: Find helper object(s) referenced via array-indexed calls
        // Pattern: HELPER[arrayName[NUM]]( — e.g., ZZ[y[19]](q,2)
        let escapedArray = NSRegularExpression.escapedPattern(for: arrayName)
        let helperPattern = "([a-zA-Z0-9_$]{2,})\\[\(escapedArray)\\[\\d+\\]\\]\\("
        var helperJS = ""

        if let helperRegex = try? NSRegularExpression(pattern: helperPattern) {
            let matches = helperRegex.matches(in: fullFunc, range: NSRange(fullFunc.startIndex..., in: fullFunc))
            var candidates = Set<String>()
            for m in matches {
                if let range = Range(m.range(at: 1), in: fullFunc) {
                    candidates.insert(String(fullFunc[range]))
                }
            }

            // Include candidates that are declared as objects in the full JS
            for candidate in candidates {
                if let helperBody = extractObjectBody(named: candidate, from: jsCode) {
                    helperJS += "var \(candidate)={\(helperBody)};\n"
                    Logger.debug("[JSPlayer] Modern sig: found helper object '\(candidate)'", category: .playback)
                }
            }
        }

        // Step 4: Determine the bitmask argument from invocation context
        let escapedFunc = NSRegularExpression.escapedPattern(for: sigFuncName)
        let bitmaskPattern = "\(escapedFunc)\\((\\d+)\\s*,\\s*decodeURIComponent"
        var bitmask = "10" // default — works for both signatureCipher and direct sig
        if let bmRegex = try? NSRegularExpression(pattern: bitmaskPattern),
           let bmMatch = bmRegex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
           let bmRange = Range(bmMatch.range(at: 1), in: jsCode) {
            bitmask = String(jsCode[bmRange])
        }

        Logger.debug("[JSPlayer] Modern sig: func=\(sigFuncName), bitmask=\(bitmask)", category: .playback)

        return """
        \(helperJS)
        var \(sigFuncName) = \(fullFunc);
        function deobfuscateSignature(a) { return \(sigFuncName)(\(bitmask), a); }
        """
    }

    // MARK: - Legacy Signature Extraction (pre-2024 YouTube player)

    private func extractLegacySignatureJS(from jsCode: String) throws -> String {
        // Step 1: Find the initial function name
        // Patterns ported from yt-dlp / SimpMusic's SmartTube SigExtractor
        let funcNamePatterns = [
            // Primary (current YouTube player) — yt-dlp pattern 1
            #"\b([a-zA-Z0-9_$]+)&&\(\1=([a-zA-Z0-9_$]{2,})\(decodeURIComponent\(\1\)\)"#,
            // Split/join function definition — yt-dlp pattern 2
            #"([a-zA-Z0-9_$]+)\s*=\s*function\(\s*([a-zA-Z0-9_$]+)\s*\)\s*\{\s*\2\s*=\s*\2\.split\(\s*""\s*\)\s*;\s*[^}]+;\s*return\s+\2\.join\(\s*""\s*\)"#,
            // Alternative split form — yt-dlp pattern 3
            #"(?:\b|[^a-zA-Z0-9_$])([a-zA-Z0-9_$]{2,})\s*=\s*function\(\s*a\s*\)\s*\{\s*a\s*=\s*a\.split\(\s*""\s*\)"#,
            // set+encodeURIComponent — yt-dlp pattern 4
            #"\b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\s*\(\s*([a-zA-Z0-9$]+)\("#,
            // Generic set+encodeURIComponent — yt-dlp pattern 5
            #"\b[a-zA-Z0-9]+\s*&&\s*[a-zA-Z0-9]+\.set\([^,]+\s*,\s*encodeURIComponent\s*\(\s*([a-zA-Z0-9$]+)\("#,
            // m=FUNC(decodeURIComponent(h.s)) — yt-dlp pattern 6
            #"\bm=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(h\.s\)\)"#,
            // Older patterns as fallbacks
            #"\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*([a-zA-Z0-9$]+)\("#,
            #"\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\("#
        ]

        var funcName: String?
        for (patternIndex, pattern) in funcNamePatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)) else {
                continue
            }
            let groupIndex = (patternIndex == 0 && match.numberOfRanges > 2) ? 2 : 1
            if let range = Range(match.range(at: groupIndex), in: jsCode) {
                funcName = String(jsCode[range])
                Logger.debug("[JSPlayer] Sig function '\(funcName!)' found via legacy pattern \(patternIndex + 1)", category: .playback)
                break
            }
        }

        guard let sigFuncName = funcName else {
            throw StreamExtractorError.deobfuscationFailed("Signature function name not found")
        }

        let funcBody = try extractFunctionBody(named: sigFuncName, from: jsCode)

        let helperPattern = #";([a-zA-Z0-9$]{2,})\.\w+\("#
        var helperJS = ""

        if let regex = try? NSRegularExpression(pattern: helperPattern),
           let match = regex.firstMatch(in: funcBody, range: NSRange(funcBody.startIndex..., in: funcBody)),
           let range = Range(match.range(at: 1), in: funcBody) {
            let helperName = String(funcBody[range])
            if let helperBody = extractObjectBody(named: helperName, from: jsCode) {
                helperJS = "var \(helperName)={\(helperBody)};"
            }
        }

        return """
        \(helperJS)
        function deobfuscateSignature(a) {
            a = a.split("");
            \(funcBody)
        }
        """
    }

    // MARK: - Extract N-Parameter Deobfuscation JS

    private func extractNParameterJS(from jsCode: String) -> String {
        // The n-parameter function prevents throttling
        // Patterns ported from yt-dlp / SimpMusic's SmartTube NSigExtractor
        let nFuncPatterns: [(pattern: String, nameGroup: Int, indexGroup: Int?)] = [
            // Primary: .get("n"))&&(b=FUNC[IDX](b) — original form
            (#"\.get\("n"\)\)&&\(b=([a-zA-Z0-9_$]+)(?:\[(\d+)\])?\([a-zA-Z]\)"#, 1, 2),
            // String.fromCharCode(110) form (110 = 'n') with .get(b) or [b]||null
            (#"b=String\.fromCharCode\(110\)(?:,[a-zA-Z0-9_$]+\([a-zA-Z]\))?,c=a\.(?:get\(b\)|[a-zA-Z0-9_$]+\[b\]\|\|null)\)&&\(c=([a-zA-Z0-9_$]+)(?:\[(\d+)\])?\([a-zA-Z]\)"#, 1, 2),
            // "nn"[+X] form
            (#"[a-zA-Z0-9_$.]+&&\(b="nn"\[\+[a-zA-Z0-9_$.]+\](?:,[a-zA-Z0-9_$]+\([a-zA-Z]\))?,c=a\.(?:get\(b\)|[a-zA-Z0-9_$]+\[b\]\|\|null)\)&&\(c=([a-zA-Z0-9_$]+)(?:\[(\d+)\])?\([a-zA-Z]\)"#, 1, 2),
            // var= form with .set() afterward
            (#"\b([a-zA-Z0-9_$]+)=([a-zA-Z0-9_$]+)(?:\[(\d+)\])?\([a-zA-Z]\),[a-zA-Z0-9_$]+\.set\((?:"n+"|[a-zA-Z0-9_$]+),\1\)"#, 2, 3),
            // Fallback: _w8_ return value pattern
            (#";\s*([a-zA-Z0-9_$]+)\s*=\s*function\([a-zA-Z0-9_$]+\)\s*\{(?:(?!\};).)+?return\s*["'][\w-]+_w8_["']\s*\+\s*[a-zA-Z0-9_$]+"#, 1, nil)
        ]

        for (pattern, nameGroup, indexGroup) in nFuncPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
                  match.numberOfRanges > nameGroup,
                  let nameRange = Range(match.range(at: nameGroup), in: jsCode) else {
                continue
            }

            var nFuncName = String(jsCode[nameRange])
            Logger.debug("[JSPlayer] N-function '\(nFuncName)' found via pattern", category: .playback)

            // If it's an array reference like funcArray[0], resolve it
            if let idxGroup = indexGroup,
               match.numberOfRanges > idxGroup,
               match.range(at: idxGroup).location != NSNotFound,
               let indexRange = Range(match.range(at: idxGroup), in: jsCode),
               let index = Int(jsCode[indexRange]) {
                if let resolved = resolveArrayFunction(arrayName: nFuncName, index: index, from: jsCode) {
                    nFuncName = resolved
                    Logger.debug("[JSPlayer] N-function resolved from array to '\(nFuncName)'", category: .playback)
                }
            }

            // Extract the full function
            if let fullFunc = extractFullFunction(named: nFuncName, from: jsCode) {
                return """
                var \(nFuncName) = \(fullFunc);
                function deobfuscateN(a) { return \(nFuncName)(a); }
                """
            }
        }

        // N-parameter not always required - return passthrough
        Logger.log("N-parameter function not found, using passthrough", category: .playback)
        return "function deobfuscateN(a) { return a; }"
    }

    // MARK: - JS Extraction Helpers

    /// Extract a function body by name (content between the outermost braces)
    private func extractFunctionBody(named funcName: String, from jsCode: String) throws -> String {
        let escaped = NSRegularExpression.escapedPattern(for: funcName)
        // Negative lookbehind prevents matching "is" inside "this" etc.
        let patterns = [
            "(?<![a-zA-Z0-9_$])\(escaped)\\s*=\\s*function\\s*\\([^)]*\\)\\s*\\{",
            "function\\s+\(escaped)\\s*\\([^)]*\\)\\s*\\{"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
                  let range = Range(match.range, in: jsCode) else { continue }

            // Find matching closing brace
            let startIdx = range.upperBound
            var braceCount = 1
            var current = startIdx

            while current < jsCode.endIndex && braceCount > 0 {
                let char = jsCode[current]
                if char == "{" { braceCount += 1 }
                else if char == "}" { braceCount -= 1 }
                current = jsCode.index(after: current)
            }

            if braceCount == 0 {
                let bodyEnd = jsCode.index(before: current)
                let body = String(jsCode[startIdx..<bodyEnd])
                // Remove the "a=a.split("");" prefix if present since we add it ourselves
                return body
                    .replacingOccurrences(of: "a=a.split(\"\");", with: "")
                    .replacingOccurrences(of: "a=a.split(\"\")", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        throw StreamExtractorError.deobfuscationFailed("Function body not found: \(funcName)")
    }

    /// Extract a full function definition (including the function keyword and braces)
    private func extractFullFunction(named funcName: String, from jsCode: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: funcName)
        // Negative lookbehind prevents matching "is" inside "this" etc.
        let patterns = [
            "(?<![a-zA-Z0-9_$])\(escaped)\\s*=\\s*function\\s*\\([^)]*\\)\\s*\\{",
            "function\\s+\(escaped)\\s*\\([^)]*\\)\\s*\\{"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
                  let matchRange = Range(match.range, in: jsCode) else { continue }

            // Find the "function" part
            let matchStr = String(jsCode[matchRange])
            let funcStart: String.Index
            if matchStr.contains("=") {
                // Pattern: NAME = function(...) {
                // We want from "function" onwards
                if let funcKeyword = jsCode.range(of: "function", range: matchRange) {
                    funcStart = funcKeyword.lowerBound
                } else {
                    funcStart = matchRange.lowerBound
                }
            } else {
                funcStart = matchRange.lowerBound
            }

            // Find matching closing brace
            let braceStart = matchRange.upperBound
            var braceCount = 1
            var current = braceStart

            while current < jsCode.endIndex && braceCount > 0 {
                let char = jsCode[current]
                if char == "{" { braceCount += 1 }
                else if char == "}" { braceCount -= 1 }
                current = jsCode.index(after: current)
            }

            if braceCount == 0 {
                return String(jsCode[funcStart..<current])
            }
        }

        return nil
    }

    /// Extract an object body by name (the content between { })
    private func extractObjectBody(named objName: String, from jsCode: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: objName)
        let pattern = "var\\s+\(escaped)\\s*=\\s*\\{"

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
              let range = Range(match.range, in: jsCode) else {
            return nil
        }

        // Find the opening brace position
        guard let braceRange = jsCode.range(of: "{", range: range.lowerBound..<jsCode.endIndex) else {
            return nil
        }

        let afterBrace = braceRange.upperBound
        var braceCount = 1
        var current = afterBrace

        while current < jsCode.endIndex && braceCount > 0 {
            let char = jsCode[current]
            if char == "{" { braceCount += 1 }
            else if char == "}" { braceCount -= 1 }
            current = jsCode.index(after: current)
        }

        if braceCount == 0 {
            let bodyEnd = jsCode.index(before: current)
            return String(jsCode[afterBrace..<bodyEnd])
        }

        return nil
    }

    /// Resolve an array function reference like: var arr = [func1, func2]; arr[0] -> func1
    private func resolveArrayFunction(arrayName: String, index: Int, from jsCode: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: arrayName)
        let pattern = "var\\s+\(escaped)\\s*=\\s*\\[([^\\]]+)\\]"

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
              let range = Range(match.range(at: 1), in: jsCode) else {
            return nil
        }

        let arrayContent = String(jsCode[range])
        let elements = arrayContent.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard index < elements.count else { return nil }
        return elements[index]
    }
}
