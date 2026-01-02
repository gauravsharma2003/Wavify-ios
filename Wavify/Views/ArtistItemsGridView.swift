//
//  ArtistItemsGridView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI
import SwiftData

struct ArtistItemsGridView: View {
    let title: String
    let browseId: String
    let params: String?
    let artistName: String
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var items: [ArtistItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            
            if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                VStack {
                    Text("Failed to load \(title)")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadItems() }
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(items) { item in
                            // Reuse Navigation Link logic from ArtistDetailView or create new components
                            NavigationLink(destination: destinationView(for: item)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: URL(string: ImageUtils.thumbnailForCard(item.thumbnailUrl))) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 160, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        
                                        Text(item.subtitle ?? "")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(8)
                                .background(Color(white: 0.1).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if items.isEmpty {
                await loadItems()
            }
        }
    }
    
    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        
        do {
            self.items = try await networkManager.getSectionItems(browseId: browseId, params: params)
        } catch {
            print("Error loading \(title): \(error)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    @ViewBuilder
    private func destinationView(for item: ArtistItem) -> some View {
        if let browseId = item.browseId {
           // It's likely an album or single
           AlbumDetailView(
               albumId: browseId,
               initialName: item.title,
               initialArtist: artistName,
               initialThumbnail: item.thumbnailUrl,
               audioPlayer: audioPlayer
           )
        } else {
           EmptyView()
        }
    }
}
