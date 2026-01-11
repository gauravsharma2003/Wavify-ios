//
//  RandomCategoryCarouselView.swift
//  Wavify
//
//  Horizontal carousel of playlists from a random category
//  Features snap-to-card scrolling with peek of adjacent cards
//

import SwiftUI

struct RandomCategoryCarouselView: View {
    let categoryName: String
    let playlists: [CategoryPlaylist]
    var audioPlayer: AudioPlayer
    let namespace: Namespace.ID
    let onPlaylistTap: (CategoryPlaylist) -> Void
    
    private let cardWidth: CGFloat = UIScreen.main.bounds.width * 0.85
    private let cardSpacing: CGFloat = 12
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                Text(categoryName)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Horizontal carousel with snap scrolling
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(playlists) { playlist in
                        CategoryPlaylistCard(
                            playlist: playlist,
                            categoryName: categoryName,
                            namespace: namespace,
                            onCardTap: {
                                onPlaylistTap(playlist)
                            },
                            onPlayTap: {
                                playPlaylist(playlist)
                            }
                        )
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, (UIScreen.main.bounds.width - cardWidth) / 2)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
    
    // MARK: - Playback Actions
    
    private func playPlaylist(_ playlist: CategoryPlaylist) {
        Task {
            do {
                var songModels: [Song] = []
                
                if playlist.isAlbum {
                    // Fetch album details for albums
                    let albumDetail = try await NetworkManager.shared.getAlbumDetails(albumId: playlist.playlistId)
                    songModels = albumDetail.songs.map { Song(from: $0, artist: albumDetail.artist, thumbnailUrl: albumDetail.albumThumbnail) }
                } else {
                    // Fetch songs from playlist
                    let playlistId = playlist.playlistId.hasPrefix("VL") 
                        ? String(playlist.playlistId.dropFirst(2)) 
                        : playlist.playlistId
                    
                    let songs = try await NetworkManager.shared.getQueueSongs(playlistId: playlistId)
                    songModels = songs.map { Song(from: $0) }
                }
                
                if !songModels.isEmpty {
                    await audioPlayer.playAlbum(songs: songModels, startIndex: 0, shuffle: false)
                }
            } catch {
                Logger.error("Failed to play \(playlist.isAlbum ? "album" : "playlist")", category: .playback, error: error)
            }
        }
    }
}
