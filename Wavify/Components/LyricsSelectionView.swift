//
//  LyricsSelectionView.swift
//  Wavify
//

import SwiftUI

struct LyricsSelectionView: View {
    let lyricsState: LyricsState
    @Bindable var selectionState: LyricsSelectionState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(selectionState.lines) { line in
                    lyricLineRow(line)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .onAppear {
            if selectionState.lines.isEmpty {
                selectionState.setLines(from: lyricsState)
            }
        }
    }

    private func lyricLineRow(_ line: LyricsSelectionState.LyricLine) -> some View {
        let selected = selectionState.isSelected(line.id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) {
                selectionState.tapLine(at: line.id)
            }
        } label: {
            Text(line.text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.1) : .clear)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
