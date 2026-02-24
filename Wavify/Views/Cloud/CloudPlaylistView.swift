//
//  CloudPlaylistView.swift
//  Wavify
//
//  Full-screen playlist view for a Drive folder's audio files
//  Mirrors AlbumDetailView layout (header, title, Play/Shuffle, AlbumSongRow)
//

import SwiftUI
import SwiftData

struct CloudPlaylistView: View {
    let playlist: CloudPlaylist
    let audioPlayer: AudioPlayer

    @State private var cloudManager = CloudLibraryManager.shared
    @State private var likedSongsStore = LikedSongsStore.shared
    @Environment(\.modelContext) private var modelContext

    @State private var gradientColors: [Color] = [Color(white: 0.12), Color(white: 0.06)]
    @State private var selectedSongForPlaylist: Song?

    private var tracks: [CloudTrack] {
        cloudManager.getTracks(for: playlist.id)
    }

    private var songs: [Song] {
        tracks.map { makeSong(from: $0) }
    }

    private var coverURL: URL? {
        playlist.cachedCoverURL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header (matches AlbumDetailView header)
                headerView

                // Content
                VStack(spacing: 20) {
                    albumInfo

                    if !songs.isEmpty {
                        actionButtons
                        songList
                    } else {
                        emptyState
                    }
                }
                .padding(.bottom, audioPlayer.currentSong != nil ? 100 : 40)
                .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height - 420, alignment: .top)
                .background(
                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                        .padding(.top, -2)
                )
            }
        }
        .background((gradientColors.last ?? Color(white: 0.05)).ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            likedSongsStore.loadIfNeeded(context: modelContext)
            await extractColors()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .global).minY
            let height = max(420, 420 + (minY > 0 ? minY : 0))
            let offset = minY > 0 ? -minY : 0

            if let coverURL = coverURL {
                CachedAsyncImagePhase(url: coverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width * 1.1, height: height)
                            .frame(width: geometry.size.width, height: height)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.4),
                                        .init(color: (gradientColors.first ?? .black).opacity(0.3), location: 0.6),
                                        .init(color: (gradientColors.first ?? .black).opacity(0.7), location: 0.8),
                                        .init(color: gradientColors.first ?? .black, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        Rectangle()
                            .fill(gradientColors.first ?? Color(white: 0.1))
                    }
                }
                .offset(y: offset)
            } else {
                ZStack {
                    Rectangle()
                        .fill(gradientColors.first ?? Color(white: 0.12))

                    Image(systemName: "music.note.list")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(width: geometry.size.width, height: height)
                .clipped()
                .offset(y: offset)
            }
        }
        .frame(height: 420)
    }

    private var albumInfo: some View {
        VStack(spacing: 6) {
            Text(playlist.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(tracks.count) tracks")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - Action Buttons (matches AlbumDetailView — no Save button)

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Play Button
            Button {
                Task { await playCloudPlaylist(startIndex: 0, shuffle: false) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 40)

            // Shuffle Button (full width, no Save)
            Button {
                Task { await playCloudPlaylist(startIndex: 0, shuffle: true) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .medium))
                    Text("Shuffle")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Song List (uses AlbumSongRow like AlbumDetailView)

    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumSongRow(
                    index: index + 1,
                    song: song,
                    isPlaying: audioPlayer.currentSong?.id == song.id,
                    isLiked: likedSongsStore.likedSongIds.contains(song.videoId),
                    isInQueue: audioPlayer.isInQueue(song),
                    onTap: {
                        Task {
                            await playCloudTrack(tracks[index], at: index)
                        }
                    },
                    onAddToPlaylist: {
                        selectedSongForPlaylist = song
                    },
                    onToggleLike: {
                        likedSongsStore.toggleLike(for: song, in: modelContext)
                    },
                    onPlayNext: {
                        audioPlayer.playNextSong(song)
                    },
                    onAddToQueue: {
                        _ = audioPlayer.addToQueue(song)
                    }
                )

                if index < songs.count - 1 {
                    Divider()
                        .padding(.leading, 50)
                        .opacity(0.3)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))

            Text("No tracks found")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            Text("This folder has no audio files")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 200)
    }

    // MARK: - Helpers

    private func makeSong(from track: CloudTrack) -> Song {
        // Use Folder.jpg cover as thumbnail for all tracks in this playlist
        let thumbnail = coverURL?.absoluteString ?? track.thumbnailLink ?? ""
        // Only show duration if we've learned it from a previous play
        let durationStr = track.duration > 0 ? track.formattedDuration : ""
        return Song(
            id: "cloud_\(track.id)",
            title: track.title,
            artist: track.artist ?? "Unknown Artist",
            thumbnailUrl: thumbnail,
            duration: durationStr
        )
    }

    private func extractColors() async {
        guard let coverURL = coverURL,
              let data = try? Data(contentsOf: coverURL),
              let uiImage = UIImage(data: data) else { return }

        let colors = await ColorExtractor.extractColors(from: uiImage)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                gradientColors = [colors.0, colors.1, Color(white: 0.06)]
            }
        }
    }

    private func playCloudTrack(_ track: CloudTrack, at index: Int) async {
        let song = makeSong(from: track)
        await audioPlayer.loadAndPlayCloudTrack(
            song: song,
            queueSongs: songs,
            startIndex: index
        )
    }

    private func playCloudPlaylist(startIndex: Int, shuffle: Bool) async {
        if shuffle {
            var shuffledSongs = songs
            shuffledSongs.shuffle()
            await audioPlayer.loadAndPlayCloudTrack(
                song: shuffledSongs[0],
                queueSongs: shuffledSongs,
                startIndex: 0
            )
        } else {
            await audioPlayer.loadAndPlayCloudTrack(
                song: songs[startIndex],
                queueSongs: songs,
                startIndex: startIndex
            )
        }
    }
}
