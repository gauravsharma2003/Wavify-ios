//
//  LibraryView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalSong.addedAt, order: .reverse) private var likedSongs: [LocalSong]
    @Query(sort: \LocalPlaylist.createdAt, order: .reverse) private var playlists: [LocalPlaylist]
    @Query(sort: \RecentHistory.playedAt, order: .reverse) private var history: [RecentHistory]
    
    var audioPlayer: AudioPlayer
    @State var navigationManager: NavigationManager = .shared
    @State private var sharePlayManager = SharePlayManager.shared
    @State private var selectedSection: LibrarySection = .playlists
    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    
    // Hero animation namespace for library
    @Namespace private var libraryHeroAnimation
    

    
    enum LibrarySection: String, CaseIterable {
        case playlists = "Playlists"
        case liked = "Liked"
        case history = "History"
    }
    
    var body: some View {
        NavigationStack(path: $navigationManager.libraryPath) {
            ScrollView {
                VStack(spacing: 20) {
                    // Listen Together
                    NavigationLink(destination: ListenTogetherView()) {
                        HStack(spacing: 14) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.cyan)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Listen Together")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(sharePlayManager.isSessionActive
                                     ? "\(sharePlayManager.participantCount) listening"
                                     : "Listen with friends")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if sharePlayManager.isSessionActive {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.06))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    // Section Picker
                    Picker("Section", selection: $selectedSection) {
                        ForEach(LibrarySection.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Content based on selection
                    switch selectedSection {
                    case .playlists:
                        playlistsSection
                    case .liked:
                        likedSection
                    case .history:
                        historySection
                    }
                }
                .padding(.vertical)
                .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
            }
            .background(gradientBackground)
            .overlay(alignment: .top) {
                // Gradient blur at top
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "1A1A1A").opacity(0.95), location: 0),
                        .init(color: Color(hex: "1A1A1A").opacity(0.7), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if selectedSection == .playlists {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCreatePlaylist = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("New Playlist", isPresented: $showingCreatePlaylist) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    createPlaylist()
                }
                Button("Cancel", role: .cancel) {
                    newPlaylistName = ""
                }
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .artist(let id, let name, let thumbnail):
                    ArtistDetailView(
                        artistId: id,
                        initialName: name,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .album(let id, let name, let artist, let thumbnail):
                    AlbumDetailView(
                        albumId: id,
                        initialName: name,
                        initialArtist: artist,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .song(_):
                    EmptyView()
                case .playlist(let id, let name, let thumbnail):
                    PlaylistDetailView(
                        playlistId: id,
                        initialName: name,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .category(let title, let endpoint):
                    CategoryDetailView(
                        title: title,
                        endpoint: endpoint,
                        namespace: libraryHeroAnimation,
                        audioPlayer: audioPlayer
                    )
                case .localPlaylist(let pID):
                     if let playlist = modelContext.model(for: pID) as? LocalPlaylist {
                         AlbumDetailView(
                             albumId: nil,
                             initialName: playlist.name,
                             initialArtist: "",
                             initialThumbnail: playlist.thumbnailUrl ?? "",
                             localPlaylist: playlist,
                             audioPlayer: audioPlayer
                         )
                     } else {
                         ContentUnavailableView("Playlist Not Found", systemImage: "questionmark.folder")
                     }
                case .listenTogether:
                    ListenTogetherView()
                }
            }
        }
    }
    
    private var gradientBackground: some View {
        Color(hex: "1A1A1A")
            .ignoresSafeArea()
    }
    
    // MARK: - Playlists Section
    
    private var playlistsSection: some View {
        VStack(spacing: 12) {
            if playlists.isEmpty {
                emptyState(
                    icon: "music.note.list",
                    title: "No Playlists",
                    message: "Create your first playlist"
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            if let albumId = playlist.albumId, !albumId.isEmpty, playlist.songs.isEmpty {
                                // This is a saved public playlist without local songs, use PlaylistDetailView to reload
                                PlaylistDetailView(
                                    playlistId: albumId,
                                    initialName: playlist.name,
                                    initialThumbnail: playlist.thumbnailUrl ?? "",
                                    audioPlayer: audioPlayer
                                )
                            } else {
                                // This is a playlist with local songs (either locally created or saved from public), use AlbumDetailView
                                AlbumDetailView(
                                    albumId: nil,
                                    initialName: playlist.name,
                                    initialArtist: "",
                                    initialThumbnail: playlist.thumbnailUrl ?? "",
                                    localPlaylist: playlist,
                                    audioPlayer: audioPlayer
                                )
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                // Playlist Art
                                PlaylistCoverImage(thumbnails: playlist.coverThumbnails)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    Text("\(playlist.songCount) songs")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Liked Section
    
    private var likedSection: some View {
        VStack(spacing: 16) {
            let likedOnly = likedSongs.filter { $0.isLiked }
            
            if likedOnly.isEmpty {
                emptyState(
                    icon: "heart",
                    title: "No Liked Songs",
                    message: "Songs you like will appear here"
                )
            } else {
                // Play & Shuffle Buttons
                HStack(spacing: 16) {
                    // Play Button
                    Button {
                        if let firstSong = likedOnly.first {
                            Task {
                                let songs = likedOnly.map { Song(from: $0) }
                                await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: false)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Play")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    
                    // Shuffle Button
                    Button {
                        Task {
                            let songs = likedOnly.map { Song(from: $0) }
                            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .medium))
                            Text("Shuffle")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal)
                
                VStack(spacing: 0) {
                    ForEach(likedOnly) { localSong in
                        SongRow(
                            song: Song(from: localSong),
                            onTap: {
                                Task {
                                    await audioPlayer.loadAndPlay(song: Song(from: localSong))
                                }
                            },
                            onLike: {
                                toggleLike(localSong)
                            }
                        )
                        
                        if localSong.videoId != likedOnly.last?.videoId {
                            Divider()
                                .padding(.leading, 76)
                                .opacity(0.3)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        VStack(spacing: 16) {
            if history.isEmpty {
                emptyState(
                    icon: "clock",
                    title: "No History",
                    message: "Recently played songs will appear here"
                )
            } else {
                // Play & Shuffle Buttons
                HStack(spacing: 16) {
                    // Play Button
                    Button {
                        if let firstSong = history.first {
                            Task {
                                let songs = history.map { Song(from: $0) }
                                await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: false)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Play")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    
                    // Shuffle Button
                    Button {
                        Task {
                            let songs = history.map { Song(from: $0) }
                            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .medium))
                            Text("Shuffle")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal)
                
                VStack(spacing: 0) {
                    ForEach(history) { item in
                        SongRow(
                            song: Song(from: item),
                            onTap: {
                                Task {
                                    await audioPlayer.loadAndPlay(song: Song(from: item))
                                }
                            }
                        )
                        
                        if item.videoId != history.last?.videoId {
                            Divider()
                                .padding(.leading, 76)
                                .opacity(0.3)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Actions
    
    private func createPlaylist() {
        guard !newPlaylistName.isEmpty else { return }
        
        let playlist = LocalPlaylist(name: newPlaylistName)
        modelContext.insert(playlist)
        newPlaylistName = ""
    }
    
    private func deletePlaylists(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(playlists[index])
        }
    }
    
    private func toggleLike(_ song: LocalSong) {
        song.isLiked.toggle()
    }
}


#Preview {
    LibraryView(audioPlayer: AudioPlayer.shared)
        .preferredColorScheme(.dark)
        .modelContainer(for: [LocalSong.self, LocalPlaylist.self, RecentHistory.self], inMemory: true)
}
