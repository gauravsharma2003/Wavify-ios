//
//  CachedFormatStore.swift
//  Wavify
//
//  Actor-based SwiftData accessor for cached audio format URLs
//

import Foundation
import SwiftData

actor CachedFormatStore {
    static let shared = CachedFormatStore()

    private var modelContainer: ModelContainer?

    private init() {}

    /// Configure with the app's shared ModelContainer (call once on launch)
    func configure(with container: ModelContainer) {
        self.modelContainer = container
    }

    /// Get a cached format if it exists and hasn't expired
    func get(videoId: String) -> CachedFormat? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let predicate = #Predicate<CachedFormat> { $0.videoId == videoId }
        var descriptor = FetchDescriptor<CachedFormat>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let cached = try? context.fetch(descriptor).first else { return nil }

        if cached.expiresAt < Date() {
            context.delete(cached)
            try? context.save()
            return nil
        }

        return cached
    }

    /// Save or update a cached format entry
    func save(
        videoId: String,
        info: PlaybackInfo,
        stream: YouTubeStreamExtractor.ResolvedStream
    ) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        // Delete existing entry for this videoId
        let predicate = #Predicate<CachedFormat> { $0.videoId == videoId }
        let descriptor = FetchDescriptor<CachedFormat>(predicate: predicate)
        if let existing = try? context.fetch(descriptor) {
            for entry in existing {
                context.delete(entry)
            }
        }

        let headersJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: stream.playbackHeaders),
           let str = String(data: data, encoding: .utf8) {
            headersJSON = str
        } else {
            headersJSON = "{}"
        }

        let cached = CachedFormat(
            videoId: videoId,
            audioUrl: stream.url.absoluteString,
            itag: stream.itag,
            mimeType: stream.mimeType,
            bitrate: stream.bitrate,
            playbackHeadersJSON: headersJSON,
            cpn: info.cpn,
            loudnessDb: info.loudnessDb,
            expiresAt: info.expiresAt ?? Date().addingTimeInterval(5 * 3600),
            playbackTrackingUrl: info.playbackTrackingUrl,
            watchtimeTrackingUrl: info.watchtimeTrackingUrl,
            atrTrackingUrl: info.atrTrackingUrl
        )

        context.insert(cached)
        try? context.save()
    }

    /// Delete all expired entries
    func pruneExpired() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let now = Date()
        let predicate = #Predicate<CachedFormat> { $0.expiresAt < now }
        let descriptor = FetchDescriptor<CachedFormat>(predicate: predicate)

        if let expired = try? context.fetch(descriptor) {
            for entry in expired {
                context.delete(entry)
            }
            try? context.save()
        }
    }

    /// Convert a CachedFormat to PlaybackInfo (metadata fields filled by caller)
    func toPlaybackInfo(from cached: CachedFormat, metadata: PlaybackInfo) -> PlaybackInfo {
        var headers: [String: String] = [:]
        if let data = cached.playbackHeadersJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            headers = dict
        }

        return PlaybackInfo(
            audioUrl: cached.audioUrl,
            videoId: metadata.videoId,
            title: metadata.title,
            duration: metadata.duration,
            thumbnailUrl: metadata.thumbnailUrl,
            artist: metadata.artist,
            viewCount: metadata.viewCount,
            artistId: metadata.artistId,
            albumId: metadata.albumId,
            playbackHeaders: headers,
            cpn: cached.cpn,
            loudnessDb: cached.loudnessDb,
            expiresAt: cached.expiresAt,
            playbackTrackingUrl: cached.playbackTrackingUrl,
            watchtimeTrackingUrl: cached.watchtimeTrackingUrl,
            atrTrackingUrl: cached.atrTrackingUrl
        )
    }
}
