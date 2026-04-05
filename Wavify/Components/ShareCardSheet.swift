//
//  ShareCardSheet.swift
//  Wavify
//

import SwiftUI

struct ShareCardSheet: View {
    let song: Song
    let initialLyricsState: LyricsState
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let audioDuration: Double

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: ShareMode = .song
    @State private var selectedColor: ShareColorOption = .primary
    @State private var lyricsSelection = LyricsSelectionState()
    @State private var albumImage: UIImage? = nil
    @State private var isSharing = false
    @State private var localLyricsState: LyricsState = .idle
    @State private var showLyricsSelector = false
    @State private var selectLyricsPrompt = false

    private var lyricsAvailable: Bool {
        switch localLyricsState {
        case .synced(let lines): return !lines.isEmpty
        case .plain(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }

    private var isLyricsLoading: Bool {
        if case .loading = localLyricsState { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Always-visible mode toggle
            modePicker
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            if selectedMode == .lyrics && showLyricsSelector {
                // Full lyrics selector view
                lyricsSelectorFullView
            } else {
                // Card preview + colors + share
                cardFlow
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            localLyricsState = initialLyricsState
            // Start loading lyrics immediately if not already available
            if !lyricsAvailable && !isLyricsLoading {
                if case .notFound = localLyricsState {} else {
                    fetchLyrics()
                }
            }
        }
        .task {
            await loadAlbumImage()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.interactive())

            Spacer()

            Text("Share")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            // Invisible spacer to balance the header
            Color.clear.frame(width: 40, height: 40)
        }
    }

    // MARK: - Card Flow (preview + colors + share)

    private var cardFlow: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Card preview
                cardPreview
                    .scaleEffect(0.8)
                    .frame(height: selectedMode == .song ? 350 * 0.8 : nil)

                // Edit lyrics button (lyrics mode only, when lyrics selected)
                if selectedMode == .lyrics && lyricsSelection.hasSelection {
                    editLyricsButton
                        .padding(.horizontal, 20)
                }

                // Color picker (locked in lyrics mode until selection exists)
                colorPickerSection

                // Share CTA
                shareButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Lyrics Selector Full View

    private var lyricsSelectorFullView: some View {
        VStack(spacing: 16) {
            // Loading / not found / selector
            if isLyricsLoading {
                Spacer()
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading lyrics...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            } else if case .notFound = localLyricsState {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No lyrics available for this song")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                // Back to song mode
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = .song
                        showLyricsSelector = false
                    }
                } label: {
                    Text("Back to Song")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else if lyricsAvailable {
                Text("Select up to 6 lines")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 20)

                LyricsSelectionView(
                    lyricsState: localLyricsState,
                    selectionState: lyricsSelection
                )

                // Done button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if lyricsSelection.hasSelection {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLyricsSelector = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectLyricsPrompt = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { selectLyricsPrompt = false }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: lyricsSelection.hasSelection ? "checkmark" : "text.quote")
                            .font(.system(size: 14, weight: .semibold))
                        Text(lyricsSelection.hasSelection ? "Done" : "Select lyrics")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .overlay {
                    if selectLyricsPrompt {
                        Text("Tap a line to select it")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: .capsule)
                            .offset(y: -50)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
    }

    // MARK: - Mode Picker (Glass Toggle Tab Bar)

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(ShareMode.allCases, id: \.self) { mode in
                let isSelected = selectedMode == mode

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                    if mode == .lyrics {
                        if !lyricsAvailable && !isLyricsLoading {
                            if case .notFound = localLyricsState {} else {
                                fetchLyrics()
                            }
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLyricsSelector = true
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showLyricsSelector = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(mode.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        if mode == .lyrics && isLyricsLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                                .tint(isSelected ? .white : .white.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.white.opacity(0.15))
                        }
                    }
                }
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Card Preview

    private var cardPreview: some View {
        ShareCardContent(
            mode: selectedMode,
            songTitle: song.title,
            artistName: song.artist,
            albumImage: albumImage,
            selectedLyrics: selectedMode == .lyrics ? lyricsSelection.selectedTexts : [],
            colorOption: selectedColor,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            accentColor: accentColor
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .animation(.easeInOut(duration: 0.25), value: selectedColor)
        .animation(.easeInOut(duration: 0.25), value: selectedMode)
    }

    // MARK: - Edit Lyrics Button

    private var editLyricsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.25)) {
                showLyricsSelector = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .semibold))
                Text("Lyrics")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Color Picker Section

    private var colorPickerSection: some View {
        Group {
            if selectedMode == .lyrics && !lyricsSelection.hasSelection {
                // Locked colors — prompt to select lyrics
                ShareColorPicker(
                    selectedOption: $selectedColor,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor
                )
                .opacity(0.35)
                .allowsHitTesting(false)
            } else {
                ShareColorPicker(
                    selectedOption: $selectedColor,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor
                )
            }
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            renderAndShare()
        } label: {
            HStack(spacing: 8) {
                if isSharing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Share")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(isSharing || (selectedMode == .lyrics && !lyricsSelection.hasSelection))
        .opacity((selectedMode == .lyrics && !lyricsSelection.hasSelection) ? 0.5 : 1.0)
    }

    // MARK: - Lyrics Fetching

    private func fetchLyrics() {
        localLyricsState = .loading
        Task {
            let result = await LyricsService.shared.fetchLyrics(
                title: song.title,
                artist: song.artist,
                duration: audioDuration
            )
            if let synced = result.syncedLyrics, !synced.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    localLyricsState = .synced(synced)
                }
            } else if let plain = result.plainLyrics, !plain.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    localLyricsState = .plain(plain)
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    localLyricsState = .notFound
                }
            }
        }
    }

    // MARK: - Album Image Loading

    private func loadAlbumImage() async {
        guard let url = URL(string: ImageUtils.thumbnailForPlayer(song.thumbnailUrl)) else { return }

        // Fast memory check
        if let cached = ImageCache.shared.memoryCachedImage(for: url) {
            albumImage = cached
            return
        }

        // Full cache (memory + disk)
        if let cached = await ImageCache.shared.image(for: url) {
            albumImage = cached
            return
        }

        // Network fallback
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                albumImage = img
            }
        } catch {}
    }

    // MARK: - Render & Share

    @MainActor
    private func renderAndShare() {
        isSharing = true

        let selectedLyrics = selectedMode == .lyrics ? lyricsSelection.selectedTexts : []

        let cardView = ShareCardContent(
            mode: selectedMode,
            songTitle: song.title,
            artistName: song.artist,
            albumImage: albumImage,
            selectedLyrics: selectedLyrics,
            colorOption: selectedColor,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            accentColor: accentColor,
            cardCornerRadius: 0
        )

        let renderer = ImageRenderer(content: cardView)
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else {
            isSharing = false
            return
        }

        let shareURL = URL(string: "https://gauravsharma2003.github.io/wavifyapp/song/\(song.videoId)")

        var activityItems: [Any] = [image]
        if let url = shareURL { activityItems.append(url) }

        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(
                    x: topController.view.bounds.midX,
                    y: topController.view.bounds.midY,
                    width: 0, height: 0
                )
                popover.permittedArrowDirections = []
            }
            topController.present(activityVC, animated: true) {
                isSharing = false
            }
        } else {
            isSharing = false
        }
    }
}
