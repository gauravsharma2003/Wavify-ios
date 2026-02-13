//
//  SuggestSongSheet.swift
//  Wavify
//
//  Sheet for guests to search and suggest songs to the host
//

import SwiftUI

struct SuggestSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchViewModel = SearchViewModel()
    @State private var sharePlayManager = SharePlayManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search for a song to suggest...", text: $searchViewModel.searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            searchViewModel.performSearch()
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.08))
                }
                .padding()

                // Results
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let songResults = searchViewModel.results.filter { $0.type == .song }
                        ForEach(songResults) { result in
                            Button {
                                let song = Song(from: result)
                                sharePlayManager.suggestSong(song)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    CachedAsyncImagePhase(url: URL(string: result.thumbnailUrl)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            Rectangle().fill(.white.opacity(0.1))
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(result.artist)
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.cyan)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if result.id != songResults.last?.id {
                                Divider()
                                    .padding(.leading, 78)
                                    .opacity(0.3)
                            }
                        }
                    }
                }
            }
            .background(Color.brandBackground.ignoresSafeArea())
            .navigationTitle("Suggest a Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
