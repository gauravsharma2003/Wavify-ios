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

    var errorDescription: String? {
        switch self {
        case .noURLAvailable: return "No audio URL available for this video"
        case .noCompatibleFormat: return "No compatible audio format found"
        case .invalidCipher: return "Invalid signature cipher"
        case .deobfuscationFailed(let detail): return "Deobfuscation failed: \(detail)"
        case .playerLoadFailed(let detail): return "Player load failed: \(detail)"
        case .networkError(let detail): return "Network error: \(detail)"
        case .playabilityError(let detail): return "Playability error: \(detail)"
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

    // MARK: - State

    private var urlCache: [String: CachedStream] = [:]
    private let jsPlayer = YouTubeJSPlayer()

    private init() {}

    // MARK: - Public API

    /// Resolve a playable audio URL for a YouTube video
    func resolveAudioURL(videoId: String) async throws -> ResolvedStream {
        // Check cache first
        if let cached = urlCache[videoId], !cached.isExpired {
            Logger.log("Stream cache hit for \(videoId)", category: .playback)
            return cached.stream
        }

        // Primary: ANDROID_VR client (direct URLs, no PoT required)
        do {
            let stream = try await resolveViaAndroidVRClient(videoId: videoId)
            Logger.log("Resolved via ANDROID_VR client: itag \(stream.itag)", category: .playback)
            return stream
        } catch {
            Logger.warning("ANDROID_VR client failed: \(error.localizedDescription), trying WEB client", category: .playback)
        }

        // Fallback: WEB client with JS deobfuscation (handles cipher-protected streams)
        let stream = try await resolveViaWebClient(videoId: videoId)
        Logger.log("Resolved via WEB client: itag \(stream.itag)", category: .playback)
        return stream
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

    // MARK: - WEB Client Resolution (with deobfuscation)

    private func resolveViaWebClient(videoId: String) async throws -> ResolvedStream {
        // Ensure JS player is loaded and ready
        let playerInfo = try await jsPlayer.ensureLoaded()

        // Call InnerTube /player API with WEB context + signatureTimestamp
        let formats = try await fetchStreamingData(
            videoId: videoId,
            signatureTimestamp: playerInfo.signatureTimestamp
        )

        // Select best audio format
        let format = try selectBestAudioFormat(from: formats)

        // Resolve URL (direct or cipher)
        var resolvedURL: URL
        if let directUrl = format.url, let url = URL(string: directUrl) {
            resolvedURL = url
        } else if let cipherString = format.signatureCipher {
            resolvedURL = try await deobfuscateCipher(cipherString: cipherString)
        } else {
            throw StreamExtractorError.noURLAvailable
        }

        // Deobfuscate n-parameter (prevents throttling/403)
        resolvedURL = await deobfuscateNParameter(url: resolvedURL)

        let stream = ResolvedStream(
            url: resolvedURL,
            itag: format.itag,
            mimeType: format.mimeType,
            bitrate: format.bitrate,
            playbackHeaders: ["User-Agent": Self.webUserAgent]
        )

        // Cache with TTL from URL expire parameter
        let expiry = extractExpiryDate(from: resolvedURL)
        urlCache[videoId] = CachedStream(stream: stream, expiresAt: expiry)

        return stream
    }

    // MARK: - ANDROID_VR Client (primary path, no PoT required)

    private func resolveViaAndroidVRClient(videoId: String) async throws -> ResolvedStream {
        let vrVersion = "1.71.26"
        let vrUA = "com.google.android.apps.youtube.vr.oculus/\(vrVersion) (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

        let body: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "ANDROID_VR",
                    "clientVersion": vrVersion,
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3",
                    "androidSdkVersion": 32,
                    "userAgent": vrUA,
                    "osName": "Android",
                    "osVersion": "12L",
                    "hl": "en",
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0
                ]
            ],
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]

        let headers = [
            "Content-Type": "application/json",
            "User-Agent": vrUA,
            "X-Youtube-Client-Name": "28",
            "X-Youtube-Client-Version": vrVersion,
            "Origin": "https://www.youtube.com"
        ]

        let formats = try await callPlayerAPI(body: body, headers: headers)
        Logger.log("ANDROID_VR client returned \(formats.count) audio formats for \(videoId)", category: .playback)

        let directFormats = formats.filter { $0.url != nil }
        guard let format = selectBestFormat(from: directFormats) else {
            Logger.warning("ANDROID_VR: no compatible direct formats (total: \(formats.count), direct: \(directFormats.count))", category: .playback)
            throw StreamExtractorError.noCompatibleFormat
        }

        guard let urlString = format.url, let url = URL(string: urlString) else {
            throw StreamExtractorError.noURLAvailable
        }

        Logger.log("ANDROID_VR: selected itag \(format.itag), host: \(url.host ?? "nil")", category: .playback)

        let stream = ResolvedStream(
            url: url,
            itag: format.itag,
            mimeType: format.mimeType,
            bitrate: format.bitrate,
            playbackHeaders: [:]  // ANDROID_VR URLs work with default AVPlayer UA
        )

        let expiry = extractExpiryDate(from: url)
        urlCache[videoId] = CachedStream(stream: stream, expiresAt: expiry)

        return stream
    }

    // MARK: - InnerTube API

    private func fetchStreamingData(videoId: String, signatureTimestamp: Int) async throws -> [AudioFormat] {
        let body: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20250120.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "playbackContext": [
                "contentPlaybackContext": [
                    "signatureTimestamp": signatureTimestamp
                ]
            ],
            "contentCheckOk": true,
            "racyCheckOk": true
        ]

        let headers = [
            "Content-Type": "application/json",
            "User-Agent": Self.webUserAgent,
            "Origin": "https://www.youtube.com",
            "Referer": "https://www.youtube.com/",
            "X-YouTube-Client-Name": "1",
            "X-YouTube-Client-Version": "2.20250120.01.00"
        ]

        return try await callPlayerAPI(body: body, headers: headers)
    }

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
            // Must be audio-only (no width means audio)
            guard format["width"] == nil else { return nil }

            guard let mimeType = format["mimeType"] as? String else { return nil }

            // Must be mp4/m4a (AVPlayer compatible)
            let isCompatible = mimeType.contains("audio/mp4") || mimeType.contains("audio/m4a")
            let isIncompatible = mimeType.contains("webm") || mimeType.contains("opus")
            guard isCompatible && !isIncompatible else { return nil }

            // Must have either direct URL or signatureCipher
            let directUrl = format["url"] as? String
            let cipher = format["signatureCipher"] as? String
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
        // Prefer itag 140 (AAC 128kbps mp4) - universal iOS compatibility
        if let itag140 = formats.first(where: { $0.itag == 140 }) {
            return itag140
        }
        // Fallback: highest bitrate audio/mp4
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

            var mutableItems = queryItems
            mutableItems[nIndex] = URLQueryItem(name: "n", value: deobfuscatedN)
            components.queryItems = mutableItems

            return components.url ?? url
        } catch {
            Logger.warning("N-parameter deobfuscation failed: \(error.localizedDescription)", category: .playback)
            return url // Return original URL as fallback
        }
    }

    // MARK: - Helpers

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

        // Extract and load signature deobfuscation function
        let sigJS = try extractSignatureJS(from: jsCode)
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

    // MARK: - Extract Signature Deobfuscation JS

    private func extractSignatureJS(from jsCode: String) throws -> String {
        // Step 1: Find the initial function name
        // YouTube uses patterns like:
        //   a.set("alr","yes");c&&(c=FUNCNAME(decodeURIComponent(c))
        //   c=[a]&&d.set(...,encodeURIComponent(FUNCNAME(...)))
        let funcNamePatterns = [
            #"\b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\("#,
            #"\bm=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(h\.s\)\)"#,
            #"\bc\s*&&\s*d\.set\([^,]+\s*,\s*(?:encodeURIComponent\s*\()([a-zA-Z0-9$]+)\("#,
            #"\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*([a-zA-Z0-9$]+)\("#,
            #"\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\("#,
            #"(?:\b|[^a-zA-Z0-9$])([a-zA-Z0-9$]{2,})\s*=\s*function\(\s*a\s*\)\s*\{\s*a\s*=\s*a\.split\(\s*""\s*\)"#
        ]

        var funcName: String?
        for pattern in funcNamePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: jsCode) {
                funcName = String(jsCode[range])
                break
            }
        }

        guard let sigFuncName = funcName else {
            throw StreamExtractorError.deobfuscationFailed("Signature function name not found")
        }

        // Step 2: Extract the function body
        let funcBody = try extractFunctionBody(named: sigFuncName, from: jsCode)

        // Step 3: Find the helper object (contains reverse, splice, swap operations)
        // The function body references helper like: XX.YY(a, N)
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
        // Pattern: .get("n"))&&(b=FUNCNAME(b)  or  .get("n"))&&(b=FUNCNAME[INDEX](b)
        let nFuncPatterns = [
            #"\.get\("n"\)\)&&\(b=([a-zA-Z0-9$]+)(?:\[(\d+)\])?\(b\)"#,
            #"\.get\("n"\)\)&&\(b=([a-zA-Z0-9$]{2,})\(b\)"#
        ]

        for pattern in nFuncPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: jsCode, range: NSRange(jsCode.startIndex..., in: jsCode)),
                  let nameRange = Range(match.range(at: 1), in: jsCode) else {
                continue
            }

            var nFuncName = String(jsCode[nameRange])

            // If it's an array reference like funcArray[0], resolve it
            if match.numberOfRanges > 2,
               let indexRange = Range(match.range(at: 2), in: jsCode),
               let index = Int(jsCode[indexRange]) {
                if let resolved = resolveArrayFunction(arrayName: nFuncName, index: index, from: jsCode) {
                    nFuncName = resolved
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
        let patterns = [
            "\(escaped)\\s*=\\s*function\\s*\\([^)]*\\)\\s*\\{",
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
        let patterns = [
            "\(escaped)\\s*=\\s*function\\s*\\([^)]*\\)\\s*\\{",
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
