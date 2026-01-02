//
//  LyricsView.swift
//  Wavify
//
//  Created by Gaurav Sharma on 02/01/26.
//

import SwiftUI

struct LyricsView: View {
    let lyricsState: LyricsState
    let currentTime: Double
    let onSeek: (Double) -> Void
    let isExpanded: Bool
    let onExpandToggle: () -> Void
    
    @State private var currentLineIndex: Int = 0
    @State private var isUserScrolling: Bool = false
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var showSyncButton: Bool = false
    
    init(
        lyricsState: LyricsState,
        currentTime: Double,
        onSeek: @escaping (Double) -> Void,
        isExpanded: Bool = false,
        onExpandToggle: @escaping () -> Void = {}
    ) {
        self.lyricsState = lyricsState
        self.currentTime = currentTime
        self.onSeek = onSeek
        self.isExpanded = isExpanded
        self.onExpandToggle = onExpandToggle
    }
    
    // Check if we should show expand button
    private var shouldShowExpandButton: Bool {
        switch lyricsState {
        case .synced(let lines) where !lines.isEmpty:
            return true
        case .plain(let text) where !text.isEmpty:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        Group {
            switch lyricsState {
            case .idle, .loading:
                loadingView
            case .synced(let lines):
                syncedLyricsView(lines: lines)
            case .plain(let text):
                plainLyricsView(text: text)
            case .notFound:
                notFoundView
            case .error(let message):
                errorView(message: message)
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Loading lyrics...")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Synced Lyrics View
    
    private func syncedLyricsView(lines: [SyncedLyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: isExpanded ? 18 : 14) {
                    // Minimal top padding
                    Color.clear.frame(height: isExpanded ? 4 : 8)
                    
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(line: line, index: index, totalLines: lines.count)
                            .id(line.id)
                            .onTapGesture {
                                onSeek(line.time)
                            }
                    }
                    
                    // Bottom padding for buttons
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, isExpanded ? 16 : 0)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in
                        isUserScrolling = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSyncButton = true
                        }
                        scrollDebounceTask?.cancel()
                    }
                    .onEnded { _ in
                        scrollDebounceTask = Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            if !Task.isCancelled {
                                await MainActor.run {
                                    isUserScrolling = false
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showSyncButton = false
                                    }
                                }
                            }
                        }
                    }
            )
            .onChange(of: currentTime) { _, newTime in
                let newIndex = calculateCurrentLineIndex(lines: lines, time: newTime)
                
                if newIndex != currentLineIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentLineIndex = newIndex
                    }
                }
                
                if !isUserScrolling, currentLineIndex < lines.count {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(lines[currentLineIndex].id, anchor: .init(x: 0.5, y: isExpanded ? 0.2 : 0.3))
                    }
                }
            }
            .onAppear {
                currentLineIndex = calculateCurrentLineIndex(lines: lines, time: currentTime)
                if currentLineIndex < lines.count {
                    proxy.scrollTo(lines[currentLineIndex].id, anchor: .init(x: 0.5, y: isExpanded ? 0.2 : 0.3))
                }
            }
            .onChange(of: isExpanded) { _, _ in
                if currentLineIndex < lines.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lines[currentLineIndex].id, anchor: .init(x: 0.5, y: isExpanded ? 0.2 : 0.3))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                // Buttons overlay
                HStack(spacing: 12) {
                    if showSyncButton {
                        syncButtonView(proxy: proxy, lines: lines)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    expandButton
                }
                .padding(.horizontal, isExpanded ? 16 : 8)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.001)) // Invisible but blocks touches
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Expand Button
    
    private var expandButton: some View {
        Button {
            onExpandToggle()
        } label: {
            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(GlassButtonStyle())
    }
    
    // MARK: - Sync Button (icon only, glass style)
    
    private func syncButtonView(proxy: ScrollViewProxy, lines: [SyncedLyricLine]) -> some View {
        Button {
            if currentLineIndex < lines.count {
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(lines[currentLineIndex].id, anchor: .init(x: 0.5, y: isExpanded ? 0.2 : 0.3))
                }
            }
            isUserScrolling = false
            withAnimation(.easeInOut(duration: 0.2)) {
                showSyncButton = false
            }
            scrollDebounceTask?.cancel()
        } label: {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(GlassButtonStyle())
    }
    
    // MARK: - Lyric Line View
    
    private func lyricLineView(line: SyncedLyricLine, index: Int, totalLines: Int) -> some View {
        let offset = index - currentLineIndex
        let isCurrent = offset == 0
        
        // Use same font size and weight for all lines to prevent text reflow
        return Text(line.text)
            .font(.system(size: isExpanded ? 22 : 20, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: blurRadius(for: offset))
            .opacity(opacity(for: offset))
            .shimmer(isAnimating: isCurrent)
            .glow(color: .white, radius: isCurrent ? 6 : 0, isActive: isCurrent)
            .animation(.easeInOut(duration: 0.3), value: currentLineIndex)
            .contentShape(Rectangle())
    }
    
    // MARK: - Blur and Opacity Helpers
    
    private func blurRadius(for offset: Int) -> CGFloat {
        switch offset {
        case 0:
            return 0
        case -1, 1:
            return 0.3
        case -2, 2:
            return 0.5
        default:
            return 0.8
        }
    }
    
    private func opacity(for offset: Int) -> Double {
        switch offset {
        case 0:
            return 1.0
        case -1:
            return 0.5
        case 1:
            return 0.7
        case 2:
            return 0.55
        case -2:
            return 0.4
        default:
            return 0.3
        }
    }
    
    // MARK: - Plain Lyrics View
    
    private func plainLyricsView(text: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: isExpanded ? 20 : 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, isExpanded ? 16 : 0)
                    .padding(.top, 8)
                    .padding(.bottom, 44)
            }
            
            expandButton
                .padding(.trailing, isExpanded ? 12 : 0)
                .padding(.bottom, isExpanded ? 12 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Not Found View
    
    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No lyrics available")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("Lyrics couldn't be found for this song")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Couldn't load lyrics")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func calculateCurrentLineIndex(lines: [SyncedLyricLine], time: Double) -> Int {
        var newIndex = 0
        for (index, line) in lines.enumerated() {
            if line.time <= time {
                newIndex = index
            } else {
                break
            }
        }
        return newIndex
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        LyricsView(
            lyricsState: .synced([
                SyncedLyricLine(time: 0, text: "First line of the song"),
                SyncedLyricLine(time: 3, text: "Second line coming up"),
                SyncedLyricLine(time: 6, text: "This is the current line playing"),
                SyncedLyricLine(time: 9, text: "Next line after this"),
                SyncedLyricLine(time: 12, text: "Another line in the song"),
                SyncedLyricLine(time: 15, text: "Keep singing along"),
                SyncedLyricLine(time: 18, text: "The music never stops"),
            ]),
            currentTime: 7,
            onSeek: { time in
                print("Seek to: \(time)")
            },
            isExpanded: false,
            onExpandToggle: {
                print("Toggle expand")
            }
        )
        .frame(width: 340, height: 360)
    }
}
