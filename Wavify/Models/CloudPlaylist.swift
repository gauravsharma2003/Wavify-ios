//
//  CloudPlaylist.swift
//  Wavify
//
//  Google Drive folder-based playlist model
//

import Foundation
import SwiftData

@Model
final class CloudPlaylist: Identifiable {
    @Attribute(.unique) var id: String

    var name: String
    var trackCount: Int

    var parentFolderId: String?
    var level: Int
    var fullPath: String

    var webViewLink: String?

    var connectionId: String

    /// Drive file ID of `Folder.jpg` in this folder (used as cover art)
    var coverImageFileId: String?

    var dateCreated: Date
    var lastSynced: Date?

    /// Local file URL for the cached cover image
    var cachedCoverURL: URL? {
        guard coverImageFileId != nil else { return nil }
        let path = Self.coverCachePath(for: id)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Returns the local cache file path for a given playlist ID
    static func coverCachePath(for playlistId: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CloudCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(playlistId).jpg")
    }

    init(
        id: String,
        name: String,
        trackCount: Int = 0,
        parentFolderId: String? = nil,
        level: Int = 0,
        fullPath: String,
        webViewLink: String? = nil,
        connectionId: String,
        coverImageFileId: String? = nil,
        dateCreated: Date = Date(),
        lastSynced: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.trackCount = trackCount
        self.parentFolderId = parentFolderId
        self.level = level
        self.fullPath = fullPath
        self.webViewLink = webViewLink
        self.connectionId = connectionId
        self.coverImageFileId = coverImageFileId
        self.dateCreated = dateCreated
        self.lastSynced = lastSynced
    }
}
