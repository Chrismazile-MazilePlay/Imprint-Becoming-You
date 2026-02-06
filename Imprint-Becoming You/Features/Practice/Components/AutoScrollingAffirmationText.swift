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
/// ## Behavior
/// - **Short texts** (fit within `maxHeight`): Renders identically to a plain `Text` —
///   no clipping, scrolling, or visual artifacts. Completely transparent.
/// - **Long texts** (overflow `maxHeight`): Displays in a fixed-height window with
///   always-active edge fades. Scrolls automatically when `isActive` is `true`.
/// - **When deactivated** (`isActive` becomes `false`): If `resetsOnStop` is true,
///   smoothly scrolls back to the top. Otherwise stays at the current position.
///
/// ## Scroll Pacing
/// Uses a fixed **points-per-second** speed with a delay before scrolling starts.
/// No mode-specific configuration — every mode gets identical timing:
/// - **1.2 second delay** before scroll starts
/// - **30 pt/s** scroll speed
///
/// Scrolling uses a single `withAnimation(.linear)` call that SwiftUI interpolates
/// at the display refresh rate (60/120fps) — perfectly smooth with zero jitter.
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
///     isActive: isScrollActive,  // true when mode's primary phase is active
///     resetsOnStop: false,       // true by default
///     maxHeight: 250
/// )
/// ```
struct AutoScrollingAffirmationText: View {
    
    // MARK: - Properties
    
    /// The full affirmation text to display
    let text: String
    
    /// Whether auto-scrolling is active.
    ///
    /// Set to `true` during each mode's primary phase:
    /// - Read Aloud: TTS playing
    /// - Read & Speak: TTS playing
    /// - Speak Only: user listening/speaking
    let isActive: Bool
    
    /// Whether the scroll position resets to the top when `isActive` becomes `false`.
    ///
    /// - `true` (default): Read & Speak / Speak Only — resets so user can re-read from top
    /// - `false`: Read Aloud — stays scrolled during the hold/complete phase
    var resetsOnStop: Bool = true
    
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
    
    // MARK: - State
    
    /// Natural (unconstrained) height of the plain text (without top spacer).
    ///
    /// Used to determine whether scrolling is needed. Measured via a hidden
    /// background `GeometryReader` that always renders the plain text.
    @State private var textHeight: CGFloat = 0
    
    /// The actively displayed scroll offset.
    ///
    /// Animated via `withAnimation(.linear)` for perfectly smooth scrolling
    /// at the display refresh rate. No timer-based updates.
    @State private var displayOffset: CGFloat = 0
    
    /// Task that manages the scroll delay before animation starts.
    @State private var scrollTask: Task<Void, Never>?
    
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
                scrollableTextContent
                    .frame(height: maxHeight, alignment: .top)
                    .mask { edgeFadeMask }
            } else {
                // Short text: natural size, no constraint — parent Spacers handle centering
                plainTextView
            }
        }
        .background { textHeightMeasurer }
        .onChange(of: isActive) { _, active in
            if active {
                startScrolling()
            } else {
                stopScrolling()
            }
        }
        .onChange(of: text) { _, _ in
            // New affirmation — cancel any pending scroll and reset instantly
            scrollTask?.cancel()
            scrollTask = nil
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
    
    /// Starts the scroll sequence: waits `scrollDelay`, then animates to max offset.
    ///
    /// Uses a single `withAnimation(.linear)` call. SwiftUI interpolates at the
    /// display refresh rate (60/120fps) — perfectly smooth with zero jitter.
    /// Duration is `maxScrollOffset / scrollSpeed`, so visual speed is constant.
    private func startScrolling() {
        scrollTask?.cancel()
        guard needsScrolling else { return }
        
        let delay = scrollDelay
        let speed = scrollSpeed
        
        scrollTask = Task { @MainActor in
            // Wait for delay before starting scroll
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            
            // Single linear animation — SwiftUI handles all frame interpolation
            let duration = maxScrollOffset / speed
            withAnimation(.linear(duration: duration)) {
                displayOffset = maxScrollOffset
            }
        }
    }
    
    /// Stops any pending/active scroll and optionally resets to the top.
    private func stopScrolling() {
        scrollTask?.cancel()
        scrollTask = nil
        if resetsOnStop {
            withAnimation(.easeOut(duration: 0.25)) {
                displayOffset = 0
            }
        }
    }
    
    // MARK: - Text Content
    
    /// The scrollable text view with top spacer and offset for scrolling.
    ///
    /// Includes a `topSpacerHeight`-sized spacer at the top so the first line of text
    /// starts below the most transparent part of the top fade zone when unscrolled.
    /// This provides a natural fade-in appearance without excessive blank space.
    private var scrollableTextContent: some View {
        VStack(spacing: 0) {
            // Top spacer: pushes text below the most transparent part of the
            // top fade zone at rest. At 28pt (half of fadeHeight), the first line
            // starts at ~20% mask opacity — visible with a gentle fade-in.
            Spacer()
                .frame(height: topSpacerHeight)
            
            plainTextView
        }
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: -displayOffset)
    }
    
    /// Plain text view used for both short content and inside scrollable content.
    private var plainTextView: some View {
        Text(text)
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
