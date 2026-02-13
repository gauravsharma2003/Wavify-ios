//
//  ArtistTopSongsView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI
import SwiftData

struct ArtistTopSongsView: View {
    let browseId: String
    let artistName: String
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // Add to playlist state
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongsStore = LikedSongsStore.shared
    
    private let networkManager = NetworkManager.shared
    
    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            
            if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                VStack {
                    Text("Failed to load songs")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadSongs() }
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SwipeUpNextRow(
                                onPlayNext: {
                                    audioPlayer.playNextSong(song)
                                }
                            ) {
                                AlbumSongRow(
                                    index: index + 1,
                                    song: song,
                                    isPlaying: audioPlayer.currentSong?.id == song.id,
                                    isLiked: likedSongsStore.likedSongIds.contains(song.videoId),
                                    showImage: true,
                                    onTap: {
                                        playSong(song)
                                    },
                                    onAddToPlaylist: {
                                        selectedSongForPlaylist = song
                                    },
                                    onToggleLike: {
                                        toggleLikeSong(song)
                                    }
                                )
                            }

                            if index < songs.count - 1 {
                                Divider()
                                    .padding(.leading, 72) // Increased padding for image
                                    .opacity(0.3)
                            }
                        }
                    }
                    .padding(.vertical)
                    .padding(.horizontal) // Create side padding
                    // Bottom padding for player bar
                    .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 20)
                }
            }
        }
        .navigationTitle("Top Songs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if songs.isEmpty {
                await loadSongs()
            }
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
    }
    
    private func loadSongs() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Use the generic browse method which handles playlists/sections
            // Top params usually return a PlaylistShelf which our browse parses into sections
            let page = try await networkManager.getPlaylist(id: browseId)
            
            // Extract songs from the first section (usually the playlist shelf)
            if let section = page.sections.first {
                self.songs = section.items.compactMap { item in
                    guard let videoId = item.id.count > 0 ? item.id : nil else { return nil }
                    return Song(
                        id: videoId,
                        title: item.name,
                        artist: item.artist.isEmpty ? artistName : item.artist,
                        thumbnailUrl: item.thumbnailUrl,
                        duration: "" // Duration might not be available in simple SearchResult
                    )
                }
                loadLikedStatus()
            } else {
                errorMessage = "No songs found"
            }
            
        } catch {
            Logger.networkError("Error loading top songs", error: error)
            errorMessage = error.localizedDescription
        
        }
        isLoading = false
    }
    
    private func playSong(_ song: Song) {
        Task {
            // Play this song and queue the rest
            // Find index
            if let index = songs.firstIndex(where: { $0.id == song.id }) {
                await audioPlayer.playAlbum(songs: songs, startIndex: index, shuffle: false)
            }
        }
    }
    
    private func loadLikedStatus() {
        likedSongsStore.loadIfNeeded(context: modelContext)
    }

    private func toggleLikeSong(_ song: Song) {
        likedSongsStore.toggleLike(for: song, in: modelContext)
    }
}

// MARK: - Swipe Up Next Row

private struct SwipeUpNextRow<Content: View>: View {
    let onPlayNext: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var passedThreshold = false

    private let threshold: CGFloat = 80

    var body: some View {
        ZStack {
            // Right background (swipe left ← green: Up Next)
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "text.insert")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Up Next")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.trailing, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green)
            .opacity(offset < 0 ? 1 : 0)

            // Row content
            content
                .background(Color(white: 0.05))
                .offset(x: min(offset, 0)) // Only allow left swipe
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if !isDragging {
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        guard horizontal > vertical, value.translation.width < 0 else { return }
                        isDragging = true
                    }
                    guard isDragging else { return }

                    offset = min(value.translation.width, 0)

                    let isPastThreshold = abs(offset) >= threshold
                    if isPastThreshold && !passedThreshold {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        passedThreshold = true
                    } else if !isPastThreshold && passedThreshold {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        passedThreshold = false
                    }
                }
                .onEnded { value in
                    guard isDragging else {
                        isDragging = false
                        return
                    }

                    if value.translation.width < -threshold {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = -UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onPlayNext()
                            offset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            offset = 0
                        }
                    }

                    isDragging = false
                    passedThreshold = false
                }
        )
    }
}
