//
//  LanguageChartCard.swift
//  Wavify
//
//  Card component for displaying a language-specific music chart
//  Features gradient background, playlist info, 3 song rows, and glass action buttons
//

import SwiftUI
import SwiftData

struct LanguageChartCard: View {
    let chart: LanguageChart
    let namespace: Namespace.ID
    let onCardTap: () -> Void
    let onSongTap: (Int) -> Void  // Index of song in playlist
    let onPlayTap: () -> Void
    
    // Callbacks for song actions
    var onAddToPlaylist: ((SearchResult) -> Void)?
    var onToggleLike: ((SearchResult) -> Void)?
    var onPlayNext: ((SearchResult) -> Void)?
    var onAddToQueue: ((SearchResult) -> Void)?
    var likedSongIds: Set<String> = []
    var queueSongIds: Set<String> = []
    
    @Environment(\.modelContext) private var modelContext
    @State private var gradientColors: [Color] = [Color(red: 0.15, green: 0.1, blue: 0.2), Color(red: 0.1, green: 0.08, blue: 0.15), Color(white: 0.08)]
    @State private var isSaved: Bool = false
    
    private var thumbnailUrl: String {
        ImageUtils.thumbnailForCard(chart.thumbnailUrl)
    }
    
    var body: some View {
        Button(action: onCardTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Header: Thumbnail + Playlist Name
                headerSection
                    .padding(.bottom, 16)
                
                // Song rows (first 3 songs)
                songRowsSection
                
                Spacer(minLength: 8)
                
                // Action buttons: Save (left) and Play (right)
                actionButtons
            }
            .padding(20)
            .frame(width: UIScreen.main.bounds.width * 0.85, height: 390)
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
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            // Album art from chart thumbnail
            CachedAsyncImagePhase(url: URL(string: thumbnailUrl)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .matchedTransitionSource(id: chart.playlistId, in: namespace)
            
            // Playlist name and info - vertically centered
            VStack(alignment: .leading, spacing: 4) {
                Text(chart.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text("100 songs")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Song Rows Section
    
    private var songRowsSection: some View {
        VStack(spacing: 4) {
            ForEach(Array(chart.songs.enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 10) {
                    // Tappable song area
                    Button {
                        onSongTap(index)
                    } label: {
                        HStack(spacing: 10) {
                            // Song thumbnail
                            CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Color.gray.opacity(0.3)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            // Song info
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                
                                Text(song.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // 3 dots menu with context menu
                    Menu {
                        Button {
                            onAddToPlaylist?(song)
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                        }
                        
                        Button {
                            onToggleLike?(song)
                        } label: {
                            let isLiked = likedSongIds.contains(song.id)
                            Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.fill" : "heart")
                        }
                        
                        Button {
                            onPlayNext?(song)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        
                        Button {
                            onAddToQueue?(song)
                        } label: {
                            let isInQueue = queueSongIds.contains(song.id)
                            Label(isInQueue ? "In Queue" : "Add to Queue", systemImage: "text.append")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .rotationEffect(.degrees(90))
                            .frame(width: 32, height: 44)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Save button - full width with text
            Button(action: {
                toggleSavePlaylist()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus")
                        .font(.system(size: 16, weight: .medium))
                    Text(isSaved ? "Saved" : "Save")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(isSaved ? .green : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            // Play button - full width with text
            Button(action: onPlayTap) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .medium))
                    Text("Play")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
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
                // Use pure album colors - darkened for background
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
        let playlistId = chart.playlistId
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
        guard !chart.songs.isEmpty else { return }
        
        // Create the local playlist
        let localPlaylist = LocalPlaylist(
            name: chart.displayName,
            thumbnailUrl: chart.thumbnailUrl,
            albumId: chart.playlistId
        )
        
        // Create and add local songs
        for (index, searchResult) in chart.songs.enumerated() {
            let song = Song(from: searchResult)
            let videoId = song.videoId
            let songDescriptor = FetchDescriptor<LocalSong>(
                predicate: #Predicate { $0.videoId == videoId }
            )
            
            let localSong: LocalSong
            if let existingSong = try? modelContext.fetch(songDescriptor).first {
                localSong = existingSong
            } else {
                localSong = LocalSong(
                    videoId: song.videoId,
                    title: song.title,
                    artist: song.artist,
                    thumbnailUrl: song.thumbnailUrl,
                    duration: song.duration,
                    orderIndex: index
                )
                modelContext.insert(localSong)
            }
            
            localSong.orderIndex = index
            localPlaylist.songs.append(localSong)
        }
        
        modelContext.insert(localPlaylist)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSaved = true
        }
    }
    
    private func removePlaylist() {
        let playlistId = chart.playlistId
        let descriptor = FetchDescriptor<LocalPlaylist>(
            predicate: #Predicate { $0.albumId == playlistId }
        )
        
        if let playlist = try? modelContext.fetch(descriptor).first {
            modelContext.delete(playlist)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSaved = false
            }
        }
    }
}

// MARK: - Color Blending Extension

extension Color {
    func blend(with other: Color, amount: Double) -> Color {
        // Simple blending by converting to UIColor
        let uiSelf = UIColor(self)
        let uiOther = UIColor(other)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        uiSelf.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiOther.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        return Color(
            red: r1 * (1 - amount) + r2 * amount,
            green: g1 * (1 - amount) + g2 * amount,
            blue: b1 * (1 - amount) + b2 * amount
        )
    }
}
