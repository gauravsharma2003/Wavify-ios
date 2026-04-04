# Apple Music-Quality Synced Lyrics Karaoke Animation Plan

## Executive Summary

Fix three bugs (multiline mask bleeding, word snapping, static glow) and polish the karaoke animation to Apple Music quality in `LyricsView.swift` and `ShimmerModifier.swift`. The core architectural change replaces the Rectangle-based mask with a Text-based mask that wraps identically to content, and adds a `TimelineView` + time interpolation layer for 60fps-smooth animation despite 0.5s `currentTime` updates.

---

## Root Cause Analysis

### Bug 1: Multiline Mask Bleeding
- **File**: `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Components/LyricsView.swift`, lines 250-267
- **Root Cause**: `karaokeLineView` uses a `Rectangle` mask inside a `GeometryReader`. When text wraps to multiple lines, the rectangle spans the full height (`geo.size.height`) and reveals text on ALL lines simultaneously at the same horizontal position. A rectangle at 60% width reveals both line 1 and line 2 up to 60%.
- **Why it matters**: Most lyric lines with word-level timing are 6-10 words, which often wraps on iPhone screens at font size 26-28.

### Bug 2: Snapping/Stopping at Half Words
- **File**: `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Components/LyricsView.swift`, lines 285-306 and 258-266
- **Root Cause**: Two compounding issues:
  1. **Character-to-pixel inaccuracy**: `karaokeProgress()` maps character counts to a 0-1 ratio, but characters have wildly different widths ("W" vs "i" vs " "). The mask width `geo.size.width * progress` does not correspond to actual text positions.
  2. **Animation fighting**: `.animation(.easeOut(duration: 0.08), value: progress)` on the mask tries to animate between progress values. But `currentTime` updates arrive every **0.5 seconds** (from `PlaybackService.swift` line 551: `CMTime(seconds: 0.5, ...)`), meaning progress jumps in large discrete steps. The 0.08s ease-out animation starts, gets 16% through, then a new value arrives and restarts it, creating visible jitter/snapping.

### Bug 3: No Smooth Glow Effect
- **File**: `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Utilities/ShimmerModifier.swift`, lines 52-62
- **Root Cause**: `GlowModifier` applies two static `.shadow()` layers. Apple Music uses a self-illuminating bloom where the bright text itself appears to radiate light -- achieved by placing a blurred, semi-transparent copy of the text behind the sharp text.

### Additional Issue: 0.5s Update Frequency
- **File**: `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Services/Audio/PlaybackService.swift`, line 551
- `currentTime` updates every 0.5 seconds. For word-by-word karaoke (where individual words may be 0.2-0.5s long), this means 1-2 updates per word. Without interpolation, the animation visibly steps.
- **Solution**: The project already has an established pattern for this -- `TimelineView` + time interpolation (used in `NowPlayingProgressView.swift` lines 40-49 and `PlayerShell.swift` lines 1018-1050). Apply the same pattern to lyrics.

---

## Architecture Decision: Text-Based Mask

### Why Not Fix the Rectangle?
The Rectangle mask is fundamentally incompatible with multiline text. Possible workarounds (line-by-line rendering, measuring each line) all break SwiftUI's natural text wrapping and create new bugs around dynamic type, rotation, and layout. They also cannot solve the character-width inaccuracy.

### The Text-Based Mask Solution
Build the **mask itself** from `Text` concatenation with per-word/per-character `foregroundColor` set to `.white` (opaque, reveals) or `.clear` (transparent, hides). Since both content and mask layers use identical `Text` concatenation with the same font, they wrap identically at every screen width. This eliminates the multiline bug entirely and also eliminates the character-width-to-pixel mapping problem since the mask IS the text.

---

## Detailed Implementation Plan

### Phase 1: Add Smooth Time Interpolation to LyricsView

**File**: `LyricsView.swift`

**Step 1.1**: Add time interpolation state variables to `LyricsView`:

```swift
@State private var lastSyncTime: Double = 0
@State private var lastSyncDate: Date = Date()
```

**Step 1.2**: Add a `smoothTime(at:)` method that mirrors the pattern in `NowPlayingProgressView`:

```swift
private func smoothTime(at date: Date) -> Double {
    // When not playing, just return the last known time
    // When playing, predict current position by adding elapsed wall-clock time
    let elapsed = date.timeIntervalSince(lastSyncDate)
    let predicted = lastSyncTime + elapsed
    return max(0, predicted)
}
```

Note: We need access to `isPlaying` state. This requires adding a parameter or referencing the audio player. Since `LyricsView` currently only receives `currentTime: Double`, we have two options:
- **Option A (Minimal change)**: Always interpolate (predicted time = lastSyncTime + elapsed). When paused, `currentTime` stops changing, so `lastSyncTime` stays constant and `elapsed` grows but gets clamped by word boundaries. This is safe because `wordProgress()` already clamps to 0-1.
- **Option B (Clean)**: Add `isPlaying: Bool` parameter to `LyricsView`. 

**Recommendation**: Option B. Add `isPlaying: Bool` to `LyricsView` init. `PlayerShell` already has `audioPlayer.isPlaying` available.

**Step 1.3**: Wrap the karaoke content in a `TimelineView` for 60fps updates. The `TimelineView` should only be active for the current karaoke line.

**Step 1.4**: Update `onChange(of: currentTime)` to sync `lastSyncTime` and `lastSyncDate`:

```swift
.onChange(of: currentTime) { _, newTime in
    lastSyncTime = newTime
    lastSyncDate = Date()
    // ... existing line index logic
}
```

### Phase 2: Replace Rectangle Mask with Text Mask

**File**: `LyricsView.swift`

**Step 2.1**: Delete the existing `karaokeLineView` method (lines 245-267), `buildKaraokeText` (lines 273-281), and `karaokeProgress` (lines 285-306).

**Step 2.2**: Create a new `karaokeLineView` that uses `TimelineView` and text-based masking:

```swift
private func karaokeLineView(words: [SyncedWord], fontSize: CGFloat) -> some View {
    TimelineView(.animation(minimumInterval: 1.0/60, paused: !isPlaying)) { timeline in
        let time = smoothTime(at: timeline.date)
        
        let dimText = buildDimText(words: words)
        let maskText = buildMaskText(words: words, at: time)
        let brightText = buildBrightText(words: words)
        
        ZStack(alignment: .topLeading) {
            // Layer 1: Dim base (all words at ~30% opacity)
            dimText
                .font(.system(size: fontSize, weight: .bold))
            
            // Layer 2: Bloom glow (blurred bright text behind)
            brightText
                .font(.system(size: fontSize, weight: .bold))
                .blur(radius: 8)
                .opacity(0.3)
                .mask(alignment: .topLeading) {
                    maskText
                        .font(.system(size: fontSize, weight: .bold))
                }
            
            // Layer 3: Sharp bright text on top
            brightText
                .font(.system(size: fontSize, weight: .bold))
                .mask(alignment: .topLeading) {
                    maskText
                        .font(.system(size: fontSize, weight: .bold))
                }
        }
    }
}
```

**Step 2.3**: Implement `buildDimText`:

```swift
private func buildDimText(words: [SyncedWord]) -> Text {
    var result = Text("")
    for (i, word) in words.enumerated() {
        let suffix = i < words.count - 1 ? " " : ""
        result = result + Text(word.text + suffix)
            .foregroundColor(.white.opacity(0.3))
    }
    return result
}
```

**Step 2.4**: Implement `buildBrightText`:

```swift
private func buildBrightText(words: [SyncedWord]) -> Text {
    var result = Text("")
    for (i, word) in words.enumerated() {
        let suffix = i < words.count - 1 ? " " : ""
        result = result + Text(word.text + suffix)
            .foregroundColor(.white)
    }
    return result
}
```

**Step 2.5**: Implement `buildMaskText` -- the core innovation:

```swift
private func buildMaskText(words: [SyncedWord], at time: Double) -> Text {
    var result = Text("")
    for (i, word) in words.enumerated() {
        let suffix = i < words.count - 1 ? " " : ""
        let wp = wordProgressAt(word: word, time: time)
        
        if wp <= 0 {
            // Not yet reached: fully transparent mask (hides bright text)
            result = result + Text(word.text + suffix)
                .foregroundColor(.clear)
        } else if wp >= 1 {
            // Fully played: fully opaque mask (reveals bright text)
            result = result + Text(word.text + suffix)
                .foregroundColor(.white)
        } else {
            // Currently playing: per-character sweep
            let chars = Array(word.text)
            let totalChars = CGFloat(chars.count)
            let charProgress = wp * totalChars
            
            for (ci, char) in chars.enumerated() {
                let charOpacity = min(1.0, max(0.0, charProgress - CGFloat(ci)))
                result = result + Text(String(char))
                    .foregroundColor(.white.opacity(charOpacity))
            }
            // Space after active word is transparent
            result = result + Text(suffix).foregroundColor(.clear)
        }
    }
    return result
}
```

**Step 2.6**: Add `wordProgressAt` (time-parameterized version of the existing `wordProgress`):

```swift
private func wordProgressAt(word: SyncedWord, time: Double) -> CGFloat {
    guard word.endTime > word.startTime else {
        return time >= word.startTime ? 1.0 : 0.0
    }
    let p = (time - word.startTime) / (word.endTime - word.startTime)
    return CGFloat(min(1.0, max(0.0, p)))
}
```

Keep the existing `wordProgress(word:)` as it may still be used, or refactor it to call `wordProgressAt(word:, time: currentTime)`.

### Phase 3: Update Animation System

**File**: `LyricsView.swift`

**Step 3.1**: Remove the `.animation(.easeOut(duration: 0.08), value: progress)` -- this is now unnecessary since `TimelineView` drives updates at 60fps.

**Step 3.2**: Replace line transition animations with spring:

Change (line 129):
```swift
// OLD
withAnimation(.easeInOut(duration: 0.3)) {
    currentLineIndex = newIndex
}

// NEW
withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
    currentLineIndex = newIndex
}
```

**Step 3.3**: Replace scroll animations with spring:

Change (line 135):
```swift
// OLD
withAnimation(.easeInOut(duration: 0.45)) {
    proxy.scrollTo(lines[currentLineIndex].id, anchor: ...)
}

// NEW
withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
    proxy.scrollTo(lines[currentLineIndex].id, anchor: ...)
}
```

Apply the same spring animation to all `proxy.scrollTo` calls (lines 136, 148, 195).

**Step 3.4**: Replace the per-line `.animation()` modifier:

Change (line 237):
```swift
// OLD
.animation(.easeInOut(duration: 0.3), value: currentLineIndex)

// NEW
.animation(.spring(response: 0.4, dampingFraction: 0.78), value: currentLineIndex)
```

### Phase 4: Visual Polish - Opacity, Blur, and Glow

**File**: `LyricsView.swift`

**Step 4.1**: Update `opacity(for:)` to match Apple Music's graduated dimming:

```swift
private func opacity(for offset: Int) -> Double {
    switch abs(offset) {
    case 0:  return 1.0
    case 1:  return 0.45
    case 2:  return 0.35
    default: return 0.25
    }
}
```

Note: The current asymmetric opacity (previous lines dimmer than next) is non-standard. Apple Music uses symmetric dimming. If asymmetry is intentional for this app's design, keep it but adjust values:
```swift
private func opacity(for offset: Int) -> Double {
    switch offset {
    case 0:   return 1.0
    case -1:  return 0.40   // previous: slightly dimmer (already read)
    case 1:   return 0.50   // next: slightly brighter (coming up)
    case -2:  return 0.30
    case 2:   return 0.35
    default:  return 0.25
    }
}
```

**Step 4.2**: Update `blurRadius(for:)` for more pronounced depth:

```swift
private func blurRadius(for offset: Int) -> CGFloat {
    switch abs(offset) {
    case 0:  return 0
    case 1:  return 0.5
    case 2:  return 1.0
    default: return 1.5
    }
}
```

The current values (0.3, 0.5, 0.8) are too subtle. Apple Music has visible but not aggressive blur on non-current lines.

**Step 4.3**: Add subtle scale effect to `lyricLineView`. After the blur/opacity modifiers, add:

```swift
.scaleEffect(isCurrent ? 1.0 : 0.98, anchor: .leading)
```

This gives a subtle depth/prominence to the current line.

**Step 4.4**: Remove `.shimmer()` from non-karaoke current lines:

Change (line 229):
```swift
// OLD
.shimmer(isAnimating: isCurrent)
.glow(color: .white, radius: isCurrent ? 6 : 0, isActive: isCurrent)

// NEW -- no shimmer, just the bloom glow for current lines without word data
.glow(color: .white, radius: isCurrent ? 6 : 0, isActive: isCurrent)
```

Apple Music does NOT use shimmer on lyrics. The shimmer looks like a loading indicator rather than a karaoke effect.

### Phase 5: Bloom Glow Effect

**File**: `ShimmerModifier.swift`

**Step 5.1**: Add a new `BloomGlowModifier` that creates the self-illuminating look:

```swift
struct BloomGlowModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let isActive: Bool
    
    func body(content: Content) -> some View {
        if isActive {
            ZStack {
                // Bloom layer: blurred copy underneath
                content
                    .blur(radius: radius)
                    .opacity(opacity)
                
                // Sharp layer on top
                content
            }
        } else {
            content
        }
    }
}
```

**Step 5.2**: Add extension method:

```swift
extension View {
    func bloomGlow(radius: CGFloat = 8, opacity: Double = 0.35, isActive: Bool = true) -> some View {
        modifier(BloomGlowModifier(radius: radius, opacity: opacity, isActive: isActive))
    }
}
```

**Note**: For the karaoke line, the bloom is built directly into the ZStack (Phase 2, Step 2.2) with the blurred bright text layer, so `BloomGlowModifier` is primarily for non-karaoke current lines that lack word data. However, having it as a reusable modifier is good practice.

**Step 5.3**: For non-karaoke current lines, replace `.glow()` with `.bloomGlow()`:

```swift
// In lyricLineView, for lines without word data:
Text(line.text)
    .font(.system(size: fontSize, weight: .bold))
    .foregroundStyle(.white)
    .bloomGlow(radius: 6, opacity: 0.3, isActive: isCurrent)
```

### Phase 6: Add `isPlaying` Parameter

**File**: `LyricsView.swift`

**Step 6.1**: Add `isPlaying` to the struct properties:

```swift
struct LyricsView: View {
    let lyricsState: LyricsState
    let currentTime: Double
    let isPlaying: Bool          // <-- NEW
    let onSeek: (Double) -> Void
    let isExpanded: Bool
    let onExpandToggle: () -> Void
```

**Step 6.2**: Update the `init`:

```swift
init(
    lyricsState: LyricsState,
    currentTime: Double,
    isPlaying: Bool = false,     // <-- NEW
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
```

**File**: `PlayerShell.swift`

**Step 6.3**: Update all `LyricsView` instantiations to pass `isPlaying`:

At approximately line 581:
```swift
LyricsView(
    lyricsState: lyricsState,
    currentTime: audioPlayer.currentTime,
    isPlaying: audioPlayer.isPlaying,    // <-- NEW
    onSeek: { time in audioPlayer.seek(to: time) },
    isExpanded: lyricsExpanded,
    ...
)
```

At approximately line 928:
```swift
LyricsView(
    lyricsState: lyricsState,
    currentTime: audioPlayer.currentTime,
    isPlaying: audioPlayer.isPlaying,    // <-- NEW
    onSeek: { time in audioPlayer.seek(to: time) },
    isExpanded: true,
    ...
)
```

**Step 6.4**: Update the `#Preview` at the bottom of `LyricsView.swift` to include `isPlaying: true`.

### Phase 7: Ensure TimelineView Pauses Correctly

The `TimelineView` in `karaokeLineView` must pause when:
- `isPlaying` is false
- There is no active karaoke line

This is handled by:
```swift
TimelineView(.animation(minimumInterval: 1.0/60, paused: !isPlaying)) { ... }
```

When paused, `smoothTime(at:)` should return `currentTime` directly (not interpolate):
```swift
private func smoothTime(at date: Date) -> Double {
    guard isPlaying else { return currentTime }
    let elapsed = date.timeIntervalSince(lastSyncDate)
    return max(0, lastSyncTime + elapsed)
}
```

### Phase 8: Performance Considerations

**Concern**: Per-character Text concatenation in `buildMaskText` creates many `Text` objects. For a typical lyric line of ~40 characters, only 5-15 characters (the active word) need per-char breakdown. The rest are full-word `.white` or `.clear`. This is efficient because:
- Completed words: 1 Text object per word (not per char)
- Future words: 1 Text object per word
- Active word only: ~5-10 Text objects for characters
- Total per frame: ~15-20 Text objects (very lightweight for SwiftUI)

**Concern**: `TimelineView` at 60fps on the karaoke view. The `minimumInterval: 1.0/60` ensures we get smooth updates but SwiftUI's diffing means only the mask text opacity values change. The font/layout computation is cached.

**Concern**: Three overlapping Text layers (dim, bloom, bright). This is standard practice -- Apple's own lyrics view uses a similar layered approach. The bloom layer has `.blur()` which is GPU-accelerated via Core Image.

---

## File-by-File Change Summary

### `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Components/LyricsView.swift`

| Section | Change |
|---------|--------|
| Properties | Add `isPlaying: Bool`, `lastSyncTime`, `lastSyncDate` |
| init | Add `isPlaying` parameter |
| `syncedLyricsView` | Add `.onChange(of: currentTime)` handler to update sync state; change all `withAnimation(.easeInOut(...))` to `withAnimation(.spring(...))` |
| `lyricLineView` | Remove `.shimmer()`, add `.scaleEffect()`, change `.animation()` to spring |
| `karaokeLineView` | **Complete rewrite**: TimelineView + 3-layer ZStack (dim, bloom, bright+mask) |
| `buildKaraokeText` | **Delete** (replaced by buildDimText, buildBrightText, buildMaskText) |
| `karaokeProgress` | **Delete** (no longer needed) |
| `wordProgress` | Refactor to `wordProgressAt(word:time:)` |
| `buildDimText` | **New method** |
| `buildBrightText` | **New method** |
| `buildMaskText` | **New method** (per-character opacity for active word) |
| `smoothTime(at:)` | **New method** (time interpolation) |
| `blurRadius(for:)` | Update values: 0, 0.5, 1.0, 1.5 |
| `opacity(for:)` | Update values: 1.0, 0.45, 0.35, 0.25 |
| Preview | Add `isPlaying: true` |

### `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Utilities/ShimmerModifier.swift`

| Section | Change |
|---------|--------|
| `BloomGlowModifier` | **New struct**: creates layered blur+sharp effect |
| View extension | **New method**: `.bloomGlow(radius:opacity:isActive:)` |
| `LyricBlurModifier` | Consider updating values to match new LyricsView values (optional, since LyricsView uses its own inline functions) |

### `/Users/Gaurav.Sharma4/Desktop/Wavify/Wavify/Views/PlayerShell.swift`

| Section | Change |
|---------|--------|
| Line ~581 | Add `isPlaying: audioPlayer.isPlaying` to LyricsView init |
| Line ~928 | Add `isPlaying: audioPlayer.isPlaying` to LyricsView init |

---

## Implementation Order and Dependencies

```
Step 1: Add isPlaying parameter (Phase 6)
   ├── LyricsView.swift: add property + init param
   └── PlayerShell.swift: pass isPlaying at both call sites

Step 2: Add time interpolation (Phase 1)
   ├── LyricsView.swift: add lastSyncTime, lastSyncDate, smoothTime()
   └── LyricsView.swift: add onChange handler

Step 3: Replace mask system (Phase 2) [CORE BUG FIX]
   ├── Delete: karaokeProgress, buildKaraokeText
   ├── Add: buildDimText, buildBrightText, buildMaskText, wordProgressAt
   └── Rewrite: karaokeLineView with TimelineView + 3-layer ZStack

Step 4: Update animations (Phase 3)
   └── LyricsView.swift: all spring animation replacements

Step 5: Visual polish (Phase 4)
   ├── LyricsView.swift: opacity/blur/scale updates
   └── LyricsView.swift: remove shimmer from lyrics

Step 6: Bloom glow (Phase 5)
   ├── ShimmerModifier.swift: add BloomGlowModifier
   └── LyricsView.swift: use bloomGlow for non-karaoke lines
```

Steps 1-2 are prerequisites for Step 3. Steps 4-6 are independent polish that can be done in any order after Step 3.

---

## Edge Cases to Handle

1. **Lines without word data**: When `line.words` is nil (from LrcLib, KuGou, LyricsPlus providers that only provide line-level timing), fall back to the non-karaoke rendering. The current code already handles this at line 221.

2. **Zero-duration words**: When `word.endTime == word.startTime`, `wordProgressAt` returns 0 or 1 (binary). This is correct -- some TTML data has instantaneous words.

3. **Seeking**: When the user taps a line to seek, `currentTime` jumps. The `onChange(of: currentTime)` handler updates `lastSyncTime` and `lastSyncDate`, so `smoothTime` immediately snaps to the new position. No special handling needed.

4. **Very fast words** (< 0.1s): Per-character sweep still works because `TimelineView` updates at 60fps. A 0.1s word gets ~6 frames of animation, which is visually sufficient.

5. **Empty words**: The TTML parser already filters these out (TTMLParser.swift line 117: `if !text.isEmpty`).

6. **RTL text**: Not a concern for this app's lyrics sources (all provide LTR text). The `.topLeading` alignment handles this correctly.

---

## Testing Checklist

- [ ] Single-line lyrics: karaoke sweep works left-to-right
- [ ] Multi-line wrapping lyrics: sweep continues correctly to second line
- [ ] Fast songs (words < 0.3s): no visual glitches
- [ ] Slow songs (words > 2s): smooth intra-word sweep visible
- [ ] Pause/resume: animation stops/starts cleanly
- [ ] Seek (tap on line): animation snaps to correct position
- [ ] Lines without word data: fallback to non-karaoke render
- [ ] Expanded mode: all effects scale correctly at larger font
- [ ] Scroll interaction: user scroll disengages auto-scroll
- [ ] Memory: no leaks from TimelineView (verify with Instruments)
- [ ] Performance: smooth 60fps on iPhone 12+ (verify with frame rate monitor)

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Text concatenation performance with many characters | Low | Only active word uses per-char; rest are per-word |
| TimelineView battery drain | Low | Paused when not playing; 1/60 min interval |
| Bloom blur on older devices | Medium | The .blur(radius: 8) is GPU-accelerated; test on iPhone 11 |
| Spring animations feeling wrong | Low | Values chosen to match existing app patterns |
| Text wrapping mismatch between layers | Very Low | All layers use identical Text concatenation + same font |
