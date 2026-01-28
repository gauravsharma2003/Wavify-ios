//
//  SearchHistoryManager.swift
//  Wavify
//
//  Created by Guardian on 28/01/26.
//

import Foundation

class SearchHistoryManager {
    static let shared = SearchHistoryManager()
    
    private let key = "search_history"
    private let maxHistoryItems = 10
    
    private init() {}
    
    func getHistory() -> [String] {
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }
    
    func add(term: String) {
        var history = getHistory()
        
        // Remove existing if present to move to top
        if let index = history.firstIndex(of: term) {
            history.remove(at: index)
        }
        
        // Insert at top
        history.insert(term, at: 0)
        
        // Cap key at max items
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        
        UserDefaults.standard.set(history, forKey: key)
    }
    
    func remove(term: String) {
        var history = getHistory()
        
        if let index = history.firstIndex(of: term) {
            history.remove(at: index)
            UserDefaults.standard.set(history, forKey: key)
        }
    }
    
    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
