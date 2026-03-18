//
//  LayoutContext.swift
//  Wavify
//
//  Layout environment for adaptive iPhone / iPad / Mac layouts
//

import SwiftUI

struct LayoutContext: Equatable {
    let isRegularWidth: Bool
    let isRegularHeight: Bool
    let isLandscape: Bool
    let containerWidth: CGFloat

    var isIPad: Bool { isRegularWidth && isRegularHeight }

    /// Wide screen: large iPad landscape or Mac window (> 1100pt)
    var isWide: Bool { containerWidth > 1100 }

    var gridColumns: Int {
        if isWide { return isLandscape ? 6 : 5 }
        if isRegularWidth { return isLandscape ? 4 : 3 }
        return 2
    }

    var carouselCardWidthFraction: CGFloat {
        if isWide { return isLandscape ? 0.35 : 0.45 }
        if isRegularWidth { return isLandscape ? 0.55 : 0.75 }
        return 0.85
    }

    /// Carousel card width capped at 600pt so cards don't become enormous on Mac
    var carouselCardWidth: CGFloat {
        min(containerWidth * carouselCardWidthFraction, 600)
    }

    // Carousel card heights (content-driven, not width-proportional)
    var categoryCardHeight: CGFloat {
        if isWide { return 460 }
        if isRegularWidth { return 440 }
        return 340
    }
    var chartCardHeight: CGFloat {
        if isWide { return 540 }
        if isRegularWidth { return 520 }
        return 390
    }

    var maxContentWidth: CGFloat { 700 }

    var detailHeaderHeight: CGFloat {
        isRegularWidth ? 500 : 420
    }

    var artistHeaderHeight: CGFloat {
        isRegularWidth ? 420 : 350
    }

    var recommendationItemWidth: CGFloat {
        if isWide { return 440 }
        if isRegularWidth { return 400 }
        return 280
    }

    var keepListeningCardWidth: CGFloat {
        if isWide { return 380 }
        if isRegularWidth { return 340 }
        return 220
    }

    // Thumbnails
    var thumbnailSmall: CGFloat { isRegularWidth ? 64 : 44 }
    var thumbnailMedium: CGFloat { isRegularWidth ? 96 : 64 }
    var thumbnailLarge: CGFloat { isRegularWidth ? 220 : 160 }

    // Grid row heights
    var favouriteRowHeight: CGFloat { isRegularWidth ? 80 : 56 }
    var recommendationRowHeight: CGFloat { isRegularWidth ? 76 : 56 }
    var keepListeningRowHeight: CGFloat { isRegularWidth ? 100 : 72 }

    // Carousel card sizes
    var shortsCardWidth: CGFloat {
        if isWide { return 280 }
        if isRegularWidth { return 250 }
        return 170
    }
    var shortsCardHeight: CGFloat {
        if isWide { return 470 }
        if isRegularWidth { return 420 }
        return 280
    }
    var homeSectionItemSize: CGFloat {
        if isWide { return 240 }
        if isRegularWidth { return 220 }
        return 160
    }
    var chartCardThumbnail: CGFloat { isRegularWidth ? 140 : 100 }

    // Section spacing
    var sectionSpacing: CGFloat { isRegularWidth ? 40 : 24 }

    // Fonts
    var fontBody: CGFloat { isRegularWidth ? 18 : 14 }
    var fontCaption: CGFloat { isRegularWidth ? 16 : 12 }
    var fontSmallCaption: CGFloat { isRegularWidth ? 15 : 11 }
    var fontCardTitle: CGFloat { isRegularWidth ? 17 : 13 }
    var fontHeadline: CGFloat { isRegularWidth ? 30 : 22 }
    var fontLargeHeadline: CGFloat { isRegularWidth ? 32 : 24 }
    var fontButton: CGFloat { isRegularWidth ? 17 : 14 }
    var fontButtonIcon: CGFloat { isRegularWidth ? 19 : 16 }

    // Button heights
    var buttonHeight: CGFloat { isRegularWidth ? 52 : 44 }

    // Detail page sizes
    var detailArtworkSize: CGFloat {
        if isWide { return 300 }
        if isRegularWidth { return 280 }
        return 200
    }
    var songRowImageSize: CGFloat { isRegularWidth ? 64 : 48 }
    var trackNumberWidth: CGFloat { isRegularWidth ? 36 : 28 }
    var detailButtonMaxWidth: CGFloat { isRegularWidth ? 500 : .infinity }
    var dividerLeading: CGFloat { isRegularWidth ? 66 : 50 }

    // Artist page sizes
    var artistCardSize: CGFloat { isRegularWidth ? 180 : 140 }
    var artistAvatarSize: CGFloat { isRegularWidth ? 130 : 100 }

    // Search page sizes
    var searchResultImageSize: CGFloat { isRegularWidth ? 72 : 56 }
    var fontSectionTitle: CGFloat { isRegularWidth ? 24 : 20 }
    var categoryBrowseHeight: CGFloat { isRegularWidth ? 130 : 100 }
}

private struct LayoutContextKey: EnvironmentKey {
    static let defaultValue = LayoutContext(
        isRegularWidth: false,
        isRegularHeight: false,
        isLandscape: false,
        containerWidth: 390
    )
}

extension EnvironmentValues {
    var layoutContext: LayoutContext {
        get { self[LayoutContextKey.self] }
        set { self[LayoutContextKey.self] = newValue }
    }
}
