//
//  ShareCardTypes.swift
//  Wavify
//

import SwiftUI

// MARK: - Share Mode

enum ShareMode: String, CaseIterable {
    case song = "Song"
    case lyrics = "Lyrics"
}

// MARK: - Share Color Option

enum ShareColorOption: String, CaseIterable, Identifiable {
    case primary
    case gradient2
    case gradient3
    case black
    case white
    case orange
    case red
    case blue
    case green
    case neon

    var id: String { rawValue }

    @ViewBuilder
    func cardBackground(primary: Color, secondary: Color, accent: Color) -> some View {
        switch self {
        case .primary:   primary
        case .gradient2: LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gradient3: LinearGradient(colors: [primary, secondary, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .black:     Color.black
        case .white:     Color.white
        case .orange:    Color(red: 0.95, green: 0.55, blue: 0.15)
        case .red:       Color(red: 0.85, green: 0.15, blue: 0.15)
        case .blue:      Color(red: 0.15, green: 0.35, blue: 0.85)
        case .green:     Color(red: 0.15, green: 0.65, blue: 0.3)
        case .neon:      Color(red: 0.0, green: 1.0, blue: 0.8)
        }
    }

    @ViewBuilder
    func circleFill(primary: Color, secondary: Color, accent: Color) -> some View {
        switch self {
        case .primary:   Circle().fill(primary)
        case .gradient2: Circle().fill(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .gradient3: Circle().fill(LinearGradient(colors: [primary, secondary, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .black:     Circle().fill(Color.black)
        case .white:     Circle().fill(Color.white)
        case .orange:    Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.15))
        case .red:       Circle().fill(Color(red: 0.85, green: 0.15, blue: 0.15))
        case .blue:      Circle().fill(Color(red: 0.15, green: 0.35, blue: 0.85))
        case .green:     Circle().fill(Color(red: 0.15, green: 0.65, blue: 0.3))
        case .neon:      Circle().fill(Color(red: 0.0, green: 1.0, blue: 0.8))
        }
    }

    var usesDarkText: Bool {
        self == .white || self == .neon
    }
}

// MARK: - Lyrics Selection State

@Observable
@MainActor
final class LyricsSelectionState {

    struct LyricLine: Identifiable {
        let id: Int
        let text: String
    }

    private(set) var lines: [LyricLine] = []
    private(set) var selectedRange: ClosedRange<Int>? = nil
    let maxLines = 6

    var selectedTexts: [String] {
        guard let range = selectedRange else { return [] }
        return lines.filter { range.contains($0.id) }.map(\.text)
    }

    var hasSelection: Bool { selectedRange != nil }

    func isSelected(_ index: Int) -> Bool {
        selectedRange?.contains(index) ?? false
    }

    func setLines(from state: LyricsState) {
        switch state {
        case .synced(let syncedLines):
            lines = syncedLines.enumerated().compactMap { index, line in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return LyricLine(id: index, text: trimmed)
            }
        case .plain(let text):
            lines = text.components(separatedBy: "\n").enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return LyricLine(id: index, text: trimmed)
            }
        default:
            lines = []
        }
        selectedRange = nil
    }

    func tapLine(at index: Int) {
        guard lines.contains(where: { $0.id == index }) else { return }

        // Nothing selected → select single line
        guard let range = selectedRange else {
            selectedRange = index...index
            return
        }

        // Already inside selection → reset to just this line
        if range.contains(index) {
            if range.count == 1 {
                // Only one selected and tapped again → deselect
                selectedRange = nil
            } else {
                // Multiple selected, tap one → keep only that line
                selectedRange = index...index
            }
            return
        }

        // Compute hypothetical extended range
        let newLower = min(range.lowerBound, index)
        let newUpper = max(range.upperBound, index)
        let newCount = newUpper - newLower + 1

        if newCount <= maxLines {
            // Extension fits within max → extend range
            selectedRange = newLower...newUpper
        } else if index == range.lowerBound - 1 && range.count == maxLines {
            // Adjacent above, at max → slide window up
            selectedRange = index...(range.upperBound - 1)
        } else if index == range.upperBound + 1 && range.count == maxLines {
            // Adjacent below, at max → slide window down
            selectedRange = (range.lowerBound + 1)...index
        } else {
            // Too far away or would exceed max → reset to single line
            selectedRange = index...index
        }
    }
}
