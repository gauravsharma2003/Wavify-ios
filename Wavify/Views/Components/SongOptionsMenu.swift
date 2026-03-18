//
//  SongOptionsMenu.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI

struct SongOptionsMenu: View {
    var isLiked: Bool
    var isInQueue: Bool = false
    var isPlaying: Bool = false
    var onAddToPlaylist: () -> Void
    var onToggleLike: () -> Void
    var onPlayNext: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    var onSuggestToHost: (() -> Void)? = nil
    var iconSize: CGFloat = 16
    var frameSize: CGFloat = 24
    
    var body: some View {
        Menu {
            // Queue options first
            if let onPlayNext = onPlayNext {
                Button {
                    onPlayNext()
                } label: {
                    Label(isPlaying ? "Currently Playing" : "Play Next", systemImage: isPlaying ? "speaker.wave.2" : "text.line.first.and.arrowtriangle.forward")
                }
                .disabled(isPlaying)
            }
            
            if let onAddToQueue = onAddToQueue {
                Button {
                    onAddToQueue()
                } label: {
                    Label(isPlaying ? "Currently Playing" : (isInQueue ? "Already in Queue" : "Add to Queue"), 
                          systemImage: isPlaying ? "speaker.wave.2" : (isInQueue ? "checkmark" : "text.append"))
                }
                .disabled(isInQueue || isPlaying)
            }
            
            if let onSuggestToHost {
                Divider()

                Button {
                    onSuggestToHost()
                } label: {
                    Label("Suggest to Host", systemImage: "shareplay")
                }
            }

            Divider()

            Button {
                onAddToPlaylist()
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            
            Button {
                onToggleLike()
            } label: {
                Label(
                    isLiked ? "Remove from Liked" : "Add to Liked",
                    systemImage: isLiked ? "heart.slash" : "heart"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        }
    }
}

#Preview {
    SongOptionsMenu(
        isLiked: false,
        onAddToPlaylist: {},
        onToggleLike: {},
        onPlayNext: {},
        onAddToQueue: {}
    )
    .padding()
    .background(Color.black)
}

