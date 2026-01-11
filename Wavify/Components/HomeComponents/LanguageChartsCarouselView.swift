//
//  LanguageChartsCarouselView.swift
//  Wavify
//
//  Horizontal carousel of language-specific music chart cards
//  Features snap-to-card scrolling with peek of adjacent cards
//

import SwiftUI

struct LanguageChartsCarouselView: View {
    let charts: [LanguageChart]
    var audioPlayer: AudioPlayer
    let likedSongIds: Set<String>
    let queueSongIds: Set<String>
    let namespace: Namespace.ID
    let onPlaylistTap: (LanguageChart) -> Void
    let onAddToPlaylist: (SearchResult) -> Void
    let onToggleLike: (SearchResult) -> Void
    let onPlayNext: (SearchResult) -> Void
    let onAddToQueue: (SearchResult) -> Void
    
    private let cardWidth: CGFloat = UIScreen.main.bounds.width * 0.85
    private let cardSpacing: CGFloat = 12
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 2) {
                Text("Charts by Language")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .textCase(.uppercase)
                Text("Top Weekly")
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Horizontal carousel with snap scrolling
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(charts) { chart in
                        LanguageChartCard(
                            chart: chart,
                            namespace: namespace,
                            onCardTap: {
                                onPlaylistTap(chart)
                            },
                            onSongTap: { index in
                                playSongFromChart(chart: chart, index: index)
                            },
                            onPlayTap: {
                                playEntireChart(chart)
                            },
                            onAddToPlaylist: onAddToPlaylist,
                            onToggleLike: onToggleLike,
                            onPlayNext: onPlayNext,
                            onAddToQueue: onAddToQueue,
                            likedSongIds: likedSongIds,
                            queueSongIds: queueSongIds
                        )
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, (UIScreen.main.bounds.width - cardWidth) / 2)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
    
    // MARK: - Playback Actions
    
    private func playSongFromChart(chart: LanguageChart, index: Int) {
        // Convert SearchResults to Songs and play from the specified index
        let songs = chart.songs.map { Song(from: $0) }
        Task {
            await audioPlayer.playAlbum(songs: songs, startIndex: index, shuffle: false)
        }
    }
    
    private func playEntireChart(_ chart: LanguageChart) {
        let songs = chart.songs.map { Song(from: $0) }
        Task {
            await audioPlayer.playAlbum(songs: songs, startIndex: 0, shuffle: false)
        }
    }
}
