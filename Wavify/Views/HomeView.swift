//
//  HomeView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 30/12/25.
//

import SwiftUI
import Observation

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    var audioPlayer: AudioPlayer
    @State var navigationManager: NavigationManager = .shared
    
    var body: some View {
        NavigationStack(path: $navigationManager.homePath) {
            ZStack {
                // Background
                gradientBackground
                
                if viewModel.isLoading && viewModel.homePage == nil {
                    ProgressView()
                        .tint(.white)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            // Chip Cloud (Fixed at top of scroll or pinned?)
                            // For now, inside scroll but could be pinned
                            if let chips = viewModel.homePage?.chips, !chips.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(chips) { chip in
                                            ChipView(
                                                title: chip.title,
                                                isSelected: chip.isSelected || viewModel.selectedChipId == chip.id
                                            ) {
                                                Task {
                                                    await viewModel.selectChip(chip)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.top, 8)
                            }
                            
                            // Sections
                            if let sections = viewModel.homePage?.sections {
                                ForEach(sections) { section in
                                    HomeSectionView(section: section) { result in
                                        handleResultTap(result)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                        .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image(systemName: "music.note.house.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .artist(let id, let name, let thumbnail):
                    ArtistDetailView(
                        artistId: id,
                        initialName: name,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .album(let id, let name, let artist, let thumbnail):
                    AlbumDetailView(
                        albumId: id,
                        initialName: name,
                        initialArtist: artist,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                case .song(_):
                    EmptyView()
                case .playlist(let id, let name, let thumbnail):
                    PlaylistDetailView(
                        playlistId: id,
                        initialName: name,
                        initialThumbnail: thumbnail,
                        audioPlayer: audioPlayer
                    )
                }
            }
        }
        .task {
            await viewModel.loadInitialContent()
        }
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            colors: [Color(hex: "1a1a1a"), .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private func handleResultTap(_ result: SearchResult) {
        if result.type == .song {
            Task {
                await audioPlayer.loadAndPlay(song: Song(from: result))
            }
        } else if result.type == .album {
            navigationManager.homePath.append(NavigationDestination.album(result.id, result.name, result.artist, result.thumbnailUrl))
        } else if result.type == .artist {
            navigationManager.homePath.append(NavigationDestination.artist(result.id, result.name, result.thumbnailUrl))
        } else if result.type == .playlist {
            navigationManager.homePath.append(NavigationDestination.playlist(result.id, result.name, result.thumbnailUrl))
        }
    }
}

// MARK: - Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Subviews

struct ChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color(white: 0.15))
                .foregroundColor(isSelected ? .black : .white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

struct HomeSectionView: View {
    let section: HomeSection
    let onResultTap: (SearchResult) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                if let strapline = section.strapline {
                    Text(strapline)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                }
                Text(section.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(section.items) { item in
                        ItemCard(item: item) {
                            onResultTap(item)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ItemCard: View {
    let item: SearchResult
    let onTap: () -> Void
    
    // Helper to get high quality image
    private var highQualityThumbnailUrl: String {
        // Replace resolution specs like "w120-h120" with larger ones if present
        // Or assume URL can be modified.
        // YouTube Music URLs often have regex like `s120-c-...` or `w120-h120-...`
        // We'll replace typical size markers with larger ones
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
             p = p.replacingOccurrences(of: "w120-h120", with: "w540-h540")
        } else if p.contains("w60-h60") {
             p = p.replacingOccurrences(of: "w60-h60", with: "w540-h540")
        } else if p.contains("s120") {
             p = p.replacingOccurrences(of: "s120", with: "s540")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                AsyncImage(url: URL(string: highQualityThumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Color.gray.opacity(0.3)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 160, height: 160) // Slightly larger for better look
                .clipShape(RoundedRectangle(cornerRadius: 12)) // Softer corners
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4) // Drop shadow for depth
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: 160)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
class HomeViewModel {
    var homePage: HomePage?
    var selectedChipId: String?
    var isLoading = false
    
    private let networkManager = NetworkManager.shared
    
    func loadInitialContent() async {
        if homePage == nil {
            await loadHome()
        }
    }
    
    func refresh() async {
        if let selectedChipId = selectedChipId,
           let chip = homePage?.chips.first(where: { $0.id == selectedChipId }) {
            await selectChip(chip)
        } else {
            await loadHome()
        }
    }
    
    func loadHome() async {
        isLoading = true
        do {
            // Load Standard Home
            var home = try await networkManager.getHome()
            
            // Load Global Charts (Top Songs)
            async let globalCharts = try? networkManager.getCharts(country: "ZZ")
            async let punjabiCharts = try? networkManager.getCharts(country: "IN") // Using India for Punjabi context
            
            let gCharts = await globalCharts
            let pCharts = await punjabiCharts
            
            // Insert Charts into Sections
            // We want "Global" and "Punjabi" sections at the top or after quick picks
            
            var newSections: [HomeSection] = []
            
            // Add Global Top Songs if available
            if let gSections = gCharts?.sections {
                // Find "Top Songs" section
                if let topSongs = gSections.first(where: { $0.title.contains("Top songs") }) {
                    newSections.append(HomeSection(title: "Global Top Songs", strapline: "Trending Worldwide", items: topSongs.items))
                }
            }
            
            // Add Punjabi/India Top Songs if available
            if let pSections = pCharts?.sections {
                // Find "Top Songs" section
                if let topSongs = pSections.first(where: { $0.title.contains("Top songs") }) {
                    newSections.append(HomeSection(title: "Trending in India", strapline: "Top Songs", items: topSongs.items))
                }
            }
            
            // Combine with Home Sections
            // We'll put these new sections after the first section (usually Quick Picks)
            if !home.sections.isEmpty {
                home.sections.insert(contentsOf: newSections, at: 1)
            } else {
                home.sections.append(contentsOf: newSections)
            }
            
            self.homePage = home
            self.selectedChipId = nil
            
        } catch {
            print("Failed to load home: \(error)")
        }
        isLoading = false
    }
    
    func selectChip(_ chip: Chip) async {
        if selectedChipId == chip.id {
            await loadHome()
            return
        }
        
        isLoading = true
        selectedChipId = chip.id
        
        do {
            self.homePage = try await networkManager.loadPage(endpoint: chip.endpoint)
        } catch {
            print("Failed to load chip: \(error)")
        }
        isLoading = false
    }
}
