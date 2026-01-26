//
//  SearchViewModel.swift
//  Wavify
//
//  ViewModel for search functionality with debounced suggestions and filtering
//

import Foundation
import Observation

// MARK: - Search Filter

enum SearchFilter: String, CaseIterable {
    case all = "All"
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"
    
    var params: String? {
        switch self {
        case .all: return nil
        case .songs: return "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
        }
    }
}

// MARK: - Search ViewModel

@MainActor
@Observable
class SearchViewModel {
    // MARK: - Published State
    
    var searchText = "" {
        didSet {
            if searchText != oldValue {
                handleSearchTextChange(searchText)
            }
        }
    }
    
    var suggestions: [SearchSuggestion] = []
    var topResults: [SearchResult] = []
    var results: [SearchResult] = []
    var isSearching = false
    var selectedFilter: SearchFilter = .all
    var hasSearched = false
    var chips: [Chip] = []
    
    // MARK: - Private State
    
    private var justPerformedSearchFromSuggestion = false
    private var chipsLoaded = false
    private let networkManager = NetworkManager.shared
    private var suggestionTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Chips Loading
    
    func loadChipsIfNeeded() async {
        guard !chipsLoaded else { return }
        chipsLoaded = true
        await fetchChips()
    }
    
    func fetchChips() async {
        do {
            let home = try await networkManager.getHome()
            self.chips = home.chips.filter { $0.title.lowercased() != "podcasts" }
        } catch {
            Logger.error("Failed to fetch chips", category: .network, error: error)
        }
    }
    
    // MARK: - Search Text Handling
    
    private func handleSearchTextChange(_ query: String) {
        debounceTask?.cancel()
        suggestionTask?.cancel()
        
        if justPerformedSearchFromSuggestion {
            justPerformedSearchFromSuggestion = false
            return
        }
        
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await fetchSuggestions(query: query)
        }
    }
    
    // MARK: - Suggestions
    
    private func fetchSuggestions(query: String) async {
        suggestionTask?.cancel()
        
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        
        do {
            let fetchedSuggestions = try await networkManager.getSearchSuggestions(query: query)
            if !Task.isCancelled {
                suggestions = fetchedSuggestions
            }
        } catch {
            if !Task.isCancelled {
                Logger.error("Failed to fetch suggestions", category: .network, error: error)
            }
        }
    }
    
    // MARK: - Search
    
    func performSearch() {
        guard !searchText.isEmpty else { return }
        
        debounceTask?.cancel()
        suggestionTask?.cancel()
        
        isSearching = true
        suggestions = []
        hasSearched = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                let searchResults = try await self.networkManager.search(query: self.searchText, params: self.selectedFilter.params)
                await MainActor.run {
                    self.topResults = searchResults.topResults
                    self.results = searchResults.results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.isSearching = false
                }
                Logger.error("Search failed", category: .network, error: error)
            }
        }
    }
    
    func performSearchFromSuggestion(text: String) {
        justPerformedSearchFromSuggestion = true
        searchText = text
        performSearch()
    }
    
    func applyFilter(_ filter: SearchFilter) {
        guard filter != selectedFilter else { return }
        selectedFilter = filter
        performSearch()
    }
}
