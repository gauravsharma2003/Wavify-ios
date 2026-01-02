//
//  AddToPlaylistSheet.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI
import SwiftData

struct AddToPlaylistSheet: View {
    let song: Song
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalPlaylist.createdAt, order: .reverse) private var playlists: [LocalPlaylist]
    
    @State private var selectedPlaylistIds: Set<PersistentIdentifier> = []
    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if playlists.isEmpty {
                            emptyState
                        } else {
                            ForEach(playlists) { playlist in
                                PlaylistSelectionRow(
                                    playlist: playlist,
                                    isSelected: selectedPlaylistIds.contains(playlist.persistentModelID)
                                ) {
                                    toggleSelection(for: playlist)
                                }
                                
                                if playlist.id != playlists.last?.id {
                                    Divider()
                                        .padding(.leading, 72)
                                        .opacity(0.3)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                    .padding(.bottom, 80) // Space for floating button
                }
                
                // Floating Done Button
                Button {
                    saveSelections()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .zIndex(100)
            }
            .background(
                Color(white: 0.06)
                    .ignoresSafeArea()
            )
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadInitialSelections()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Playlists")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            
            Text("Create your first playlist")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            Button {
                showingCreatePlaylist = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Playlist")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Actions
    
    private func loadInitialSelections() {
        // Pre-select playlists that already contain this song
        selectedPlaylistIds = Set(playlists.filter { playlist in
            playlist.songs.contains { $0.videoId == song.videoId }
        }.map { $0.persistentModelID })
    }
    
    private func toggleSelection(for playlist: LocalPlaylist) {
        if selectedPlaylistIds.contains(playlist.persistentModelID) {
            selectedPlaylistIds.remove(playlist.persistentModelID)
        } else {
            selectedPlaylistIds.insert(playlist.persistentModelID)
        }
    }
    
    private func saveSelections() {
        let playlistManager = PlaylistManager.shared
        
        for playlist in playlists {
            let wasSelected = playlist.songs.contains { $0.videoId == song.videoId }
            let isSelected = selectedPlaylistIds.contains(playlist.persistentModelID)
            
            if isSelected && !wasSelected {
                // Add song to playlist
                playlistManager.addSong(song, to: playlist, in: modelContext)
            } else if !isSelected && wasSelected {
                // Remove song from playlist
                playlistManager.removeSong(song, from: playlist, in: modelContext)
            }
        }
    }
    
    private func createPlaylist() {
        guard !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let playlist = PlaylistManager.shared.createPlaylist(name: newPlaylistName, in: modelContext)
        // Auto-select the new playlist
        selectedPlaylistIds.insert(playlist.persistentModelID)
        newPlaylistName = ""
    }
}

// MARK: - Playlist Selection Row

struct PlaylistSelectionRow: View {
    let playlist: LocalPlaylist
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Playlist Artwork
                Group {
                    if let imageUrl = playlist.thumbnailUrl, !imageUrl.isEmpty {
                        AsyncImage(url: URL(string: imageUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                playlistPlaceholder
                            }
                        }
                    } else {
                        playlistPlaceholder
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Playlist Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text("\(playlist.songCount) songs")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var playlistPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
}

#Preview {
    AddToPlaylistSheet(
        song: Song(
            id: "1",
            title: "Test Song",
            artist: "Test Artist",
            thumbnailUrl: "",
            duration: "3:22",
            isLiked: false
        )
    )
    .preferredColorScheme(.dark)
}
