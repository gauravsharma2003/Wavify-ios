//
//  CategoryDetailView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let title: String
    let endpoint: BrowseEndpoint
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @State private var page: HomePage?
    @State private var isLoading = true
    
    private let networkManager = NetworkManager.shared
    
    var body: some View {
        ZStack {
            // Background
            Color(white: 0.05).ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let page = page {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(page.sections) { section in
                            HomeSectionView(section: section) { result in
                                handleResultTap(result)
                            }
                        }
                    }
                    .padding(.vertical)
                    .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
                }
            } else {
                Text("Failed to load content")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        do {
            page = try await networkManager.loadPage(endpoint: endpoint)
        } catch {
            print("Failed to load category: \(error)")
        }
        isLoading = false
    }
    
    private func handleResultTap(_ result: SearchResult) {
        // Reuse navigation logic
        NavigationManager.shared.handleNavigation(for: result, audioPlayer: audioPlayer)
    }
}
