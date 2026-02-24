//
//  CloudTrack.swift
//  Wavify
//
//  Google Drive audio file model
//

import Foundation
import SwiftData

@Model
final class CloudTrack {
    @Attribute(.unique) var id: String

    var title: String
    var artist: String?
    var duration: TimeInterval
    var format: String
    var fileSize: Int64

    var webContentLink: String
    var parentFolderId: String
    var thumbnailLink: String?
    var mimeType: String

    var playlistId: String?

    var dateAdded: Date

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    init(
        id: String,
        title: String,
        artist: String? = nil,
        duration: TimeInterval = 0,
        format: String,
        fileSize: Int64,
        webContentLink: String,
        parentFolderId: String,
        thumbnailLink: String? = nil,
        mimeType: String,
        playlistId: String? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.format = format
        self.fileSize = fileSize
        self.webContentLink = webContentLink
        self.parentFolderId = parentFolderId
        self.thumbnailLink = thumbnailLink
        self.mimeType = mimeType
        self.playlistId = playlistId
        self.dateAdded = dateAdded
    }
}
