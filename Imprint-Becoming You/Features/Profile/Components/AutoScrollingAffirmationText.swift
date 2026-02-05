//
//  AutoScrollingAffirmationText.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/4/26.
//

import SwiftUI

// MARK: - AutoScrollingAffirmationText

/// A text view that auto-scrolls long affirmations in sync with TTS playback.
///
/// ## Behavior
/// - **Short texts** (fit within `maxHeight`): Renders identically to a plain `Text` —
///   no clipping, scrolling, or visual artifacts. Completely transparent.
/// - **Long texts** (overflow `maxHeight`): Displays in a fixed-height window with
///   edge fades. Scrolls automatically as TTS progress advances.
/// - **When TTS stops** (progress becomes `nil`): Smoothly scrolls back to the top
///   so the user can read the full text from the beginning (important for Read & Speak
///   listening phase). If the text changes before completion, the instant reset from
///   `onChange(of: text)` overrides the animation.
///
/// ## Scroll Pacing
/// Adapts to the caller's TTS progress range via `progressRange` parameter:
/// - **Read Aloud** (range 0.95): delay ~24%, scroll completes at progress 0.95
/// - **Read & Speak** (range 0.45): delay ~11%, scroll completes at progress 0.45
///
/// A 25% dead zone at the start of each range lets TTS speak the initially
/// visible text before scrolling begins.
///
/// ## Edge Fades
/// Uses `.mask` with a **static layout** — both top and bottom gradients are
/// always present at 56pt fixed height. Each gradient uses 5 eased stops that
/// follow a cubic ease-in curve for an imperceptible onset:
///
/// ```
/// Opacity ▲
///    1.0  │                    ●
///    0.7  │                 ●
///    0.3  │             ●
///    0.05 │        ●
///    0.0  │   ●
///         └──────────────────────▶ Distance
///            0    14   28   42  56pt
/// ```
///
/// The fade intensity animates via gradient stop opacity, not via conditional
/// view insertion — the layout never changes, eliminating any visible "setup" artifact.
///
/// ## Usage
/// ```swift
/// AutoScrollingAffirmationText(
///     text: affirmation.text,
///     progress: store.flow.ttsProgress,
///     progressRange: 0.95,  // or 0.45 for Read & Speak
///     maxHeight: 250
/// )
/// ```
struct AutoScrollingAffirmationText: View {
    
    // MARK: - Properties
    
    /// The full affirmation text to display
    let text: String
    
    /// TTS playback progress, or `nil` when not playing.
    /// Range depends on mode: 0.0–0.95 for Read Aloud, 0.0–0.45 for Read & Speak.
    let progress: Double?
    
    /// The maximum progress value the caller will send.
    ///
    /// Read Aloud caps at 0.95, Read & Speak caps at 0.45. The component scales
    /// its delay and scroll range proportionally so the full text scrolls
    /// regardless of mode.
    var progressRange: Double = 0.95
    
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
    
    /// Natural (unconstrained) height of the full text.
    /// Measured via a background `GeometryReader` on the text view.
    @State private var textHeight: CGFloat = 0
    
    /// The actively displayed scroll offset.
    ///
    /// Managed explicitly via `onChange` rather than computed, so that:
    /// - Progress updates animate smoothly toward the target
    /// - TTS completion (progress → nil) animates back to top
    /// - Text changes (new affirmation) reset instantly without animation
    @State private var displayOffset: CGFloat = 0
    
    // MARK: - Configuration
    
    /// Height of each edge fade gradient.
    ///
    /// 56pt provides enough length for a 5-stop eased gradient that is
    /// imperceptible at onset and ramps smoothly to full fade.
    private let fadeHeight: CGFloat = 56
    
    /// Fraction of `progressRange` that is a dead zone before scrolling begins.
    ///
    /// 25% of the range lets the user read the initially visible text while
    /// TTS speaks it, before scrolling starts.
    /// - Read Aloud (0.95 range): delay = 0.95 × 0.25 ≈ 0.24 (~2.4s at 10s duration)
    /// - Read & Speak (0.45 range): delay = 0.45 × 0.25 ≈ 0.11 (~1.1s at 10s duration)
    private let scrollDelayFraction: Double = 0.25
    
    // MARK: - Computed Properties
    
    /// Whether the text overflows the visible window and requires scrolling.
    private var needsScrolling: Bool {
        textHeight > maxHeight && maxHeight > 0
    }
    
    /// Maximum scroll offset before hitting the bottom of the text.
    ///
    /// Adds `fadeHeight` so the last line of text scrolls fully past the
    /// bottom fade zone into the clear center region.
    private var maxScrollOffset: CGFloat {
        max(textHeight - maxHeight + fadeHeight, 0)
    }
    
    /// Absolute progress value where scrolling begins.
    private var effectiveDelay: Double {
        progressRange * scrollDelayFraction
    }
    
    /// Top fade intensity (0 = no fade, 1 = full fade).
    ///
    /// Ramps over the first 40pt of scroll for a gradual onset that matches
    /// the multi-stop gradient's ease-in curve.
    private var topFadeAmount: Double {
        guard needsScrolling else { return 0 }
        return min(displayOffset / 40.0, 1.0)
    }
    
    /// Bottom fade intensity (0 = no fade, 1 = full fade).
    ///
    /// Ramps over the last 40pt of scroll for a gradual release.
    private var bottomFadeAmount: Double {
        guard needsScrolling else { return 0 }
        let remaining = maxScrollOffset - displayOffset
        return min(remaining / 40.0, 1.0)
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if needsScrolling {
                // Long text: constrained height with edge fade mask.
                // The mask handles both clipping and fading — no .clipped() needed.
                // Using .clipped() would create a hard edge BEFORE the mask, defeating
                // the smooth gradient fade.
                textContent
                    .frame(height: maxHeight, alignment: .top)
                    .mask { edgeFadeMask }
            } else {
                // Short text: natural size, no constraint — parent Spacers handle centering
                textContent
            }
        }
        .onChange(of: progress) { _, newValue in
            if let newValue {
                // TTS playing — scroll toward target
                withAnimation(.easeOut(duration: 0.35)) {
                    displayOffset = targetOffset(for: newValue)
                }
            } else {
                // TTS ended — smoothly return to top.
                // For Read & Speak: user sees text from top during listening phase.
                // For Read Aloud: auto-advance changes text shortly after, which
                //   triggers the instant reset below, overriding this animation.
                withAnimation(.easeInOut(duration: 0.4)) {
                    displayOffset = 0
                }
            }
        }
        .onChange(of: text) { _, _ in
            // New affirmation — reset instantly without animation
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
    
    // MARK: - Text Content
    
    /// The full text view with an offset applied for scrolling.
    ///
    /// Uses a background `GeometryReader` to capture the natural text height
    /// without affecting layout. The offset shifts the text upward as TTS
    /// progress advances.
    private var textContent: some View {
        Text(text)
            .font(font)
            .foregroundStyle(textColor)
            .multilineTextAlignment(alignment)
            .padding(.horizontal, horizontalPadding)
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: needsScrolling ? -displayOffset : 0)
            .background(textHeightMeasurer)
    }
    
    /// Invisible geometry reader that measures the natural text height.
    private var textHeightMeasurer: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: TextHeightPreferenceKey.self, value: geometry.size.height)
        }
        .onPreferenceChange(TextHeightPreferenceKey.self) { height in
            textHeight = height
        }
    }
    
    // MARK: - Edge Fade Mask
    
    /// Mask that fades text at the top and bottom edges of the visible window.
    ///
    /// **Static layout**: Both gradients are always rendered at 56pt fixed height
    /// with 5 stops following a cubic ease-in curve. Only the stop opacities change,
    /// driven by `topFadeAmount` / `bottomFadeAmount`. When fade amount is 0,
    /// all stops are `.white` (no fade). When fade amount is 1, stops follow
    /// the eased curve from `.clear` to `.white`.
    ///
    /// The ease-in curve concentrates most opacity change near the edge where
    /// text transitions to fully visible, making the onset of the fade
    /// imperceptible. This matches Apple's own fade implementations in
    /// ScrollView, Safari, and Music.
    private var edgeFadeMask: some View {
        VStack(spacing: 0) {
            // Top edge fade
            LinearGradient(
                stops: topFadeStops,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            
            // Center: always fully visible
            Rectangle()
                .fill(.white)
            
            // Bottom edge fade
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
    /// When `topFadeAmount` = 0: all stops are white (invisible mask).
    /// When `topFadeAmount` = 1: stops create a smooth fade from clear to white.
    ///
    /// The curve: `opacity = 1.0 - (fadeAmount × (1.0 - t³))` where t is position.
    /// This produces near-zero opacity change at the top edge (imperceptible onset)
    /// ramping to full opacity at the boundary with the center region.
    private var topFadeStops: [Gradient.Stop] {
        let f = topFadeAmount
        return [
            .init(color: .white.opacity(1.0 - f * 1.00), location: 0.00),  // outer edge
            .init(color: .white.opacity(1.0 - f * 0.97), location: 0.25),
            .init(color: .white.opacity(1.0 - f * 0.80), location: 0.50),
            .init(color: .white.opacity(1.0 - f * 0.40), location: 0.75),
            .init(color: .white.opacity(1.0),             location: 1.00),  // center edge
        ]
    }
    
    /// Gradient stops for the bottom fade, following a cubic ease-in curve.
    ///
    /// Mirror of `topFadeStops` — solid at top (center edge), fading at bottom (outer edge).
    private var bottomFadeStops: [Gradient.Stop] {
        let f = bottomFadeAmount
        return [
            .init(color: .white.opacity(1.0),             location: 0.00),  // center edge
            .init(color: .white.opacity(1.0 - f * 0.40), location: 0.25),
            .init(color: .white.opacity(1.0 - f * 0.80), location: 0.50),
            .init(color: .white.opacity(1.0 - f * 0.97), location: 0.75),
            .init(color: .white.opacity(1.0 - f * 1.00), location: 1.00),  // outer edge
        ]
    }
    
    // MARK: - Scroll Offset Calculation
    
    /// Computes the target scroll offset for a given TTS progress value.
    ///
    /// Applies a proportional dead zone at the start, then maps the remaining
    /// progress range linearly to the full scroll distance. The dead zone and
    /// cap scale automatically with `progressRange` so both Read Aloud (0.95)
    /// and Read & Speak (0.45) complete their full scroll:
    ///
    /// **Read Aloud** (range 0.95):
    /// - Progress 0.00–0.24: no scroll (dead zone)
    /// - Progress 0.24–0.95: scroll 0% → 100%
    ///
    /// **Read & Speak** (range 0.45):
    /// - Progress 0.00–0.11: no scroll (dead zone)
    /// - Progress 0.11–0.45: scroll 0% → 100%
    ///
    /// - Parameter progress: TTS playback progress
    /// - Returns: Pixel offset to apply as vertical scroll
    private func targetOffset(for progress: Double) -> CGFloat {
        guard needsScrolling else { return 0 }
        guard progress > effectiveDelay else { return 0 }
        
        // Map [effectiveDelay, progressRange] → [0.0, 1.0]
        let activeRange = progressRange - effectiveDelay
        guard activeRange > 0 else { return 0 }
        let normalized = min((progress - effectiveDelay) / activeRange, 1.0)
        
        return normalized * maxScrollOffset
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
                progress: nil,
                maxHeight: 200
            )
            Spacer()
        }
    }
}

#Preview("Long Text - Scrolling at 50%") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            AutoScrollingAffirmationText(
                text: "I am worthy of love and respect. Every day I grow stronger and more confident in my abilities. I embrace every opportunity that comes my way because I believe in my strength and resilience. The world is full of possibilities and I am ready to seize them all. My potential is limitless and I trust the journey that lies ahead of me. I release all negativity and welcome peace into my heart and mind.",
                progress: 0.5,
                maxHeight: 200
            )
            Spacer()
        }
    }
}

#Preview("Long Text - Interactive Progress") {
    struct InteractiveDemo: View {
        @State private var progress: Double = 0
        @State private var isPlaying = false
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    AutoScrollingAffirmationText(
                        text: "I am worthy of love and respect. Every day I grow stronger and more confident in my abilities. I embrace every opportunity that comes my way because I believe in my strength and resilience. The world is full of possibilities and I am ready to seize them all. My potential is limitless and I trust the journey that lies ahead of me. I release all negativity and welcome peace into my heart and mind. I am grateful for everything I have and everything I am becoming.",
                        progress: isPlaying ? progress : nil,
                        maxHeight: 200
                    )
                    
                    Spacer()
                    
                    VStack(spacing: 12) {
                        Text("Progress: \(Int(progress * 100))%")
                            .foregroundStyle(.white)
                        
                        Slider(value: $progress, in: 0...0.95)
                            .padding(.horizontal, 40)
                        
                        Button(isPlaying ? "Stop (resets to top)" : "Simulate TTS") {
                            isPlaying.toggle()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(.bottom, 60)
                }
            }
        }
    }
    
    return InteractiveDemo()
}
