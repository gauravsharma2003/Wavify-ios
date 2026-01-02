//
//  SongOptionsMenu.swift
//  Wavify
//
//  Created by Gaurav Sharma on 01/01/26.
//

import SwiftUI

struct SongOptionsMenu: View {
    var isLiked: Bool
    var onAddToPlaylist: () -> Void
    var onToggleLike: () -> Void
    
    var body: some View {
        Menu {
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
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
    }
}

#Preview {
    SongOptionsMenu(
        isLiked: false,
        onAddToPlaylist: {},
        onToggleLike: {}
    )
    .padding()
    .background(Color.black)
}
