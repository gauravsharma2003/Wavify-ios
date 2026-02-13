//
//  LikedSongsStore.swift
//  Wavify
//
//  Single source of truth for liked song state across all views.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class LikedSongsStore {
    static let shared = LikedSongsStore()

    private(set) var likedSongIds: Set<String> = []
    private var isLoaded = false

    private init() {}

    func loadIfNeeded(context: ModelContext) {
        guard !isLoaded else { return }
        load(context: context)
    }

    func load(context: ModelContext) {
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.isLiked == true }
        )
        let songs = (try? context.fetch(descriptor)) ?? []
        likedSongIds = Set(songs.map(\.videoId))
        isLoaded = true
    }

    func isLiked(_ videoId: String) -> Bool {
        likedSongIds.contains(videoId)
    }

    @discardableResult
    func toggleLike(for song: Song, in context: ModelContext) -> Bool {
        let videoId = song.videoId
        let descriptor = FetchDescriptor<LocalSong>(
            predicate: #Predicate { $0.videoId == videoId }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.isLiked.toggle()
            try? context.save()
            if existing.isLiked {
                likedSongIds.insert(videoId)
            } else {
                likedSongIds.remove(videoId)
            }
            return existing.isLiked
        } else {
            let newSong = LocalSong(
                videoId: song.videoId,
                title: song.title,
                artist: song.artist,
                thumbnailUrl: song.thumbnailUrl,
                duration: song.duration,
                isLiked: true
            )
            context.insert(newSong)
            try? context.save()
            likedSongIds.insert(videoId)
            return true
        }
    }

    /// For LibraryView which works with LocalSong directly
    func toggleLike(localSong: LocalSong, in context: ModelContext) {
        localSong.isLiked.toggle()
        try? context.save()
        if localSong.isLiked {
            likedSongIds.insert(localSong.videoId)
        } else {
            likedSongIds.remove(localSong.videoId)
        }
    }
}
