# Card → Detail Zoom Transition — Implementation Guide

## Overview

This pattern creates a zoom animation where a card thumbnail morphs into a full-screen detail view on navigation push, and reverses on back. It uses SwiftUI's iOS 18+ `matchedTransitionSource` + `navigationTransition(.zoom(...))` APIs.

---

## Core Concept

Three pieces must agree on a shared `(id, namespace)` pair:

```
[Card Thumbnail] ──matchedTransitionSource(id, namespace)──┐
                                                            ├── SwiftUI matches these
[Detail View]    ──navigationTransition(.zoom(id, namespace))┘
```

---

## Step-by-Step Implementation

### 1. Declare a Namespace in the Parent View

The parent view that owns the `NavigationStack` creates the namespace. This is the shared coordinate space.

```swift
struct HomeView: View {
    @Namespace private var heroAnimation
    // ...
}
```

**Key rule:** The namespace must be declared at the `NavigationStack` level — not inside child views or list rows. One namespace per navigation stack.

### 2. Pass the Namespace Down to Card Views

Pass it as `Namespace.ID` (not `Namespace`) to child components:

```swift
struct ItemCard: View {
    let item: Item
    let namespace: Namespace.ID  // Not @Namespace — that's only for declaration
    // ...
}
```

### 3. Register the Source on the Card Thumbnail

Apply `.matchedTransitionSource` to the thumbnail image — not the entire card, not the button wrapper:

```swift
CachedAsyncImage(url: item.thumbnailUrl) { image in
    image.resizable().aspectRatio(contentMode: .fill)
}
.frame(width: 160, height: 160)
.clipShape(RoundedRectangle(cornerRadius: 12))
.matchedTransitionSource(id: item.id, in: namespace)  // <- on the image
```

### 4. Apply the Zoom Transition on the Destination

Inside `.navigationDestination`, apply `.navigationTransition(.zoom(...))` to the destination view. The `sourceID` must match the `id` used in step 3:

```swift
.navigationDestination(for: NavigationDestination.self) { destination in
    switch destination {
    case .album(let id, let name, let artist, let thumbnail):
        AlbumDetailView(albumId: id, ...)
            .navigationTransition(.zoom(sourceID: id, in: heroAnimation))
    }
}
```

### 5. Trigger Navigation via the Path

Push a value onto the `NavigationStack`'s path. SwiftUI automatically handles the animation:

```swift
navigationPath.append(NavigationDestination.album(item.id, item.name, ...))
```

---

## Edge Cases & Bugs You Will Hit

### 1. Images Disappear After Returning (iOS 18 Bug)

**Problem:** After the zoom-back animation completes, the source card's image becomes invisible. The view is still there (tappable), but renders as blank.

**Cause:** SwiftUI fails to properly restore the image view after the matched transition completes.

**Fix:** Force-recreate the image view by changing its identity when the detail view disappears:

```swift
// Parent view
@State private var heroRefreshId = UUID()

// On the card thumbnail
.id(heroRefreshId)
.matchedTransitionSource(id: item.id, in: namespace)

// On the destination
AlbumDetailView(...)
    .navigationTransition(.zoom(sourceID: id, in: heroAnimation))
    .onDisappear {
        heroRefreshId = UUID()  // Forces SwiftUI to recreate all source images
    }
```

**Trade-off:** This recreates ALL card images in the list, not just the one that was tapped. Acceptable for small lists; for very large lists, consider scoping the refresh ID per-item.

### 2. Rapid Double-Tap Causes Glitchy Animation

**Problem:** If a user taps a card, goes back, and immediately taps the same card again, the zoom animation glitches — the thumbnail may not be in its final resting position yet.

**Fix:** Add a cooldown that blocks re-navigation to the same item for ~2 seconds:

```swift
// In your NavigationManager or similar
private var lastNavigatedId: String?
private var lastNavigatedTime: Date?
private let cooldownDuration: TimeInterval = 2.0

func isInCooldown(id: String) -> Bool {
    guard lastNavigatedId == id,
          let lastTime = lastNavigatedTime else { return false }
    return Date().timeIntervalSince(lastTime) < cooldownDuration
}

func recordClose(id: String) {
    lastNavigatedId = id
    lastNavigatedTime = Date()
}
```

Usage:
```swift
// Before navigating
guard !navigationManager.isInCooldown(id: item.id) else { return }
navigationPath.append(...)

// When detail disappears
.onDisappear {
    navigationManager.recordClose(id: id)
}
```

### 3. Not All Item Types Should Zoom

**Problem:** If you apply the hero transition to every item (songs, artists, albums), items that navigate differently (e.g., songs just play inline) will cause a mismatched or broken animation.

**Fix:** Use a conditional ID. Items that shouldn't animate get a dummy ID that will never match any destination:

```swift
.matchedTransitionSource(
    id: item.shouldHeroAnimate ? item.id : "non_hero_\(item.id)",
    in: namespace
)
```

Since no destination ever declares `.navigationTransition(.zoom(sourceID: "non_hero_...", ...))`, SwiftUI falls back to the default push transition.

### 4. Same Item ID Appears Multiple Times on Screen

**Problem:** If the same album/playlist card appears in two different sections simultaneously, both thumbnails register the same `(id, namespace)` pair. SwiftUI picks one arbitrarily, causing the animation to zoom from the wrong card.

**Fix options:**
- Deduplicate items across sections so the same ID never appears twice
- Use a composite ID: `"\(section.id)_\(item.id)"` — but then the destination must also use the same composite ID, which means you need to know which section triggered the navigation

### 5. LazyHStack / LazyVGrid Deallocation

**Problem:** In a `LazyHStack` or `LazyVGrid`, if the user scrolls the card off-screen before the detail view appears, the source view gets deallocated. The zoom animation has no source to animate from and falls back to a standard push.

**Mitigation:** This is mostly a non-issue in practice — navigation happens fast enough. But if you have very large lazy containers with slow loading, consider using an eager `HStack` for small item counts.

### 6. Namespace Must Not Cross NavigationStack Boundaries

**Problem:** If you have nested `NavigationStack`s (e.g., in a `TabView`), a namespace from one stack cannot be used in another. The source and destination must be in the same `NavigationStack`.

**Fix:** Declare one namespace per `NavigationStack`. If a `CategoryDetailView` is pushed inside the same stack and has its own `.navigationDestination`, pass the namespace down:

```swift
// Parent pushes CategoryDetailView with the namespace
CategoryDetailView(
    title: title,
    endpoint: endpoint,
    namespace: heroAnimation,  // Pass it through
    audioPlayer: audioPlayer
)

// CategoryDetailView uses it in its own .navigationDestination
.navigationTransition(.zoom(sourceID: id, in: namespace))
```

### 7. clipShape Must Be Applied BEFORE matchedTransitionSource

**Problem:** If you apply `.matchedTransitionSource` before `.clipShape`, the zoom animation uses the uncropped frame, causing a visual jump.

**Correct order:**
```swift
image
    .frame(width: 160, height: 160)
    .clipShape(RoundedRectangle(cornerRadius: 12))  // First
    .matchedTransitionSource(id: item.id, in: namespace)  // After
```

---

## Minimal Complete Example

```swift
import SwiftUI

// MARK: - Data
enum Destination: Hashable {
    case detail(id: String, title: String)
}

// MARK: - Root
struct ContentView: View {
    @Namespace private var hero
    @State private var path: [Destination] = []
    @State private var refreshId = UUID()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack {
                    ForEach(items) { item in
                        Button {
                            path.append(.detail(id: item.id, title: item.title))
                        } label: {
                            AsyncImage(url: item.imageURL)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .id(refreshId)
                                .matchedTransitionSource(id: item.id, in: hero)
                        }
                    }
                }
            }
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .detail(let id, let title):
                    DetailView(title: title)
                        .navigationTransition(.zoom(sourceID: id, in: hero))
                        .onDisappear { refreshId = UUID() }
                }
            }
        }
    }
}
```

---

## Checklist

- [ ] `@Namespace` declared at the `NavigationStack` owner level
- [ ] Namespace passed as `Namespace.ID` to child views
- [ ] `.matchedTransitionSource(id:in:)` applied to the **thumbnail image**, after `clipShape`
- [ ] `.navigationTransition(.zoom(sourceID:in:))` applied to the **destination view**
- [ ] IDs match between source and destination
- [ ] `refreshId` workaround for iOS 18 image disappearance bug
- [ ] Cooldown guard to prevent rapid double-tap glitches
- [ ] Conditional IDs for items that shouldn't zoom (e.g., songs)
- [ ] Namespace not shared across different `NavigationStack` boundaries
