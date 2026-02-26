//
//  CloudAPIManager.swift
//  Wavify
//
//  Google Drive REST API v3 wrapper
//

import Foundation

final class CloudAPIManager {

    private let authManager: CloudAuthManager
    private let baseURL = "https://www.googleapis.com/drive/v3"

    init(authManager: CloudAuthManager) {
        self.authManager = authManager
    }

    // MARK: - File Operations

    func listFiles(in folderId: String, pageToken: String? = nil, resourceKey: String? = nil) async throws -> FileListResponse {
        let token = try await authManager.getAccessToken()

        var components = URLComponents(string: "\(baseURL)/files")!
        var queryItems = [
            URLQueryItem(name: "q", value: "'\(folderId)' in parents and trashed=false"),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,webContentLink,webViewLink,thumbnailLink,parents)"),
            URLQueryItem(name: "pageSize", value: "1000"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
        ]

        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.requestFailed(statusCode: -1, message: "Failed to build request URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        if let resourceKey = resourceKey {
            let resourceKeyHeader = "\(folderId)/\(resourceKey)"
            request.setValue(resourceKeyHeader, forHTTPHeaderField: "X-Goog-Drive-Resource-Keys")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.requestFailed(statusCode: code, message: Self.parseErrorMessage(from: data, statusCode: code))
        }

        return try JSONDecoder().decode(FileListResponse.self, from: data)
    }

    func getFileMetadata(fileId: String) async throws -> DriveFile {
        let token = try await authManager.getAccessToken()

        var components = URLComponents(string: "\(baseURL)/files/\(fileId)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size,webContentLink,webViewLink,thumbnailLink,parents")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.requestFailed(statusCode: code, message: Self.parseErrorMessage(from: data, statusCode: code))
        }

        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    func listFilesRecursively(in folderId: String, resourceKey: String? = nil) async throws -> [DriveFile] {
        var allFiles: [DriveFile] = []
        var pageToken: String?

        repeat {
            let response = try await listFiles(in: folderId, pageToken: pageToken, resourceKey: resourceKey)
            allFiles.append(contentsOf: response.files)
            pageToken = response.nextPageToken
        } while pageToken != nil

        return allFiles
    }

    func searchAudioFiles(in folderId: String) async throws -> [DriveFile] {
        let allFiles = try await listFilesRecursively(in: folderId)

        let audioMimeTypes: Set<String> = [
            "audio/flac", "audio/x-flac",
            "audio/wav", "audio/x-wav", "audio/wave",
            "audio/mpeg", "audio/mp3",
            "audio/mp4", "audio/m4a",
            "audio/aac",
            "audio/ogg", "audio/opus"
        ]

        return allFiles.filter { file in
            audioMimeTypes.contains(file.mimeType?.lowercased() ?? "") || file.isAudioFileByExtension
        }
    }

    func getFolders(in folderId: String) async throws -> [DriveFile] {
        let allFiles = try await listFilesRecursively(in: folderId)
        return allFiles.filter { $0.mimeType == "application/vnd.google-apps.folder" }
    }

    /// Download a file's raw content (used for cover images)
    func downloadFileData(fileId: String) async throws -> Data {
        let token = try await authManager.getAccessToken()

        guard let url = URL(string: "\(baseURL)/files/\(fileId)?alt=media") else {
            throw APIError.requestFailed(statusCode: -1, message: "Failed to build download URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.requestFailed(statusCode: code, message: Self.parseErrorMessage(from: data, statusCode: code))
        }

        return data
    }

    // MARK: - Error Types

    enum APIError: LocalizedError {
        case requestFailed(statusCode: Int, message: String)
        case invalidResponse
        case rateLimitExceeded

        var errorDescription: String? {
            switch self {
            case .requestFailed(let code, let message):
                return "Drive API error \(code): \(message)"
            case .invalidResponse: return "Received invalid response from Google Drive"
            case .rateLimitExceeded: return "Rate limit exceeded. Please try again later."
            }
        }
    }

    private static func parseErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "HTTP \(statusCode)"
    }

    // MARK: - Response Models

    struct FileListResponse: Codable {
        let files: [DriveFile]
        let nextPageToken: String?
    }

    struct DriveFile: Codable {
        let id: String
        let name: String
        let mimeType: String?
        let size: String?
        let webContentLink: String?
        let webViewLink: String?
        let thumbnailLink: String?
        let parents: [String]?

        var sizeInBytes: Int64 {
            Int64(size ?? "0") ?? 0
        }

        var isFolder: Bool {
            mimeType == "application/vnd.google-apps.folder"
        }

        var isAudioFile: Bool {
            guard let mimeType = mimeType else { return false }
            return mimeType.hasPrefix("audio/") || isAudioFileByExtension
        }

        var isAudioFileByExtension: Bool {
            let audioExtensions = [".flac", ".wav", ".mp3", ".m4a", ".aac", ".ogg", ".opus"]
            return audioExtensions.contains { name.lowercased().hasSuffix($0) }
        }

        var fileExtension: String {
            (name as NSString).pathExtension.lowercased()
        }
    }
}
