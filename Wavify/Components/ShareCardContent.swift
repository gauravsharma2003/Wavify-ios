//
//  ShareCardContent.swift
//  Wavify
//
//  The visual card rendered both as a preview and via ImageRenderer for sharing.
//  IMPORTANT: No .glassEffect() — ImageRenderer cannot capture compositor effects.
//

import SwiftUI

struct ShareCardContent: View {
    let mode: ShareMode
    let songTitle: String
    let artistName: String
    let albumImage: UIImage?
    let selectedLyrics: [String]
    let colorOption: ShareColorOption
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    var cardCornerRadius: CGFloat = 20

    private var textColor: Color {
        colorOption.usesDarkText ? Color(white: 0.12) : .white
    }

    private var subtitleColor: Color {
        colorOption.usesDarkText ? Color(white: 0.3) : .white.opacity(0.7)
    }

    private var brandingColor: Color {
        colorOption.usesDarkText ? Color(white: 0.35) : .white.opacity(0.5)
    }

    var body: some View {
        if mode == .song {
            songCard
        } else {
            lyricsCard
        }
    }

    // Fixed square card for song mode
    private var songCard: some View {
        ZStack {
            colorOption.cardBackground(primary: primaryColor, secondary: secondaryColor, accent: accentColor)

            VStack(spacing: 0) {
                Spacer()
                songLayout
                Spacer()
                branding
            }
        }
        .frame(width: 350, height: 350)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    // Dynamic height card for lyrics mode — fits content tightly
    private var lyricsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            lyricsLayout
                .padding(.top, 24)

            branding
                .padding(.top, 20)
        }
        .frame(width: 350)
        .background {
            colorOption.cardBackground(primary: primaryColor, secondary: secondaryColor, accent: accentColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    // MARK: - Branding

    private var branding: some View {
        HStack(spacing: 5) {
            Spacer()
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("wavify")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(brandingColor)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: - Song Layout

    private var songLayout: some View {
        HStack(spacing: 16) {
            // Album Art
            if let image = albumImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(textColor.opacity(0.3))
                    }
            }

            // Song Info
            VStack(alignment: .leading, spacing: 6) {
                Text(songTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(artistName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Lyrics Layout

    private var lyricsLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Album art + song info at top-left
            lyricsSongHeader
                .padding(.bottom, 16)

            // Selected lyrics
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(selectedLyrics.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var lyricsSongHeader: some View {
        HStack(spacing: 10) {
            if let image = albumImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(textColor.opacity(0.3))
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(songTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Text(artistName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
        }
    }
}
