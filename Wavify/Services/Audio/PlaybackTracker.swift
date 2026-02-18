//
//  PlaybackTracker.swift
//  Wavify
//
//  Reports playback analytics to YouTube so plays count for artists
//

import Foundation

actor PlaybackTracker {

    private var currentInfo: PlaybackInfo?
    private var startTime: Double = 0
    private var lastReportedTime: Double = 0
    private var hasInitialized = false
    private var reportedThresholds: Set<Int> = []

    // Thresholds for watchtime reporting: 10s, 30s, 60s, then every 60s
    private static let initialThresholds = [10, 30, 60]

    // MARK: - Public API

    /// Start tracking a new playback session
    func startTracking(info: PlaybackInfo) {
        currentInfo = info
        startTime = 0
        lastReportedTime = 0
        hasInitialized = false
        reportedThresholds = []

        // Fire initial playback tracking request
        guard let baseUrl = info.playbackTrackingUrl, !baseUrl.isEmpty else { return }

        let url = buildTrackingURL(base: baseUrl, params: [
            "cpn": info.cpn,
            "ver": "2",
            "c": "WEB_REMIX",
            "cmt": "0"
        ])

        fireAndForget(url: url)
        hasInitialized = true
        Logger.debug("[PlaybackTracker] initPlayback sent", category: .playback)
    }

    /// Report current playback time — fires watchtime at thresholds
    func reportTime(currentTime: Double) {
        guard let info = currentInfo, hasInitialized else { return }
        guard let baseUrl = info.watchtimeTrackingUrl, !baseUrl.isEmpty else { return }

        let currentSecond = Int(currentTime)

        // Check initial thresholds
        for threshold in Self.initialThresholds {
            if currentSecond >= threshold && !reportedThresholds.contains(threshold) {
                reportedThresholds.insert(threshold)
                sendWatchtime(baseUrl: baseUrl, info: info, startTime: lastReportedTime, endTime: currentTime)
                lastReportedTime = currentTime
                return
            }
        }

        // After 60s, report every 60s
        if currentSecond >= 60 {
            let nextThreshold = ((currentSecond / 60) * 60)
            if nextThreshold > 60 && !reportedThresholds.contains(nextThreshold) {
                reportedThresholds.insert(nextThreshold)
                sendWatchtime(baseUrl: baseUrl, info: info, startTime: lastReportedTime, endTime: currentTime)
                lastReportedTime = currentTime
            }
        }
    }

    /// Stop tracking and send ATR (end-of-session attestation)
    func stopTracking() {
        guard let info = currentInfo, hasInitialized else {
            currentInfo = nil
            return
        }

        if let baseUrl = info.atrTrackingUrl, !baseUrl.isEmpty {
            let url = buildTrackingURL(base: baseUrl, params: [
                "cpn": info.cpn,
                "ver": "2",
                "c": "WEB_REMIX",
                "cmt": String(format: "%.1f", lastReportedTime)
            ])
            fireAndForget(url: url)
            Logger.debug("[PlaybackTracker] atr sent", category: .playback)
        }

        currentInfo = nil
        hasInitialized = false
    }

    // MARK: - Private

    private func sendWatchtime(baseUrl: String, info: PlaybackInfo, startTime: Double, endTime: Double) {
        let url = buildTrackingURL(base: baseUrl, params: [
            "cpn": info.cpn,
            "ver": "2",
            "c": "WEB_REMIX",
            "st": String(format: "%.1f", startTime),
            "et": String(format: "%.1f", endTime),
            "cmt": String(format: "%.1f", endTime)
        ])
        fireAndForget(url: url)
        Logger.debug("[PlaybackTracker] watchtime sent st=\(String(format: "%.0f", startTime)) et=\(String(format: "%.0f", endTime))", category: .playback)
    }

    private func buildTrackingURL(base: String, params: [String: String]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        for (key, value) in params {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url
    }

    private nonisolated func fireAndForget(url: URL?) {
        guard let url = url else { return }
        Task.detached(priority: .background) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            do {
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                Logger.debug("[PlaybackTracker] request failed: \(error.localizedDescription)", category: .playback)
            }
        }
    }
}
