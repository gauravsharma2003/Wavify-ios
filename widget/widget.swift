//
//  widget.swift
//  widget
//
//  Home screen widget displaying current/last played song with playback controls
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Favorite Item

struct WidgetFavoriteItem: Codable {
    let id: String
    let name: String
    let thumbnailUrl: String
    let type: String // "artist" or "song"
}

// MARK: - Widget Entry

struct MusicPlayerEntry: TimelineEntry {
    let date: Date
    let songData: SharedSongData?
    let thumbnailData: Data?
    let favorites: [WidgetFavoriteItem]
    let favoriteThumbnails: [Int: Data]
    
    static var placeholder: MusicPlayerEntry {
        MusicPlayerEntry(
            date: Date(),
            songData: SharedSongData(
                videoId: "placeholder",
                title: "Song Title",
                artist: "Artist Name",
                thumbnailUrl: "",
                duration: "3:45",
                isPlaying: false,
                currentTime: 0,
                totalDuration: 225
            ),
            thumbnailData: nil,
            favorites: [],
            favoriteThumbnails: [:]
        )
    }
    
    static var empty: MusicPlayerEntry {
        MusicPlayerEntry(
            date: Date(),
            songData: nil,
            thumbnailData: nil,
            favorites: [],
            favoriteThumbnails: [:]
        )
    }
}

// MARK: - Timeline Provider

struct MusicPlayerProvider: TimelineProvider {
    
    private let appGroupIdentifier = "group.com.gaurav.Wavify"
    
    // File names (must match main app)
    private let songFileName = "lastPlayedSong.json"
    private let thumbnailFileName = "cachedThumbnail.data"
    
    func placeholder(in context: Context) -> MusicPlayerEntry {
        MusicPlayerEntry.placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MusicPlayerEntry) -> Void) {
        let entry = loadCurrentEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicPlayerEntry>) -> Void) {
        let entry = loadCurrentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> MusicPlayerEntry {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return MusicPlayerEntry.empty
        }
        
        // Load song data from file
        let songFileURL = containerURL.appendingPathComponent(songFileName)
        var songData: SharedSongData? = nil
        
        if let data = try? Data(contentsOf: songFileURL) {
            songData = try? JSONDecoder().decode(SharedSongData.self, from: data)
        }
        
        // Load thumbnail from file
        let thumbnailFileURL = containerURL.appendingPathComponent(thumbnailFileName)
        let thumbnailData = try? Data(contentsOf: thumbnailFileURL)
        
        // Load favorites (still using UserDefaults for now, can migrate if needed)
        var favorites: [WidgetFavoriteItem] = []
        var favoriteThumbnails: [Int: Data] = [:]
        
        if let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            if let favData = defaults.data(forKey: "widgetFavorites") {
                favorites = (try? JSONDecoder().decode([WidgetFavoriteItem].self, from: favData)) ?? []
            }
            
            for i in 0..<4 {
                if let thumbData = defaults.data(forKey: "favoriteThumbnail_\(i)") {
                    favoriteThumbnails[i] = thumbData
                }
            }
        }
        
        if songData == nil {
            return MusicPlayerEntry.empty
        }
        
        return MusicPlayerEntry(
            date: Date(),
            songData: songData,
            thumbnailData: thumbnailData,
            favorites: favorites,
            favoriteThumbnails: favoriteThumbnails
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
    }
    
    // MARK: - Main Player View
    
    @ViewBuilder
    private func songPlayerView(songData: SharedSongData) -> some View {
        switch family {
        case .systemMedium:
            mediumWidgetView(songData: songData)
        default:
            smallWidgetView(songData: songData)
        }
    }
    
    // MARK: - Small Widget
    
    private func smallWidgetView(songData: SharedSongData) -> some View {
        GeometryReader { geo in
            ZStack {
                // Album art background with blur
                if let thumbnailData = entry.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 25)
                        .overlay(Color.black.opacity(0.35))
                } else {
                    backgroundGradient
                }
                
                VStack(spacing: 0) {
                    // Top section
                    HStack(alignment: .top) {
                        // Large album art - top left
                        albumArtView(size: 85, cornerRadius: 20)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                        
                        Spacer()
                        
                        // Wavify logo - top right
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Spacer()
                    
                    // Bottom section: Song info + Play button
                    HStack(alignment: .bottom) {
                        // Song info - left
                        VStack(alignment: .leading, spacing: 3) {
                            Text(songData.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            
                            Text(songData.artist)
                                .font(.system(size: 12, weight: .regular))
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        
                        Spacer()
                        
                        // Play/Pause button - bottom right
                        Button(intent: PlayPauseIntent()) {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: songData.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.black)
                                    .offset(x: songData.isPlaying ? 0 : 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
        .containerBackground(for: .widget) { backgroundGradient }
    }
    
    // MARK: - Medium Widget
    
    private func mediumWidgetView(songData: SharedSongData) -> some View {
        GeometryReader { geo in
            ZStack {
                // Blurred album art background (using downsized thumbnail)
                if let thumbnailData = entry.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Color.clear
                        .background(
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 20)
                        .overlay(Color.black.opacity(0.5))
                        .id(songData.videoId) // Force redraw when song changes
                } else {
                    backgroundGradient
                }
                
                VStack(spacing: 8) {
                    // Top: Player section
                    HStack(alignment: .center, spacing: 10) {
                        // Album art (smaller size)
                        albumArtView(size: 50)
                        
                        // Song info
                        VStack(alignment: .leading, spacing: 3) {
                            Text(songData.title)
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(2)
                                .foregroundStyle(.white)
                            
                            Text(songData.artist)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Right: Logo + Play button
                        VStack(spacing: 6) {
                            // Wavify logo
                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            // Play button
                            Button(intent: PlayPauseIntent()) {
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: songData.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    
                    // Bottom: Favorites grid (tappable via deep links)
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { index in
                            if index < entry.favorites.count {
                                let favorite = entry.favorites[index]
                                let urlString = favorite.type == "artist" 
                                    ? "wavify://artist/\(favorite.id)" 
                                    : "wavify://song/\(favorite.id)"
                                Link(destination: URL(string: urlString)!) {
                                    favoriteItem(index: index, favorite: favorite)
                                }
                            } else {
                                // Placeholder box
                                favoritesBlock(isArtist: index == 0)
                            }
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .padding(.vertical, 12)
            }
        }
        .containerBackground(for: .widget) { backgroundGradient }
    }
    
    // MARK: - Favorite Item View (with cached image)
    
    @ViewBuilder
    private func favoriteItem(index: Int, favorite: WidgetFavoriteItem) -> some View {
        let isArtist = favorite.type == "artist"
        let cornerRadius: CGFloat = isArtist ? 50 : 8
        
        // Use cached thumbnail data from App Groups
        if let imageData = entry.favoriteThumbnails[index],
           let uiImage = UIImage(data: imageData) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // Fallback to placeholder
            favoritesBlock(isArtist: isArtist)
        }
    }
    
    // MARK: - Favorites Block (empty placeholder)
    
    private func favoritesBlock(isArtist: Bool) -> some View {
        RoundedRectangle(cornerRadius: isArtist ? 50 : 8)
            .fill(.white.opacity(0.15))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: isArtist ? 50 : 8)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 12) {
                Image(systemName: "waveform.low.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.8))
                    .symbolRenderingMode(.hierarchical)
                
                VStack(spacing: 2) {
                    Text("Wavify")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("Play a song to get started")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .containerBackground(for: .widget) { backgroundGradient }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.12, blue: 0.28),
                Color(red: 0.08, green: 0.06, blue: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Album Art View
    
    @ViewBuilder
    private func albumArtView(size: CGFloat, cornerRadius: CGFloat? = nil) -> some View {
        let radius = cornerRadius ?? (size * 0.12)
        
        if let thumbnailData = entry.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: radius))
        } else {
            RoundedRectangle(cornerRadius: radius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.2, blue: 0.6),
                            Color(red: 0.2, green: 0.3, blue: 0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
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
        .description("Control Wavify playback from your home screen")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    MusicPlayerWidget()
} timeline: {
    MusicPlayerEntry.placeholder
    MusicPlayerEntry.empty
}
