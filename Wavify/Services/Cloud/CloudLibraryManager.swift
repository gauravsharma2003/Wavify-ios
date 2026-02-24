//
//  CloudLibraryManager.swift
//  Wavify
//
//  Coordinates Drive folder sync and SwiftData CRUD for cloud content
//

import Foundation
import SwiftData

@MainActor
@Observable
final class CloudLibraryManager {
    static let shared = CloudLibraryManager()

    var connections: [CloudConnection] = []
    var playlists: [CloudPlaylist] = []
    var tracks: [CloudTrack] = []
    var isLoading: Bool = false
    var syncError: String?

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private let authManager = CloudAuthManager.shared
    private var cachedAPIManager: CloudAPIManager?
    private var apiManager: CloudAPIManager {
        if let existing = cachedAPIManager { return existing }
        let manager = CloudAPIManager(authManager: authManager)
        cachedAPIManager = manager
        return manager
    }

    private init() {}

    // MARK: - Configuration

    func configure(with container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = container.mainContext
        Task { await loadAll() }
    }

    // MARK: - Public Methods

    func addDriveFolder(url: String, name: String? = nil) async throws {
        guard let ctx = modelContext else { throw CloudError.notConfigured }

        guard let folderInfo = CloudConnection.extractFolderInfo(from: url) else {
            throw CloudError.invalidURL
        }

        let folderId = folderInfo.folderId
        let resourceKey = folderInfo.resourceKey

        let existingConnections = try ctx.fetch(FetchDescriptor<CloudConnection>())
        if existingConnections.contains(where: { $0.folderId == folderId }) {
            throw CloudError.connectionExists
        }

        let folderName = name?.isEmpty == false ? name! : "Drive Folder"

        let connection = CloudConnection(
            folderId: folderId,
            folderName: folderName,
            folderURL: url,
            resourceKey: resourceKey,
            isDefault: connections.isEmpty
        )

        ctx.insert(connection)
        try ctx.save()

        await loadConnections()

        try await syncFolder(connectionId: connection.id)
    }

    func syncFolder(connectionId: UUID) async throws {
        guard let ctx = modelContext else { throw CloudError.notConfigured }

        guard let connection = connections.first(where: { $0.id == connectionId }) else {
            throw CloudError.connectionNotFound
        }

        isLoading = true
        syncError = nil

        do {
            try await scanFolderRecursively(
                folderId: connection.folderId,
                connectionId: connection.id.uuidString,
                parentPath: connection.folderName,
                level: 0,
                resourceKey: connection.resourceKey
            )

            connection.lastSynced = Date()
            try ctx.save()

            await loadPlaylists()
            await loadTracks()

            isLoading = false
        } catch {
            isLoading = false
            syncError = error.localizedDescription
            throw error
        }
    }

    func refreshAllConnections() async {
        for connection in connections {
            do {
                try await syncFolder(connectionId: connection.id)
            } catch {
                Logger.warning("Failed to sync \(connection.folderName): \(error)", category: .network)
            }
        }
    }

    func getPlaylists(for connectionId: UUID) -> [CloudPlaylist] {
        playlists.filter { $0.connectionId == connectionId.uuidString }
    }

    func playlistCount(for connectionId: UUID) -> Int {
        playlists.count(where: { $0.connectionId == connectionId.uuidString })
    }

    func getTracks(for playlistId: String) -> [CloudTrack] {
        tracks.filter { $0.playlistId == playlistId }
    }

    func deleteConnection(_ connection: CloudConnection) async {
        guard let ctx = modelContext else { return }

        let playlistsToDelete = playlists.filter { $0.connectionId == connection.id.uuidString }
        for playlist in playlistsToDelete {
            ctx.delete(playlist)
        }

        let playlistIds = Set(playlistsToDelete.map { $0.id })
        let tracksToDelete = tracks.filter { playlistIds.contains($0.playlistId ?? "") }
        for track in tracksToDelete {
            ctx.delete(track)
        }

        ctx.delete(connection)

        do { try ctx.save() } catch {
            Logger.warning("Failed to delete connection: \(error)", category: .network)
        }

        await loadAll()
    }

    // MARK: - Private Methods

    private func loadAll() async {
        await loadConnections()
        await loadPlaylists()
        await loadTracks()
    }

    private func loadConnections() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CloudConnection>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        do { connections = try ctx.fetch(descriptor) } catch {}
    }

    private func loadPlaylists() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CloudPlaylist>(
            sortBy: [SortDescriptor(\.level), SortDescriptor(\.name)]
        )
        do { playlists = try ctx.fetch(descriptor) } catch {}
    }

    private func loadTracks() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CloudTrack>(
            sortBy: [SortDescriptor(\.title)]
        )
        do { tracks = try ctx.fetch(descriptor) } catch {}
    }

    private func scanFolderRecursively(
        folderId: String,
        connectionId: String,
        parentPath: String,
        level: Int,
        resourceKey: String?
    ) async throws {
        guard let ctx = modelContext else { throw CloudError.notConfigured }

        let files = try await apiManager.listFilesRecursively(in: folderId, resourceKey: resourceKey)

        var audioFiles: [CloudAPIManager.DriveFile] = []
        var subfolders: [CloudAPIManager.DriveFile] = []
        var coverImageFile: CloudAPIManager.DriveFile?

        for file in files {
            if file.isFolder {
                subfolders.append(file)
            } else if file.isAudioFile {
                audioFiles.append(file)
            } else if file.name == "Folder.jpg" {
                coverImageFile = file
            }
        }

        if !audioFiles.isEmpty {
            let existingPlaylist = try? ctx.fetch(
                FetchDescriptor<CloudPlaylist>(
                    predicate: #Predicate { $0.id == folderId }
                )
            ).first

            if let playlist = existingPlaylist {
                playlist.trackCount = audioFiles.count
                playlist.lastSynced = Date()
                if let cover = coverImageFile {
                    playlist.coverImageFileId = cover.id
                }
            } else {
                let playlist = CloudPlaylist(
                    id: folderId,
                    name: parentPath.components(separatedBy: " / ").last ?? parentPath,
                    trackCount: audioFiles.count,
                    level: level,
                    fullPath: parentPath,
                    connectionId: connectionId,
                    coverImageFileId: coverImageFile?.id,
                    lastSynced: Date()
                )
                ctx.insert(playlist)
            }

            // Download and cache Folder.jpg if present
            if let cover = coverImageFile {
                await downloadAndCacheCover(fileId: cover.id, playlistId: folderId)
            }

            for audioFile in audioFiles {
                let existingTrack = try? ctx.fetch(
                    FetchDescriptor<CloudTrack>(
                        predicate: #Predicate { $0.id == audioFile.id }
                    )
                ).first

                if existingTrack == nil {
                    let track = CloudTrack(
                        id: audioFile.id,
                        title: audioFile.name,
                        format: audioFile.fileExtension,
                        fileSize: audioFile.sizeInBytes,
                        webContentLink: audioFile.webContentLink ?? "",
                        parentFolderId: folderId,
                        thumbnailLink: audioFile.thumbnailLink,
                        mimeType: audioFile.mimeType ?? "audio/unknown",
                        playlistId: folderId
                    )
                    ctx.insert(track)
                }
            }

            try ctx.save()
        }

        for subfolder in subfolders {
            let subPath = "\(parentPath) / \(subfolder.name)"
            try await scanFolderRecursively(
                folderId: subfolder.id,
                connectionId: connectionId,
                parentPath: subPath,
                level: level + 1,
                resourceKey: resourceKey
            )
        }
    }

    /// Download a cover image from Drive and cache it locally
    private func downloadAndCacheCover(fileId: String, playlistId: String) async {
        let cachePath = CloudPlaylist.coverCachePath(for: playlistId)

        // Skip if already cached
        if FileManager.default.fileExists(atPath: cachePath.path) { return }

        do {
            let data = try await apiManager.downloadFileData(fileId: fileId)
            try data.write(to: cachePath)
        } catch {
            Logger.warning("Failed to download cover for \(playlistId): \(error)", category: .network)
        }
    }

    /// Get the local cover image URL string for a playlist (for use in Song.thumbnailUrl)
    func coverURLString(for playlistId: String) -> String {
        let path = CloudPlaylist.coverCachePath(for: playlistId)
        if FileManager.default.fileExists(atPath: path.path) {
            return path.absoluteString
        }
        return ""
    }

    /// Get the file extension for a cloud track (e.g. "flac", "mp3", "m4a")
    func trackFileExtension(for fileId: String) -> String {
        tracks.first(where: { $0.id == fileId })?.format ?? "m4a"
    }

    /// Update a cloud track's duration after it becomes known from playback
    func updateTrackDuration(fileId: String, duration: TimeInterval) {
        guard let ctx = modelContext else { return }
        guard let track = tracks.first(where: { $0.id == fileId }), track.duration == 0 else { return }
        track.duration = duration
        try? ctx.save()
    }

    // MARK: - Error Types

    enum CloudError: LocalizedError {
        case notConfigured
        case invalidURL
        case connectionExists
        case connectionNotFound
        case authenticationRequired

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Cloud library not configured"
            case .invalidURL: return "Invalid Google Drive folder URL"
            case .connectionExists: return "This Drive folder is already connected"
            case .connectionNotFound: return "Drive connection not found"
            case .authenticationRequired: return "Please sign in to Google Drive first"
            }
        }
    }
}
