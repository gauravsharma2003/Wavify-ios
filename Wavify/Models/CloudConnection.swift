//
//  CloudConnection.swift
//  Wavify
//
//  Google Drive folder connection model
//

import Foundation
import SwiftData

@Model
final class CloudConnection {
    @Attribute(.unique) var id: UUID

    var folderId: String
    var folderName: String
    var folderURL: String
    var resourceKey: String?

    var isDefault: Bool

    var dateAdded: Date
    var lastSynced: Date?

    static func extractFolderInfo(from url: String) -> (folderId: String, resourceKey: String?)? {
        var folderId: String?
        var resourceKey: String?

        if let range = url.range(of: "folders/") {
            let afterFolders = String(url[range.upperBound...])
            if let questionMark = afterFolders.firstIndex(of: "?") {
                folderId = String(afterFolders[..<questionMark])
            } else if let ampersand = afterFolders.firstIndex(of: "&") {
                folderId = String(afterFolders[..<ampersand])
            } else {
                folderId = afterFolders
            }
        }

        if let range = url.range(of: "resourcekey=") {
            let afterKey = String(url[range.upperBound...])
            if let ampersand = afterKey.firstIndex(of: "&") {
                resourceKey = String(afterKey[..<ampersand])
            } else {
                resourceKey = afterKey
            }
        }

        guard let id = folderId else { return nil }
        return (id, resourceKey)
    }

    init(
        id: UUID = UUID(),
        folderId: String,
        folderName: String,
        folderURL: String,
        resourceKey: String? = nil,
        isDefault: Bool = false,
        dateAdded: Date = Date(),
        lastSynced: Date? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.folderName = folderName
        self.folderURL = folderURL
        self.resourceKey = resourceKey
        self.isDefault = isDefault
        self.dateAdded = dateAdded
        self.lastSynced = lastSynced
    }
}
