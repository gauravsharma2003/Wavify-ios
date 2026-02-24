//
//  CloudTrackCache.swift
//  Wavify
//
//  Caches the last 10 played cloud tracks locally for instant playback
//

import Foundation

actor CloudTrackCache {
    static let shared = CloudTrackCache()

    private let maxCachedTracks = 10
    private let cacheDir: URL
    private let manifestURL: URL

    /// Ordered list of cached file IDs (newest first)
    private var manifest: [CachedEntry] = []

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("CloudAudioCache", isDirectory: true)
        manifestURL = cacheDir.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadManifest()
    }

    // MARK: - Public API

    /// Returns the local file URL if the track is cached, nil otherwise
    func cachedURL(for fileId: String) -> URL? {
        guard let entry = manifest.first(where: { $0.fileId == fileId }) else { return nil }
        let path = audioPath(for: fileId, ext: entry.fileExtension)
        guard FileManager.default.fileExists(atPath: path.path) else {
            // Manifest entry exists but file is missing — clean up
            manifest.removeAll(where: { $0.fileId == fileId })
            saveManifest()
            return nil
        }
        return path
    }

    /// Cache audio data for a cloud track
    func cacheTrack(fileId: String, ext: String, data: Data) {
        let path = audioPath(for: fileId, ext: ext)
        do {
            try data.write(to: path)
        } catch {
            return
        }

        // Remove old entry for this fileId (may have different extension)
        if let oldEntry = manifest.first(where: { $0.fileId == fileId }) {
            let oldPath = audioPath(for: fileId, ext: oldEntry.fileExtension)
            if oldPath != path { try? FileManager.default.removeItem(at: oldPath) }
        }
        manifest.removeAll(where: { $0.fileId == fileId })
        manifest.insert(CachedEntry(fileId: fileId, fileExtension: ext, cachedAt: Date()), at: 0)

        // Evict oldest if over limit
        while manifest.count > maxCachedTracks {
            let evicted = manifest.removeLast()
            let evictedPath = audioPath(for: evicted.fileId, ext: evicted.fileExtension)
            try? FileManager.default.removeItem(at: evictedPath)
        }

        saveManifest()
    }

    /// Download and cache a track from Google Drive
    func downloadAndCache(fileId: String, ext: String, accessToken: String) async {
        // Skip if already cached
        if cachedURL(for: fileId) != nil { return }

        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
            cacheTrack(fileId: fileId, ext: ext, data: data)
        } catch {
            // Silently fail — caching is best-effort
        }
    }

    // MARK: - Private

    private func audioPath(for fileId: String, ext: String) -> URL {
        let safeExt = ext.isEmpty ? "m4a" : ext
        return cacheDir.appendingPathComponent("\(fileId).\(safeExt)")
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([CachedEntry].self, from: data) else {
            manifest = []
            return
        }
        manifest = entries
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL)
    }

    // MARK: - Model

    private struct CachedEntry: Codable {
        let fileId: String
        let fileExtension: String
        let cachedAt: Date
    }
}
