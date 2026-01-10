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
    @State private var likedSongIds: Set<String> = []
    
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
                            AlbumSongRow(
                                index: index + 1,
                                song: song,
                                isPlaying: audioPlayer.currentSong?.id == song.id,
                                isLiked: likedSongIds.contains(song.videoId),
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
        for song in songs {
            let videoId = song.videoId
            let descriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId && $0.isLiked == true }
            )
            if (try? modelContext.fetchCount(descriptor)) ?? 0 > 0 {
                likedSongIds.insert(song.videoId)
            }
        }
    }
    
    private func toggleLikeSong(_ song: Song) {
        let isNowLiked = PlaylistManager.shared.toggleLike(for: song, in: modelContext)
        if isNowLiked {
            likedSongIds.insert(song.videoId)
        } else {
            likedSongIds.remove(song.videoId)
        }
    }
}
