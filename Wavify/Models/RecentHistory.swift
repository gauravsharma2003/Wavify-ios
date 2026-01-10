//
//  RecentHistory.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import Foundation
import SwiftData

@Model
final class RecentHistory {
    var videoId: String
    var title: String
    var artist: String
    var thumbnailUrl: String
    var duration: String
    var playedAt: Date
    
    init(
        videoId: String,
        title: String,
        artist: String,
        thumbnailUrl: String,
        duration: String
    ) {
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.duration = duration
        self.playedAt = .now
    }
    
    // MARK: - Pagination Query
    
    /// Fetch recent history with pagination support
    static func fetchRecent(
        limit: Int = 50,
        offset: Int = 0,
        in context: ModelContext
    ) throws -> [RecentHistory] {
        var descriptor = FetchDescriptor<RecentHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try context.fetch(descriptor)
    }
    
    // MARK: - Cleanup
    
    static func cleanupOldEntries(in context: ModelContext, keepCount: Int = 200) {
        let descriptor = FetchDescriptor<RecentHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        
        do {
            let allHistory = try context.fetch(descriptor)
            if allHistory.count > keepCount {
                for item in allHistory.dropFirst(keepCount) {
                    context.delete(item)
                }
            }
        } catch {
            Logger.error("Failed to cleanup history", category: .data, error: error)
        }
    }
}
