//
//  HomeSectionView.swift
//  Wavify
//
//  Section wrapper for home page API sections with horizontal carousel
//

import SwiftUI

// MARK: - Home Section View
struct HomeSectionView: View {
    let section: HomeSection
    let namespace: Namespace.ID
    let onResultTap: (SearchResult) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                if let strapline = section.strapline {
                    Text(strapline)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                }
                Text(section.title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            
            // Content
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(section.items) { item in
                        ItemCard(
                            item: item,
                            namespace: namespace,
                            onTap: {
                                onResultTap(item)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Item Card (Standard carousel card)
struct ItemCard: View {
    let item: SearchResult
    let namespace: Namespace.ID
    let onTap: () -> Void
    
    // Helper to get high quality image
    private var highQualityThumbnailUrl: String {
        var p = item.thumbnailUrl
        if p.contains("w120-h120") {
             p = p.replacingOccurrences(of: "w120-h120", with: "w540-h540")
        } else if p.contains("w60-h60") {
             p = p.replacingOccurrences(of: "w60-h60", with: "w540-h540")
        } else if p.contains("s120") {
             p = p.replacingOccurrences(of: "s120", with: "s540")
        }
        return p
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                CachedAsyncImagePhase(url: URL(string: highQualityThumbnailUrl)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        Color.gray.opacity(0.3)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .matchedTransitionSource(id: (item.type == .album || item.type == .playlist) ? item.id : "non_hero_\(item.id)", in: namespace)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(item.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            .frame(width: 160)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip View
struct ChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color(white: 0.15))
                .foregroundColor(isSelected ? .black : .white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}
