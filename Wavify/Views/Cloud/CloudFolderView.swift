//
//  CloudFolderView.swift
//  Wavify
//
//  Shows playlists inside a Google Drive folder connection
//

import SwiftUI

struct CloudFolderView: View {
    let connection: CloudConnection
    let audioPlayer: AudioPlayer

    @State private var cloudManager = CloudLibraryManager.shared

    private var playlists: [CloudPlaylist] {
        cloudManager.getPlaylists(for: connection.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if playlists.isEmpty && !cloudManager.isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No Playlists")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Sync this folder to discover audio files")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            Task { try? await cloudManager.syncFolder(connectionId: connection.id) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Sync Now")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if playlists.isEmpty && cloudManager.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        ForEach(playlists, id: \.id) { playlist in
                            NavigationLink {
                                CloudPlaylistView(playlist: playlist, audioPlayer: audioPlayer)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Playlist cover art
                                    ZStack {
                                        if let coverURL = playlist.cachedCoverURL {
                                            CachedAsyncImagePhase(url: coverURL) { phase in
                                                if let image = phase.image {
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                } else {
                                                    Rectangle().fill(.white.opacity(0.06))
                                                }
                                            }
                                        } else {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(.white.opacity(0.06))

                                            Image(systemName: "music.note.list")
                                                .font(.system(size: 28))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text("\(playlist.trackCount) tracks")
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

                if let error = cloudManager.syncError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.brandGradientTop, location: 0),
                    .init(color: Color.brandBackground, location: 0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color.brandGradientTop.opacity(0.95), location: 0),
                    .init(color: Color.brandGradientTop.opacity(0.7), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
        .navigationTitle(connection.folderName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { try? await cloudManager.syncFolder(connectionId: connection.id) }
                } label: {
                    if cloudManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(cloudManager.isLoading)
            }
        }
    }
}
