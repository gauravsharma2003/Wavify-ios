//
//  VisitorDataScraper.swift
//  Wavify
//
//  Scrapes fresh visitorData from YouTube watch page HTML
//

import Foundation

actor VisitorDataScraper {
    static let shared = VisitorDataScraper()

    private var lastScrapeAt: Date?
    private let cooldown: TimeInterval = 3600 // 1 hour between scrapes

    private init() {}

    /// Scrape fresh visitorData from YouTube. Updates YouTubeAPIContext.visitorData on success.
    func scrape() async {
        // Debounce: don't scrape more than once per hour
        if let last = lastScrapeAt, Date().timeIntervalSince(last) < cooldown {
            return
        }

        do {
            let visitorData = try await fetchVisitorData()
            YouTubeAPIContext.visitorData = visitorData
            lastScrapeAt = Date()
            Logger.log("[VisitorData] Scraped: \(visitorData.prefix(20))...", category: .network)
        } catch {
            Logger.warning("[VisitorData] Scrape failed: \(error.localizedDescription)", category: .network)
        }
    }

    private func fetchVisitorData() async throws -> String {
        let url = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(YouTubeStreamExtractor.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw VisitorDataError.decodeFailed
        }

        // Try multiple patterns for visitorData
        let patterns = [
            #""visitorData"\s*:\s*"([^"]+)""#,
            #"visitorData\\?":\s*\\?"([^"\\]+)"#,
            #"visitor_data\s*=\s*"([^"]+)""#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                let value = String(html[range])
                if !value.isEmpty {
                    return value
                }
            }
        }

        throw VisitorDataError.notFound
    }
}

private enum VisitorDataError: Error, LocalizedError {
    case decodeFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .decodeFailed: return "Could not decode YouTube page"
        case .notFound: return "visitorData not found in page"
        }
    }
}
