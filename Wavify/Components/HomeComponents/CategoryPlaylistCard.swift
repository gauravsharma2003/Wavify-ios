//
//  CategoryPlaylistCard.swift
//  Wavify
//
//  Card component for displaying a playlist from a random category
//  Features centered image, title, and action buttons
//

import SwiftUI
import SwiftData

struct CategoryPlaylistCard: View {
    let playlist: CategoryPlaylist
    let categoryName: String
    let namespace: Namespace.ID
    let onCardTap: () -> Void
    let onPlayTap: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var gradientColors: [Color] = [Color(red: 0.15, green: 0.1, blue: 0.2), Color(red: 0.1, green: 0.08, blue: 0.15), Color(white: 0.08)]
    @State private var isSaved: Bool = false
    
    private var thumbnailUrl: String {
        ImageUtils.thumbnailForCard(playlist.thumbnailUrl)
    }
    
    var body: some View {
        Button(action: onCardTap) {
            VStack(spacing: 12) {
                // Centered playlist image
                CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .overlay {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .matchedTransitionSource(id: playlist.playlistId, in: namespace)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // Title and subtitle section
                VStack(spacing: 4) {
                    // Playlist title - bigger font
                    Text(playlist.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    
                    // Subtitle (artist/description) below title
                    if let subtitle = playlist.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                Spacer(minLength: 4)
                
                // Bottom row: Buttons aligned to right
                HStack {
                    Spacer()
                    
                    // Save button
                    Button(action: {
                        toggleSavePlaylist()
                    }) {
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isSaved ? .green : .white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    
                    // Play button (rightmost)
                    Button(action: onPlayTap) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(16)
            .frame(width: UIScreen.main.bounds.width * 0.85, height: 340)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .task {
            await extractColors()
            checkSavedStatus()
        }
    }
    
    // MARK: - Color Extraction
    
    private func extractColors() async {
        guard let url = URL(string: thumbnailUrl),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        
        let colors = await ColorExtractor.extractColors(from: uiImage)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                gradientColors = [
                    colors.0.opacity(0.85),
                    colors.1.opacity(0.6),
                    Color(white: 0.08)
                ]
            }
        }
    }
    
    // MARK: - Save/Unsave Playlist
    
    private func checkSavedStatus() {
        let playlistId = playlist.playlistId
        let descriptor = FetchDescriptor<LocalPlaylist>(
            predicate: #Predicate { $0.albumId == playlistId }
        )
        isSaved = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }
    
    private func toggleSavePlaylist() {
        if isSaved {
            removePlaylist()
        } else {
            savePlaylist()
        }
    }
    
    private func savePlaylist() {
        // Create the local playlist (songs will be fetched when user opens it)
        let localPlaylist = LocalPlaylist(
            name: playlist.name,
            thumbnailUrl: playlist.thumbnailUrl,
            albumId: playlist.playlistId
        )
        
        modelContext.insert(localPlaylist)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSaved = true
        }
    }
    
    private func removePlaylist() {
        let playlistId = playlist.playlistId
        let descriptor = FetchDescriptor<LocalPlaylist>(
            predicate: #Predicate { $0.albumId == playlistId }
        )
        
        if let existingPlaylist = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existingPlaylist)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSaved = false
            }
        }
    }
}
