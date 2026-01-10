//
//  SearchView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import Combine
import Observation

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State var navigationManager: NavigationManager = .shared
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.modelContext) private var modelContext
    
    // Add to playlist and liked status
    @State private var selectedSongForPlaylist: Song?
    @State private var likedSongIds: Set<String> = []
    
    var body: some View {
        NavigationStack(path: $navigationManager.searchPath) {
            ZStack {
                
                if viewModel.searchText.isEmpty && viewModel.results.isEmpty {
                    emptyStateView
                } else {
                    resultsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Songs, artists, albums..."
            )
            .searchSuggestions {
                if !viewModel.suggestions.isEmpty {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        switch suggestion {
                        case .text(let text):
                            Button {
                                viewModel.suggestions = []
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                dismissSearch()
                                viewModel.performSearchFromSuggestion(text: text)
                            } label: {
                                Label(text, systemImage: "magnifyingglass")
                            }
                            
                        case .result(let result):
                            Button {
                                viewModel.searchText = ""
                                dismissSearch()
                                handleSuggestionTap(result)
                            } label: {
                                HStack(spacing: 12) {
                                    CachedAsyncImagePhase(url: URL(string: result.thumbnailUrl)) { phase in
                                        if let image = phase.image {
                                            image.resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } else {
                                            Color(white: 0.15)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.system(size: 16))
                                            .foregroundStyle(.primary)
                                        Text(result.artist)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onSubmit(of: .search) {
                viewModel.performSearch()
            }
            .background(Color(white: 0.06).ignoresSafeArea())
            .overlay(alignment: .top) {
                // Gradient blur at top
                LinearGradient(
                    stops: [
                        .init(color: Color(white: 0.06).opacity(0.95), location: 0),
                        .init(color: Color(white: 0.06).opacity(0.7), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)
                .ignoresSafeArea()
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
                        audioPlayer: audioPlayer
                    )
                }
            }
        }
        .task {
            await viewModel.loadChipsIfNeeded()
        }
        .sheet(item: $selectedSongForPlaylist) { song in
            AddToPlaylistSheet(song: song)
        }
    }
    

    private var emptyStateView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.chips.isEmpty {
                    Text("Browse")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(viewModel.chips) { chip in
                            Button {
                                NavigationManager.shared.navigateToCategory(title: chip.title, endpoint: chip.endpoint)
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    // Random-ish gradient background based on title hash
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(hue: Double(abs(chip.title.hashValue) % 100) / 100.0, saturation: 0.7, brightness: 0.8),
                                                    Color(hue: Double(abs(chip.title.hashValue) % 100) / 100.0, saturation: 0.8, brightness: 0.4)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(height: 100)
                                    
                                    Text(chip.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Fallback if no chips
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("Search for music")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Find your favorite songs, artists, and albums")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .padding()
                }
            }
        }
    }
    
    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Filter Chips
                if viewModel.hasSearched {
                    filterChipsView
                }
                
                if viewModel.isSearching {
                    ProgressView()
                        .padding(.top, 50)
                } else {
                    // Top Results Section (only show when filter is All)
                    if viewModel.selectedFilter == .all && !viewModel.topResults.isEmpty {
                        topResultsSection
                    }
                    
                    // Songs Section
                    let songs = viewModel.results.filter { $0.type == .song }
                    if !songs.isEmpty {
                        sectionView(title: viewModel.selectedFilter == .songs ? nil : "Songs", results: viewModel.selectedFilter == .songs ? songs : Array(songs.prefix(5))) { result in
                            let song = Song(from: result)
                            SongRow(
                                song: song,
                                onTap: {
                                    Task {
                                        await audioPlayer.loadAndPlay(song: song)
                                    }
                                },
                                onLike: {
                                    toggleLikeSong(song)
                                },
                                showMenu: true,
                                onAddToPlaylist: {
                                    selectedSongForPlaylist = song
                                },
                                onPlayNext: {
                                    audioPlayer.playNextSong(song)
                                },
                                onAddToQueue: {
                                    _ = audioPlayer.addToQueue(song)
                                },
                                isInQueue: audioPlayer.isInQueue(song),
                                isCurrentlyPlaying: audioPlayer.currentSong?.id == song.id
                            )
                        }
                    }
                    
                    // Artists Section
                    let artists = viewModel.results.filter { $0.type == .artist }
                    if !artists.isEmpty && viewModel.selectedFilter != .songs && viewModel.selectedFilter != .albums {
                        if viewModel.selectedFilter == .artists {
                            sectionView(title: nil, results: artists) { result in
                                topResultRow(result)
                            }
                        } else {
                            artistSection(artists: Array(artists.prefix(4)))
                        }
                    }
                    
                    // Albums Section
                    let albums = viewModel.results.filter { $0.type == .album }
                    if !albums.isEmpty && viewModel.selectedFilter != .songs && viewModel.selectedFilter != .artists {
                        albumSection(albums: viewModel.selectedFilter == .albums ? albums : Array(albums.prefix(4)))
                    }
                    
                    // Playlists Section (only show when filter is All)
                    let playlists = viewModel.results.filter { $0.type == .playlist }
                    if !playlists.isEmpty && viewModel.selectedFilter == .all {
                        playlistSection(playlists: Array(playlists.prefix(4)))
                    }
                }
            }
            .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
        }
    }
    
    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.applyFilter(filter)
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.selectedFilter == filter ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(viewModel.selectedFilter == filter ? .white : Color.white.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
    
    private var topResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Results")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal)
                .padding(.top, 16)
            
            VStack(spacing: 0) {
                ForEach(Array(viewModel.topResults.prefix(4).enumerated()), id: \.element.id) { index, result in
                    topResultRow(result)
                    
                    if index < min(viewModel.topResults.count, 4) - 1 {
                        Divider()
                            .padding(.leading, 76)
                            .opacity(0.3)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func topResultRow(_ result: SearchResult) -> some View {
        Group {
            switch result.type {
            case .song:
                Button {
                    Task {
                        await audioPlayer.loadAndPlay(song: Song(from: result))
                    }
                } label: {
                    topResultRowContent(result)
                }
                .buttonStyle(.plain)
                
            case .artist:
                NavigationLink {
                    ArtistDetailView(
                        artistId: result.id,
                        initialName: result.name,
                        initialThumbnail: result.thumbnailUrl,
                        audioPlayer: audioPlayer
                    )
                } label: {
                    topResultRowContent(result)
                }
                .buttonStyle(.plain)
                
            case .album:
                NavigationLink {
                    AlbumDetailView(
                        albumId: result.id,
                        initialName: result.name,
                        initialArtist: result.artist,
                        initialThumbnail: result.thumbnailUrl,
                        audioPlayer: audioPlayer
                    )
                } label: {
                    topResultRowContent(result)
                }
                .buttonStyle(.plain)
            case .playlist:
                NavigationLink {
                    PlaylistDetailView(
                        playlistId: result.id,
                        initialName: result.name,
                        initialThumbnail: result.thumbnailUrl,
                        audioPlayer: audioPlayer
                    )
                } label: {
                    topResultRowContent(result)
                }
                .buttonStyle(.plain)
            case .video:
                Button {
                    Task {
                        await audioPlayer.loadAndPlay(song: Song(from: result))
                    }
                } label: {
                    topResultRowContent(result)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func topResultRowContent(_ result: SearchResult) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImagePhase(url: URL(string: result.thumbnailUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .overlay {
                            Image(systemName: iconForType(result.type))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(result.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if result.type == .song || result.type == .video {
                        // For songs/videos, show artist name directly
                        if !result.artist.isEmpty {
                            Text(result.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if result.type == .artist {
                        // For artists, just show type label
                        Text(labelForType(result.type))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        // For albums/playlists, show type and artist
                        Text(labelForType(result.type))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        if !result.artist.isEmpty {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(result.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer()
            
            if result.type == .song || result.type == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func iconForType(_ type: SearchResultType) -> String {
        switch type {
        case .song: return "music.note"
        case .artist: return "person.fill"
        case .album: return "music.note.list"
        case .playlist: return "music.note.list"
        case .video: return "play.rectangle.fill"
        }
    }
    
    private func labelForType(_ type: SearchResultType) -> String {
        switch type {
        case .song: return "Song"
        case .artist: return "Artist"
        case .album: return "Album"
        case .playlist: return "Playlist"
        case .video: return "Video"
        }
    }
    
    private func sectionView<Content: View>(
        title: String?,
        results: [SearchResult],
        @ViewBuilder content: @escaping (SearchResult) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.horizontal)
                    .padding(.top, 16)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    content(result)
                    
                    if index < results.count - 1 {
                        Divider()
                            .padding(.leading, 76)
                            .opacity(0.3)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func artistSection(artists: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artists")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal)
                .padding(.top, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(
                                artistId: artist.id,
                                initialName: artist.name,
                                initialThumbnail: artist.thumbnailUrl,
                                audioPlayer: audioPlayer
                            )
                        } label: {
                            VStack(spacing: 8) {
                                CachedAsyncImagePhase(url: URL(string: artist.thumbnailUrl)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    default:
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                                
                                Text(artist.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 100)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func albumSection(albums: [SearchResult], title: String = "Albums") -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal)
                .padding(.top, 20)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 16
            ) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(
                            albumId: album.id,
                            initialName: album.name,
                            initialArtist: album.artist,
                            initialThumbnail: album.thumbnailUrl,
                            audioPlayer: audioPlayer
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CachedAsyncImagePhase(url: URL(string: album.thumbnailUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    Rectangle()
                                        .fill(Color(white: 0.15))
                                        .overlay {
                                            Image(systemName: "music.note.list")
                                                .font(.system(size: 32))
                                                .foregroundStyle(.secondary)
                                        }
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Text(album.artist)
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
    
    private func playlistSection(playlists: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playlists")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal)
                .padding(.top, 20)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 16
            ) {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(
                            playlistId: playlist.id,
                            initialName: playlist.name,
                            initialThumbnail: playlist.thumbnailUrl,
                            audioPlayer: audioPlayer
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    CachedAsyncImagePhase(url: URL(string: playlist.thumbnailUrl)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        default:
                                            Rectangle()
                                                .fill(Color(white: 0.15))
                                                .overlay {
                                                    Image(systemName: "music.note.list")
                                                        .font(.system(size: 32))
                                                        .foregroundStyle(.secondary)
                                                }
                                        }
                                    }
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                Text(playlist.artist)
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
    
    private func handleSuggestionTap(_ result: SearchResult) {
        switch result.type {
        case .song:
            Task {
                await audioPlayer.loadAndPlay(song: Song(from: result))
            }
        case .artist:
            navigationManager.searchPath.append(NavigationDestination.artist(result.id, result.name, result.thumbnailUrl))
        case .album:
            navigationManager.searchPath.append(NavigationDestination.album(result.id, result.name, result.artist, result.thumbnailUrl))
        case .playlist:
            navigationManager.searchPath.append(NavigationDestination.playlist(result.id, result.name, result.thumbnailUrl))
        case .video:
             Task {
                 await audioPlayer.loadAndPlay(song: Song(from: result))
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


#Preview {
    SearchView(audioPlayer: AudioPlayer.shared)
        .preferredColorScheme(.dark)
}
