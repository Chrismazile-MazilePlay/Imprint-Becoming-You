//
//  AutoScrollingAffirmationText.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/4/26.
//

import SwiftUI

// MARK: - AutoScrollingAffirmationText

/// A text view that auto-scrolls long affirmations using a single smooth animation.
///
/// ## Scroll Control
///
/// Two complementary inputs control scrolling, each with a distinct responsibility:
///
/// - **`scrollGeneration`** — *Position authority.* When this value changes (segment
///   boundary), the scroll position is instantly reset to the top and a fresh scroll
///   sequence begins if `isActive` is true. Sourced from `PracticeStore.flowGeneration`,
///   which increments on every segment start. This guarantees the text is at the top
///   regardless of background/foreground transitions, loops, or mode switches.
///
/// - **`isActive`** — *Animation gate.* Controls intra-segment scroll state: start
///   scrolling when true, stop and smoothly reset when false. Handles phase transitions
///   within a segment (e.g., TTS → preparing → listening in Read & Speak mode).
///
/// ## Behavior
/// - **Short texts** (fit within `maxHeight`): Renders identically to a plain `Text` —
///   no clipping, scrolling, or visual artifacts. Completely transparent.
/// - **Long texts** (overflow `maxHeight`): Displays in a fixed-height window with
///   always-active edge fades. Scrolls automatically when `isActive` is `true`.
/// - **Segment boundary** (`scrollGeneration` changes): Smoothly scrolls back to top
///   via easeOut animation, then starts fresh scroll if `isActive` is true.
///   When the affirmation text also changes, `onChange(of: text)` overrides with
///   an instant reset (masked by the VerticalPager's page transition).
/// - **Deactivated** (`isActive` becomes `false`): Stops forward scroll, then smoothly
///   scrolls back to top with a TimelineView-driven easeOut deceleration (0.3–0.8s).
/// - **Reactivated** (`isActive` becomes `true`): If a scroll-back is in progress,
///   lets it complete naturally, then starts a fresh forward scroll. If no scroll-back
///   is active, starts a new scroll sequence with the standard delay.
///
/// ## Scroll Pacing
/// Uses a fixed **points-per-second** speed with a delay before scrolling starts.
/// No mode-specific configuration — every mode gets identical timing:
/// - **3.0 second delay** before scroll starts
/// - **15 pt/s** scroll speed
///
/// ## Gesture Immunity
/// Both forward scrolling and scroll-back are driven by `TimelineView(.animation)`,
/// computing the offset from elapsed time each frame. This makes both directions
/// completely immune to SwiftUI gesture transactions (e.g., VerticalPager's
/// `DragGesture`), which would otherwise interrupt `withAnimation` and cause
/// the text to jump.
///
/// ## Edge Fades
/// Uses `.mask` with **always-active gradients** — both top and bottom fades
/// are permanently on at full intensity. A reduced spacer (28pt) at the top
/// of the text content positions text below the most transparent part of the
/// fade zone, giving a natural fade-in appearance without excessive blank space.
///
/// ## Usage
/// ```swift
/// AutoScrollingAffirmationText(
///     text: affirmation.text,
///     isActive: isScrollActive,
///     scrollGeneration: store.flowGeneration,
///     maxHeight: 250
/// )
/// ```
struct AutoScrollingAffirmationText: View {
    
    // MARK: - Properties
    
    /// The full affirmation text to display
    let text: String
    
    /// Animation gate — controls intra-segment scroll state.
    ///
    /// Set to `true` during each mode's active content phase:
    /// - Read Aloud: TTS playing + complete (holds at bottom)
    /// - Read & Speak: TTS playing + user listening/speaking
    /// - Speak Only: user listening/speaking
    ///
    /// When `isActive` becomes `false`, the scroll stops and smoothly scrolls back
    /// to top via TimelineView-driven easeOut deceleration (0.3–0.8s).
    /// When `isActive` becomes `true`, if a scroll-back is in progress it completes
    /// naturally first, then a new scroll sequence begins (delay + linear).
    /// Does NOT handle segment-boundary resets — that's `scrollGeneration`'s job.
    let isActive: Bool

    /// Segment boundary token — sourced from `PracticeStore.flowGeneration`.
    ///
    /// When this value changes, the scroll smoothly animates back to the top
    /// (easeOut deceleration), then a fresh scroll sequence begins if `isActive`
    /// is true. When the affirmation text also changes, `onChange(of: text)`
    /// overrides with an instant reset (appropriate since different content appears).
    /// This token covers every segment-start path: first start, auto-advance,
    /// loop restart, background resume, mode switch, manual navigation,
    /// timeout retry, skip, saved session, and favorites.
    var scrollGeneration: Int = 0

    /// Maximum visible height before scrolling activates.
    /// When the natural text height exceeds this value, the view clips
    /// and enables auto-scroll. Short texts below this height render
    /// at their natural size with no constraint applied.
    let maxHeight: CGFloat
    
    /// Font applied to the text. Defaults to `AppTypography.affirmation`.
    var font: Font = AppTypography.affirmation
    
    /// Text foreground color. Defaults to `AppColors.textPrimary`.
    var textColor: Color = AppColors.textPrimary
    
    /// Text alignment. Defaults to `.center`.
    var alignment: TextAlignment = .center
    
    /// Horizontal padding applied to text content.
    /// Defaults to `AppTheme.Spacing.xl` to match existing practice layout.
    var horizontalPadding: CGFloat = AppTheme.Spacing.xl

    /// Number of words matched sequentially from the start during listening.
    ///
    /// When > 0, the text renders as an `AttributedString` with matched words
    /// colored `AppColors.accent` and unmatched words inheriting `textColor`.
    /// When 0 (default), the text renders as a plain `String` — zero overhead.
    var matchedWordCount: Int = 0
    
    // MARK: - State
    
    /// Natural (unconstrained) height of the plain text (without top spacer).
    ///
    /// Used to determine whether scrolling is needed. Measured via a hidden
    /// background `GeometryReader` that always renders the plain text.
    @State private var textHeight: CGFloat = 0
    
    /// Scroll offset used only for animated resets (easeOut back to top).
    ///
    /// During active scrolling, the offset is computed from `scrollStartTime`
    /// via `TimelineView` — this @State is NOT used for forward scrolling.
    /// This separation makes forward scrolling immune to gesture interruption.
    @State private var displayOffset: CGFloat = 0

    /// Timestamp when the forward scroll animation started (after delay).
    ///
    /// Non-nil means `TimelineView` is actively driving the scroll offset
    /// from elapsed time × `scrollSpeed`. Set to `nil` to stop the timeline
    /// and fall back to `displayOffset` for reset animations.
    @State private var scrollStartTime: Date?

    /// Task that manages the scroll delay before animation starts,
    /// or the scroll-back cleanup timer.
    @State private var scrollTask: Task<Void, Never>?

    /// Timestamp when the scroll-back-to-top animation started.
    ///
    /// Non-nil means `TimelineView` is actively driving the reverse scroll offset.
    /// The offset is computed from `scrollBackStartOffset` minus elapsed time
    /// through an easeOut curve. Set to `nil` when the reverse animation completes.
    @State private var scrollBackStartTime: Date?

    /// The scroll offset at the moment scroll-back started.
    ///
    /// Captured from the forward scroll position so the reverse animation
    /// starts seamlessly from wherever the text was. Used with `scrollBackStartTime`
    /// to compute the easeOut deceleration trajectory.
    @State private var scrollBackStartOffset: CGFloat = 0

    /// Whether to start a forward scroll after the current scroll-back completes.
    ///
    /// Set by `startScrolling()` when called during an in-flight scroll-back
    /// (e.g., `isActive` goes true while scroll-back is animating). The scroll-back
    /// cleanup Task checks this flag and calls `startScrolling()` if true, ensuring
    /// the text smoothly returns to top before beginning the next forward scroll.
    /// This prevents the jump caused by cancelling a mid-flight scroll-back.
    @State private var startScrollAfterScrollBack: Bool = false
    
    // MARK: - Configuration
    
    /// Height of each edge fade gradient.
    ///
    /// 56pt provides enough length for a 5-stop eased gradient that is
    /// imperceptible at onset and ramps smoothly to full fade.
    private let fadeHeight: CGFloat = 56
    
    /// Height of the top spacer inside scrollable content.
    ///
    /// Pushes text below the most transparent part of the top fade zone at rest.
    /// Set to half of `fadeHeight` — text starts at ~20% mask opacity, giving a
    /// natural fade-in appearance without excessive blank space above.
    private let topSpacerHeight: CGFloat = 28
    
    /// Seconds to wait before scrolling starts.
    ///
    /// Gives the user time to read the initially visible text before it begins moving.
    private let scrollDelay: TimeInterval = 3.0
    
    /// Scroll speed in points per second.
    ///
    /// Fixed rate ensures identical visual speed regardless of content length.
    /// Longer texts simply scroll for a longer duration.
    private let scrollSpeed: CGFloat = 15.0

    /// Minimum duration for the scroll-back-to-top animation (seconds).
    ///
    /// Applied when the current offset is small (< 50pt). Ensures the
    /// animation is always visible even for short distances.
    private let scrollBackMinDuration: TimeInterval = 0.3

    /// Maximum duration for the scroll-back-to-top animation (seconds).
    ///
    /// Caps the duration for very long texts where the offset could be
    /// 300–400pt. Keeps the UX snappy without excessive wait.
    private let scrollBackMaxDuration: TimeInterval = 0.8

    /// Reference offset for scaling scroll-back duration.
    ///
    /// At this offset, the scroll-back duration equals `scrollBackMaxDuration`.
    /// Offsets below this scale linearly down to `scrollBackMinDuration`.
    private let scrollBackReferenceOffset: CGFloat = 300.0
    
    // MARK: - Word Highlighting

    /// Ranges of each whitespace-delimited word in `text`.
    ///
    /// Computed once per `text` value and used by `highlightedText` to apply
    /// per-word foreground color via `AttributedString`. Preserves the original
    /// character ranges (including punctuation attached to words) so the
    /// highlighted text is visually identical to the plain text.
    private var wordRanges: [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            // Skip whitespace
            guard let wordStart = text[searchStart...].firstIndex(where: { !$0.isWhitespace }) else {
                break
            }
            // Find word end (next whitespace or end of string)
            let wordEnd = text[wordStart...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
            ranges.append(wordStart..<wordEnd)
            searchStart = wordEnd
        }

        return ranges
    }

    /// Builds an `AttributedString` with matched words colored `AppColors.accent`.
    ///
    /// Unmatched characters have no explicit foreground set, so they inherit
    /// the `textColor` from `.foregroundStyle()` on the parent `Text` view.
    /// This preserves visual parity — identical font, kerning, and layout.
    private var highlightedText: AttributedString {
        var attributed = AttributedString(text)
        let ranges = wordRanges
        let count = min(matchedWordCount, ranges.count)

        for i in 0..<count {
            let stringRange = ranges[i]
            // Convert String.Index range to AttributedString.Index range
            guard let attrStart = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let attrEnd = AttributedString.Index(stringRange.upperBound, within: attributed) else {
                continue
            }
            attributed[attrStart..<attrEnd].foregroundColor = UIColor(AppColors.accent)
        }

        return attributed
    }

    // MARK: - Computed Properties

    /// Whether the text overflows the visible window and requires scrolling.
    ///
    /// Compares the plain text height (without top spacer) against the window.
    private var needsScrolling: Bool {
        textHeight > maxHeight && maxHeight > 0
    }
    
    /// Maximum scroll offset before hitting the bottom of the text.
    ///
    /// The scrollable content height is `topSpacerHeight + textHeight` (spacer + text).
    /// Adding 35% of `fadeHeight` clears the dense part of the bottom gradient
    /// without leaving excessive empty space below the last line.
    private var maxScrollOffset: CGFloat {
        let scrollableHeight = topSpacerHeight + textHeight
        return max(scrollableHeight - maxHeight + fadeHeight * 0.5, 0)
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if needsScrolling {
                // Long text: constrained height with always-active edge fade mask.
                // The mask handles both clipping and fading in a single pass.
                //
                // TimelineView drives the scroll offset from elapsed time,
                // making it immune to parent gesture transactions.
                scrollableTextContent
                    .frame(height: maxHeight, alignment: .top)
                    .mask { edgeFadeMask }
            } else {
                // Short text: natural size, no constraint — parent Spacers handle centering
                plainTextView
            }
        }
        .background { textHeightMeasurer }
        .onChange(of: scrollGeneration) { _, _ in
            // Segment boundary — smooth scroll-back to top, then fresh scroll.
            //
            // Uses the same TimelineView-driven easeOut as stopScrolling() to
            // guarantee the text NEVER jumps. When a different affirmation appears,
            // onChange(of: text) also fires in the same frame and handles the
            // instant reset (masked by the VerticalPager's page transition).
            scrollTask?.cancel()
            scrollTask = nil

            // Capture current position from whichever phase is active.
            let currentOffset: CGFloat = {
                if let backStart = scrollBackStartTime {
                    // Mid-reverse: compute where we are in the scroll-back
                    let duration = scrollBackDuration(for: scrollBackStartOffset)
                    let elapsed = Date().timeIntervalSince(backStart)
                    let t = min(elapsed / duration, 1.0)
                    let easedT = 1.0 - (1.0 - t) * (1.0 - t)
                    return max(scrollBackStartOffset * CGFloat(1.0 - easedT), 0)
                }
                return captureCurrentForwardOffset()
            }()

            scrollStartTime = nil
            scrollBackStartTime = nil
            scrollBackStartOffset = 0

            guard currentOffset > 2 else {
                // Already at or near top — just reset and start fresh
                displayOffset = 0
                if isActive && needsScrolling {
                    startScrolling()
                }
                return
            }

            // Smooth scroll-back to top via TimelineView easeOut,
            // then start fresh forward scroll after animation completes.
            scrollBackStartOffset = currentOffset
            scrollBackStartTime = Date()

            let duration = scrollBackDuration(for: currentOffset)
            scrollTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration + 0.03))
                guard !Task.isCancelled else { return }
                scrollBackStartTime = nil
                scrollBackStartOffset = 0
                // Start fresh scroll after smooth return to top.
                // Also honor startScrollAfterScrollBack in case startScrolling()
                // was called during this scroll-back (e.g., isActive went true).
                if (isActive || startScrollAfterScrollBack) && needsScrolling {
                    startScrollAfterScrollBack = false
                    startScrolling()
                } else {
                    startScrollAfterScrollBack = false
                }
            }
        }
        .onChange(of: isActive) { _, active in
            // Intra-segment animation gate — handles phase transitions
            // within a segment (e.g., TTS → preparing → listening).
            if active {
                startScrolling()
            } else {
                stopScrolling()
            }
        }
        .onChange(of: text) { _, _ in
            // New affirmation — cancel everything and reset instantly.
            // Cancels forward scroll, scroll-back, pending delay tasks, and deferred flags.
            scrollTask?.cancel()
            scrollTask = nil
            scrollStartTime = nil
            scrollBackStartTime = nil
            scrollBackStartOffset = 0
            startScrollAfterScrollBack = false
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayOffset = 0
                textHeight = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        
    }
    
    // MARK: - Scroll Control
    
    /// Starts the scroll sequence: waits `scrollDelay`, then begins timeline-driven scroll.
    ///
    /// **Scroll-back safety:** If a scroll-back animation is in flight, this method
    /// does NOT cancel it. Instead, it sets `startScrollAfterScrollBack = true` so
    /// the scroll-back cleanup Task starts the forward scroll after the text has
    /// smoothly returned to the top. This prevents the visible jump caused by
    /// zeroing `scrollBackStartTime` mid-animation.
    ///
    /// Position reset is NOT this method's responsibility — callers handle that:
    /// - `onChange(of: scrollGeneration)` → smooth scroll-back (segment boundaries)
    /// - `stopScrolling()` → smooth easeOut reset (intra-segment transitions)
    ///
    /// Uses `TimelineView(.animation)` driven by `scrollStartTime` instead of
    /// `withAnimation(.linear)`. The offset is computed from elapsed time each frame,
    /// making it immune to SwiftUI gesture transactions that would otherwise interrupt
    /// implicit animations (e.g., VerticalPager's DragGesture causing text to jump).
    private func startScrolling() {
        // If a scroll-back is in progress, don't cancel it.
        // Instead, flag that a forward scroll should start after it completes.
        // This prevents the jump caused by zeroing scrollBackStartTime mid-animation.
        if scrollBackStartTime != nil {
            startScrollAfterScrollBack = true
            return
        }

        scrollTask?.cancel()
        scrollStartTime = nil
        startScrollAfterScrollBack = false
        guard needsScrolling else { return }

        let delay = scrollDelay

        scrollTask = Task { @MainActor in
            // Wait for delay before starting scroll
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            // Start the timeline-driven scroll.
            // TimelineView computes offset from Date() + elapsed × scrollSpeed.
            scrollStartTime = Date()
        }
    }
    
    /// Stops any pending/active scroll and smoothly scrolls back to top.
    ///
    /// **Scroll-back safety:** If a scroll-back is already in progress (e.g., started
    /// by `onChange(of: scrollGeneration)`), this method leaves it undisturbed — the
    /// existing scroll-back is already returning the text to the top.
    ///
    /// Otherwise, captures the current forward offset and initiates a TimelineView-driven
    /// reverse scroll with easeOut deceleration. Like forward scrolling, this is immune
    /// to SwiftUI gesture transactions because the offset is computed from elapsed time
    /// each frame rather than using `withAnimation`.
    ///
    /// A cleanup Task fires after the computed duration (+30ms buffer) to nil out
    /// `scrollBackStartTime`, pausing the timeline. The duration is deterministic:
    /// 0.3–0.8s depending on the captured offset distance.
    ///
    /// Skips animation for offsets ≤ 2pt (imperceptible) — resets directly.
    private func stopScrolling() {
        scrollTask?.cancel()
        scrollTask = nil

        // If a scroll-back is already in progress, leave it alone.
        // It's already returning the text to the top, which is what we want.
        // Clear the deferred-start flag since we're now stopping, not starting.
        // Re-schedule cleanup since we cancelled scrollTask above.
        if scrollBackStartTime != nil {
            startScrollAfterScrollBack = false
            let remaining = currentScrollBackOffset()
            let duration = scrollBackDuration(for: remaining)
            scrollTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration + 0.03))
                guard !Task.isCancelled else { return }
                scrollBackStartTime = nil
                scrollBackStartOffset = 0
                // Resume forward scroll if isActive is true.
                // This covers the case where isActive went true during scroll-back
                // but SwiftUI batched the onChange and startScrollAfterScrollBack
                // was already cleared.
                if (isActive || startScrollAfterScrollBack) && needsScrolling {
                    startScrollAfterScrollBack = false
                    startScrolling()
                } else {
                    startScrollAfterScrollBack = false
                }
            }
            scrollStartTime = nil
            return
        }

        let currentOffset = captureCurrentForwardOffset()
        scrollStartTime = nil

        // Skip animation for tiny offsets — not visible to the user.
        guard currentOffset > 2 else {
            scrollBackStartTime = nil
            scrollBackStartOffset = 0
            displayOffset = 0
            return
        }

        // Begin reverse scroll: TimelineView will compute easeOut offset
        // from scrollBackStartOffset back to 0 over the computed duration.
        scrollBackStartOffset = currentOffset
        scrollBackStartTime = Date()

        // Schedule cleanup after the animation completes.
        // Duration is deterministic (based on offset), +30ms buffer ensures
        // the final frame at offset 0 has rendered before we pause the timeline.
        let duration = scrollBackDuration(for: currentOffset)
        scrollTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.03))
            guard !Task.isCancelled else { return }
            scrollBackStartTime = nil
            scrollBackStartOffset = 0
            // Resume forward scroll if isActive is true after scroll-back completes.
            // Uses isActive directly (not just startScrollAfterScrollBack) because
            // SwiftUI may batch rapid isActive transitions (true→false→true) within
            // a single update cycle, causing onChange to not fire for the final true.
            // This ensures the forward scroll starts even when the flag wasn't set.
            if (isActive || startScrollAfterScrollBack) && needsScrolling {
                startScrollAfterScrollBack = false
                startScrolling()
            } else {
                startScrollAfterScrollBack = false
            }
        }
    }
    
    // MARK: - Text Content
    
    // MARK: - Timeline Helpers

    /// Whether the `TimelineView` should be actively ticking.
    ///
    /// True when either forward scrolling (`scrollStartTime`) or reverse
    /// scroll-back (`scrollBackStartTime`) is active. When false, the timeline
    /// is paused and the view falls back to `displayOffset`.
    private var isTimelineActive: Bool {
        scrollStartTime != nil || scrollBackStartTime != nil
    }

    /// Computes the scroll offset at a given point in time.
    ///
    /// Handles three phases in priority order:
    /// 1. **Reverse scroll** (`scrollBackStartTime` non-nil): Offset decelerates from
    ///    `scrollBackStartOffset` to 0 using a quadratic easeOut curve.
    /// 2. **Forward scroll** (`scrollStartTime` non-nil): Offset = elapsed × `scrollSpeed`,
    ///    capped at `maxScrollOffset`.
    /// 3. **Idle** (both nil): Falls back to `displayOffset` (0 after resets).
    private func currentScrollOffset(at date: Date) -> CGFloat {
        // Reverse scroll — easeOut deceleration back to top
        if let backStart = scrollBackStartTime {
            let duration = scrollBackDuration(for: scrollBackStartOffset)
            let elapsed = date.timeIntervalSince(backStart)
            let t = min(elapsed / duration, 1.0)

            // Quadratic easeOut: starts fast, decelerates to rest.
            // Same curve family as iOS return-to-origin animations.
            let easedT = 1.0 - (1.0 - t) * (1.0 - t)

            return max(scrollBackStartOffset * CGFloat(1.0 - easedT), 0)
        }

        // Forward scroll — linear from elapsed time
        guard let startTime = scrollStartTime else {
            return displayOffset
        }
        let elapsed = date.timeIntervalSince(startTime)
        return min(CGFloat(elapsed) * scrollSpeed, maxScrollOffset)
    }

    /// Computes the duration of the scroll-back animation based on the offset distance.
    ///
    /// Scales linearly from `scrollBackMinDuration` (at 0pt) to `scrollBackMaxDuration`
    /// (at `scrollBackReferenceOffset`). Clamped to the [min, max] range so very short
    /// distances still produce a visible animation and very long distances stay snappy.
    ///
    /// - Parameter offset: The starting offset in points
    /// - Returns: Duration in seconds
    private func scrollBackDuration(for offset: CGFloat) -> TimeInterval {
        guard offset > 0 else { return scrollBackMinDuration }
        let fraction = Double(offset) / Double(scrollBackReferenceOffset)
        let duration = scrollBackMinDuration + (scrollBackMaxDuration - scrollBackMinDuration) * fraction
        return min(max(duration, scrollBackMinDuration), scrollBackMaxDuration)
    }

    /// Captures the current forward scroll offset for use as a scroll-back starting point.
    ///
    /// Replicates the forward-scroll formula from `currentScrollOffset(at:)` using
    /// the current wall-clock time. Returns 0 if no forward scroll is active
    /// (e.g., still in the delay phase or already stopped).
    private func captureCurrentForwardOffset() -> CGFloat {
        guard let startTime = scrollStartTime else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime)
        return min(CGFloat(elapsed) * scrollSpeed, maxScrollOffset)
    }

    /// Captures the current reverse scroll offset for duration recalculation.
    ///
    /// Replicates the reverse-scroll formula from `currentScrollOffset(at:)` using
    /// the current wall-clock time. Returns 0 if no reverse scroll is active.
    /// Used by `stopScrolling()` to re-schedule a cleanup Task with the correct
    /// remaining duration when an existing scroll-back needs to continue.
    private func currentScrollBackOffset() -> CGFloat {
        guard let backStart = scrollBackStartTime else { return 0 }
        let duration = scrollBackDuration(for: scrollBackStartOffset)
        let elapsed = Date().timeIntervalSince(backStart)
        let t = min(elapsed / duration, 1.0)
        let easedT = 1.0 - (1.0 - t) * (1.0 - t)
        return max(scrollBackStartOffset * CGFloat(1.0 - easedT), 0)
    }

    // MARK: - Text Content

    /// The scrollable text view with top spacer and timeline-driven offset.
    ///
    /// Uses `TimelineView(.animation)` to compute the scroll offset from elapsed
    /// time each frame. This decouples the scroll from SwiftUI's animation system,
    /// making it immune to gesture transactions that would interrupt `withAnimation`.
    ///
    /// Includes a `topSpacerHeight`-sized spacer at the top so the first line of text
    /// starts below the most transparent part of the top fade zone when unscrolled.
    private var scrollableTextContent: some View {
        TimelineView(.animation(paused: !isTimelineActive)) { timeline in
            VStack(spacing: 0) {
                // Top spacer: pushes text below the most transparent part of the
                // top fade zone at rest. At 28pt (half of fadeHeight), the first line
                // starts at ~20% mask opacity — visible with a gentle fade-in.
                Spacer()
                    .frame(height: topSpacerHeight)

                plainTextView
            }
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -currentScrollOffset(at: timeline.date))
        }
    }
    
    /// Plain text view used for both short content and inside scrollable content.
    ///
    /// When `matchedWordCount > 0`, renders an `AttributedString` with per-word
    /// accent coloring. Otherwise renders a plain `String` (zero overhead path).
    /// Both paths use the same `Text` view with identical font, foreground style,
    /// alignment, and padding — preserving visual parity.
    private var plainTextView: some View {
        Group {
            if matchedWordCount > 0 {
                Text(highlightedText)
            } else {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(textColor)
        .multilineTextAlignment(alignment)
        .padding(.horizontal, horizontalPadding)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    /// Hidden text that measures the natural height without affecting layout.
    ///
    /// Always present as a background to provide accurate height data for the
    /// `needsScrolling` check. Measures plain text only (no spacer).
    private var textHeightMeasurer: some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(alignment)
            .padding(.horizontal, horizontalPadding)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: TextHeightPreferenceKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(TextHeightPreferenceKey.self) { height in
                textHeight = height
            }
    }
    
    // MARK: - Edge Fade Mask
    
    /// Mask that fades text at the top and bottom edges of the visible window.
    ///
    /// **Always-active gradients**: Both fades are permanently on at full intensity.
    /// The top `topSpacerHeight` spacer in `scrollableTextContent` positions text
    /// below the most transparent part of the fade zone, and the scroll offset math
    /// ensures text scrolls past the bottom fade zone.
    ///
    /// The 5-stop cubic ease-in curve concentrates most opacity change near the
    /// center edge where text transitions to fully visible, making the onset
    /// imperceptible.
    private var edgeFadeMask: some View {
        VStack(spacing: 0) {
            // Top edge fade: clear at outer edge → white at center edge
            LinearGradient(
                stops: topFadeStops,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            
            // Center: always fully visible
            Rectangle()
                .fill(.white)
            
            // Bottom edge fade: white at center edge → clear at outer edge
            LinearGradient(
                stops: bottomFadeStops,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
        }
    }
    
    /// Gradient stops for the top fade, following a cubic ease-in curve.
    ///
    /// Always at full intensity — clear at the outer edge, solid white at the center.
    private var topFadeStops: [Gradient.Stop] {
        [
            .init(color: .clear,               location: 0.00),  // outer edge
            .init(color: .white.opacity(0.03),  location: 0.25),
            .init(color: .white.opacity(0.20),  location: 0.50),
            .init(color: .white.opacity(0.60),  location: 0.75),
            .init(color: .white,                location: 1.00),  // center edge
        ]
    }
    
    /// Gradient stops for the bottom fade, following a cubic ease-in curve.
    ///
    /// Mirror of `topFadeStops` — solid white at center edge, clear at outer edge.
    private var bottomFadeStops: [Gradient.Stop] {
        [
            .init(color: .white,                location: 0.00),  // center edge
            .init(color: .white.opacity(0.60),  location: 0.25),
            .init(color: .white.opacity(0.20),  location: 0.50),
            .init(color: .white.opacity(0.03),  location: 0.75),
            .init(color: .clear,                location: 1.00),  // outer edge
        ]
    }
}

// MARK: - Preference Key

/// Captures the natural height of the text content for overflow detection.
private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

#Preview("Short Text - No Scrolling") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            AutoScrollingAffirmationText(
                text: "I am worthy of love and respect.",
                isActive: false,
                maxHeight: 200
            )
            Spacer()
        }
    }
}

#Preview("Long Text - Active Scrolling") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            AutoScrollingAffirmationText(
                text: "I am worthy of love and respect. Every day I grow stronger and more confident in my abilities. I embrace every opportunity that comes my way because I believe in my strength and resilience. The world is full of possibilities and I am ready to seize them all. My potential is limitless and I trust the journey that lies ahead of me. I release all negativity and welcome peace into my heart and mind.",
                isActive: true,
                maxHeight: 200
            )
            Spacer()
        }
    }
}

#Preview("Long Text - Interactive Toggle") {
    struct InteractiveDemo: View {
        @State private var isActive = false
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    AutoScrollingAffirmationText(
                        text: "I am worthy of love and respect. Every day I grow stronger and more confident in my abilities. I embrace every opportunity that comes my way because I believe in my strength and resilience. The world is full of possibilities and I am ready to seize them all. My potential is limitless and I trust the journey that lies ahead of me. I release all negativity and welcome peace into my heart and mind. I am grateful for everything I have and everything I am becoming.",
                        isActive: isActive,
                        maxHeight: 200
                    )
                    
                    Spacer()
                    
                    Button(isActive ? "Stop (resets to top)" : "Start Scrolling") {
                        isActive.toggle()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.bottom, 60)
                }
            }
        }
    }
    
    return InteractiveDemo()
}
