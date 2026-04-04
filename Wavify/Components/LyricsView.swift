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
    let isPlaying: Bool
    let onSeek: (Double) -> Void
    let isExpanded: Bool
    let onExpandToggle: () -> Void

    @State private var currentLineIndex: Int = 0
    @State private var isUserScrolling: Bool = false
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var showSyncButton: Bool = false

    // Time interpolation for 60fps-smooth karaoke (same pattern as NowPlayingProgressView)
    @State private var lastSyncTime: Double = 0
    @State private var lastSyncDate: Date = Date()

    init(
        lyricsState: LyricsState,
        currentTime: Double,
        isPlaying: Bool = false,
        onSeek: @escaping (Double) -> Void,
        isExpanded: Bool = false,
        onExpandToggle: @escaping () -> Void = {}
    ) {
        self.lyricsState = lyricsState
        self.currentTime = currentTime
        self.isPlaying = isPlaying
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

    // MARK: - Smooth Time Interpolation

    /// Predicts playback position between the 0.5s currentTime updates for smooth 60fps animation.
    private func smoothTime(at date: Date) -> Double {
        guard isPlaying else { return currentTime }
        let elapsed = date.timeIntervalSince(lastSyncDate)
        return max(0, lastSyncTime + elapsed)
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
                VStack(alignment: .leading, spacing: isExpanded ? 22 : 18) {
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
                // Sync interpolation anchor
                lastSyncTime = newTime
                lastSyncDate = Date()

                let newIndex = calculateCurrentLineIndex(lines: lines, time: newTime)

                if newIndex != currentLineIndex {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        currentLineIndex = newIndex
                    }
                }

                if !isUserScrolling, currentLineIndex < lines.count {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        proxy.scrollTo(lines[currentLineIndex].id, anchor: .init(x: 0.5, y: isExpanded ? 0.2 : 0.3))
                    }
                }
            }
            .onAppear {
                lastSyncTime = currentTime
                lastSyncDate = Date()
                currentLineIndex = calculateCurrentLineIndex(lines: lines, time: currentTime)
                if currentLineIndex < lines.count {
                    proxy.scrollTo(lines[currentLineIndex].id, anchor: .init(x: 0.5, y: isExpanded ? 0.2 : 0.3))
                }
            }
            .onChange(of: isExpanded) { _, _ in
                if currentLineIndex < lines.count {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
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
                .background(Color.black.opacity(0.001))
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

    // MARK: - Sync Button

    private func syncButtonView(proxy: ScrollViewProxy, lines: [SyncedLyricLine]) -> some View {
        Button {
            if currentLineIndex < lines.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
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
        let fontSize: CGFloat = isExpanded ? 28 : 26

        return Group {
            if isCurrent, let words = line.words, !words.isEmpty {
                // Word-by-word karaoke for current line
                karaokeLineView(words: words, fontSize: fontSize)
            } else {
                // Standard rendering for non-current lines or lines without word data
                Text(line.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .bloomGlow(radius: 6, intensity: 0.3, isActive: isCurrent)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isCurrent ? 1.0 : 0.98, anchor: .leading)
        .blur(radius: blurRadius(for: offset))
        .opacity(opacity(for: offset))
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: currentLineIndex)
        .contentShape(Rectangle())
    }

    // MARK: - Karaoke Word-by-Word View

    /// Apple Music-style word reveal using text-based masking.
    /// Two identical Text layers (dim + bright) where the bright layer is masked
    /// by a third Text with per-word/per-character foreground colors.
    /// Because all three use identical Text concatenation, they wrap identically,
    /// eliminating the multiline mask bleeding bug.
    private func karaokeLineView(words: [SyncedWord], fontSize: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isPlaying)) { timeline in
            let time = smoothTime(at: timeline.date)
            let dimText = buildDimText(words: words)
            let brightText = buildBrightText(words: words)
            let maskText = buildMaskText(words: words, at: time)

            ZStack(alignment: .topLeading) {
                // Layer 1: Dim base — all words at low opacity
                dimText
                    .font(.system(size: fontSize, weight: .bold))

                // Layer 2: Bloom glow — blurred bright text for self-illumination
                brightText
                    .font(.system(size: fontSize, weight: .bold))
                    .blur(radius: 8)
                    .opacity(0.3)
                    .mask(alignment: .topLeading) {
                        maskText.font(.system(size: fontSize, weight: .bold))
                    }

                // Layer 3: Sharp bright text — revealed by mask progress
                brightText
                    .font(.system(size: fontSize, weight: .bold))
                    .mask(alignment: .topLeading) {
                        maskText.font(.system(size: fontSize, weight: .bold))
                    }
            }
        }
    }

    // MARK: - Karaoke Text Builders

    /// All words at dim opacity (base layer visible underneath the bright reveal)
    private func buildDimText(words: [SyncedWord]) -> Text {
        var result = Text("")
        for (i, word) in words.enumerated() {
            let suffix = i < words.count - 1 ? " " : ""
            result = result + Text(word.text + suffix).foregroundColor(.white.opacity(0.3))
        }
        return result
    }

    /// All words at full brightness (masked by buildMaskText to reveal progressively)
    private func buildBrightText(words: [SyncedWord]) -> Text {
        var result = Text("")
        for (i, word) in words.enumerated() {
            let suffix = i < words.count - 1 ? " " : ""
            result = result + Text(word.text + suffix).foregroundColor(.white)
        }
        return result
    }

    /// The mask that controls what portion of brightText is visible.
    /// - Fully played words → white (opaque mask = reveals bright text)
    /// - Currently playing word → per-character opacity sweep
    /// - Unplayed words → clear (transparent mask = hides bright text)
    private func buildMaskText(words: [SyncedWord], at time: Double) -> Text {
        var result = Text("")
        for (i, word) in words.enumerated() {
            let suffix = i < words.count - 1 ? " " : ""
            let wp = wordProgressAt(word: word, time: time)

            if wp <= 0 {
                // Not yet reached
                result = result + Text(word.text + suffix).foregroundColor(.clear)
            } else if wp >= 1 {
                // Fully played
                result = result + Text(word.text + suffix).foregroundColor(.white)
            } else {
                // Currently playing — per-character sweep
                let chars = Array(word.text)
                let totalChars = CGFloat(chars.count)
                let charProgress = wp * totalChars

                for (ci, char) in chars.enumerated() {
                    let charOpacity = min(1.0, max(0.0, charProgress - CGFloat(ci)))
                    result = result + Text(String(char))
                        .foregroundColor(.white.opacity(charOpacity))
                }
                // Space after active word stays hidden
                result = result + Text(suffix).foregroundColor(.clear)
            }
        }
        return result
    }

    /// Progress of a single word at a given time: 0 = not started, 0→1 = playing, 1 = finished
    private func wordProgressAt(word: SyncedWord, time: Double) -> CGFloat {
        guard word.endTime > word.startTime else {
            return time >= word.startTime ? 1.0 : 0.0
        }
        let p = (time - word.startTime) / (word.endTime - word.startTime)
        return CGFloat(min(1.0, max(0.0, p)))
    }

    // MARK: - Blur and Opacity Helpers

    private func blurRadius(for offset: Int) -> CGFloat {
        switch abs(offset) {
        case 0:
            return 0
        case 1:
            return 0.5
        case 2:
            return 1.0
        default:
            return 1.5
        }
    }

    private func opacity(for offset: Int) -> Double {
        switch offset {
        case 0:
            return 1.0
        case -1:
            return 0.40
        case 1:
            return 0.50
        case -2:
            return 0.30
        case 2:
            return 0.35
        default:
            return 0.25
        }
    }

    // MARK: - Plain Lyrics View

    private func plainLyricsView(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.system(size: isExpanded ? 26 : 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isExpanded ? 16 : 0)
                .padding(.top, 8)
                .padding(.bottom, 60)
        }
        .overlay(alignment: .bottom) {
            HStack {
                Spacer()
                expandButton
            }
            .padding(.horizontal, isExpanded ? 16 : 8)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Not Found View

    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.word.spacing")
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
            isPlaying: true,
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
