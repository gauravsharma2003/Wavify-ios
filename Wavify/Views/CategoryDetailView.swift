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
    let namespace: Namespace.ID
    var audioPlayer: AudioPlayer
    
    @Environment(\.dismiss) private var dismiss
    @State private var page: HomePage?
    @State private var isLoading = true
    
    // Force refresh to restore visibility after zoom transition (iOS 18 bug workaround)
    @State private var refreshId = UUID()
    
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
                            HomeSectionView(section: section, namespace: namespace, refreshId: refreshId) { result in
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
            Logger.networkError("Failed to load category", error: error)
        }
        isLoading = false
    }
    
    private func handleResultTap(_ result: SearchResult) {
        // Reuse navigation logic
        NavigationManager.shared.handleNavigation(for: result, audioPlayer: audioPlayer)
    }
}
