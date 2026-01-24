//
//  MusicPlayerWidget.swift
//  WavifyWidget
//
//  Home screen widget displaying current/last played song with playback controls
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct MusicPlayerEntry: TimelineEntry {
    let date: Date
    let songData: SharedSongData?
    let thumbnailData: Data?
    
    static var placeholder: MusicPlayerEntry {
        MusicPlayerEntry(
            date: Date(),
            songData: SharedSongData(
                videoId: "placeholder",
                title: "Song Title",
                artist: "Artist Name",
                thumbnailUrl: "",
                duration: "3:45",
                isPlaying: false
            ),
            thumbnailData: nil
        )
    }
    
    static var empty: MusicPlayerEntry {
        MusicPlayerEntry(
            date: Date(),
            songData: nil,
            thumbnailData: nil
        )
    }
}

// MARK: - Timeline Provider

struct MusicPlayerProvider: TimelineProvider {
    
    /// App Group identifier shared with main app
    private let appGroupIdentifier = "group.com.gaurav.Wavify"
    
    func placeholder(in context: Context) -> MusicPlayerEntry {
        MusicPlayerEntry.placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MusicPlayerEntry) -> Void) {
        let entry = loadCurrentEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicPlayerEntry>) -> Void) {
        let entry = loadCurrentEntry()
        
        // Refresh every 15 minutes or when app updates data
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> MusicPlayerEntry {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: "lastPlayedSong"),
              let songData = try? JSONDecoder().decode(SharedSongData.self, from: data) else {
            return MusicPlayerEntry.empty
        }
        
        let thumbnailData = defaults.data(forKey: "cachedThumbnail")
        
        return MusicPlayerEntry(
            date: Date(),
            songData: songData,
            thumbnailData: thumbnailData
        )
    }
}

// MARK: - Widget View

struct MusicPlayerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: MusicPlayerEntry
    
    var body: some View {
        Group {
            if let songData = entry.songData {
                songPlayerView(songData: songData)
            } else {
                emptyStateView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    // MARK: - Main Player View
    
    @ViewBuilder
    private func songPlayerView(songData: SharedSongData) -> some View {
        switch family {
        case .systemMedium:
            mediumWidgetView(songData: songData)
        case .systemLarge:
            largeWidgetView(songData: songData)
        default:
            smallWidgetView(songData: songData)
        }
    }
    
    // MARK: - Small Widget
    
    private func smallWidgetView(songData: SharedSongData) -> some View {
        VStack(spacing: 8) {
            albumArtView(size: 50)
            
            Text(songData.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            // Play/Pause button only for small widget
            Button(intent: PlayPauseIntent()) {
                Image(systemName: songData.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Medium Widget
    
    private func mediumWidgetView(songData: SharedSongData) -> some View {
        HStack(spacing: 16) {
            albumArtView(size: 80)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(songData.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                Text(songData.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Playback controls
                HStack(spacing: 24) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: songData.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Large Widget
    
    private func largeWidgetView(songData: SharedSongData) -> some View {
        VStack(spacing: 16) {
            albumArtView(size: 160)
            
            VStack(spacing: 8) {
                Text(songData.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                
                Text(songData.artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Playback controls
            HStack(spacing: 36) {
                Button(intent: PreviousTrackIntent()) {
                    Image(systemName: "backward.fill")
                        .font(.title)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: songData.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                
                Button(intent: NextTrackIntent()) {
                    Image(systemName: "forward.fill")
                        .font(.title)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("No song played yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Open Wavify to start listening")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Album Art View
    
    @ViewBuilder
    private func albumArtView(size: CGFloat) -> some View {
        if let thumbnailData = entry.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - Widget Configuration

struct MusicPlayerWidget: Widget {
    let kind: String = "MusicPlayerWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MusicPlayerProvider()) { entry in
            MusicPlayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Control playback and see what's playing in Wavify.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    MusicPlayerWidget()
} timeline: {
    MusicPlayerEntry.placeholder
    MusicPlayerEntry.empty
}
