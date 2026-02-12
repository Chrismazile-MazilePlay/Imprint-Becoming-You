//
//  WordHighlightAffirmationText.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/11/26.
//

import SwiftUI

// MARK: - WordHighlightAffirmationText

/// Renders affirmation text with per-word highlighting driven by speech recognition.
///
/// Each word is rendered as a separate `Text` element within a `CenterAlignedFlowLayout`,
/// enabling independent color, scale, and glow animations as words are matched sequentially
/// during the listening phase.
///
/// ## Word Styling
/// - **Matched words**: Accent color with slight scale increase (1.08x), spring animation
/// - **Most recently matched**: Accent glow pulse via shadow + opacity animation
/// - **Unmatched words**: Dimmed secondary color (40% opacity)
///
/// ## Scrolling
/// For long affirmations that exceed `maxHeight`, the text is wrapped in a `ScrollViewReader`
/// with programmatic scrolling. When a new word highlights, the scroll position tracks
/// to keep the active word visible at center. Edge fades match `AutoScrollingAffirmationText`.
///
/// ## Usage
/// ```swift
/// WordHighlightAffirmationText(
///     text: "I am confident and strong",
///     matchedWordCount: 3,
///     maxHeight: 250
/// )
/// ```
struct WordHighlightAffirmationText: View {

    // MARK: - Properties

    /// The full affirmation text to display
    let text: String

    /// Number of words matched sequentially from the start (0 = none matched)
    let matchedWordCount: Int

    /// Maximum height before scrolling activates
    let maxHeight: CGFloat

    /// Font for each word
    var font: Font = AppTypography.affirmation

    /// Horizontal padding applied to the text content
    var horizontalPadding: CGFloat = AppTheme.Spacing.xl

    // MARK: - Private State

    /// Words split from the affirmation text (preserving display form)
    private var words: [String] {
        text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    /// Whether the content needs scrolling (determined by measuring natural height)
    @State private var needsScrolling = false

    /// Natural height of the content without scrolling constraint
    @State private var contentHeight: CGFloat = 0

    // MARK: - Body

    var body: some View {
        if needsScrolling {
            scrollableContent
        } else {
            staticContent
                .background(
                    // Measure natural height to determine if scrolling is needed
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            contentHeight = geometry.size.height
                            needsScrolling = contentHeight > maxHeight
                        }
                    }
                )
        }
    }

    // MARK: - Static Content (No Scroll)

    /// Renders words without scrolling for short affirmations
    private var staticContent: some View {
        wordFlowLayout
            .padding(.horizontal, horizontalPadding)
    }

    // MARK: - Scrollable Content

    /// Renders words in a scrollable container with edge fades for long affirmations
    private var scrollableContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                wordFlowLayout
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, edgeFadeHeight / 2)
                    .padding(.bottom, edgeFadeHeight / 2)
            }
            .frame(maxHeight: maxHeight)
            .mask(edgeFadeMask)
            .onChange(of: matchedWordCount) { _, newCount in
                // Scroll to keep the most recently matched word visible
                guard newCount > 0 else { return }
                let targetIndex = newCount - 1
                withAnimation(AppTheme.Animation.standard) {
                    proxy.scrollTo(targetIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Word Flow Layout

    /// The center-aligned flow layout containing all word views
    private var wordFlowLayout: some View {
        CenterAlignedFlowLayout(horizontalSpacing: wordSpacing, verticalSpacing: lineSpacing) {
            ForEach(words.indices, id: \.self) { index in
                WordView(
                    word: words[index],
                    index: index,
                    isMatched: index < matchedWordCount,
                    isMostRecent: index == matchedWordCount - 1,
                    font: font
                )
                .id(index)
            }
        }
    }

    // MARK: - Edge Fade Mask

    /// Height of the edge fade gradient zones
    private let edgeFadeHeight: CGFloat = 56

    /// Gradient mask for top and bottom edge fades (matches AutoScrollingAffirmationText)
    private var edgeFadeMask: some View {
        VStack(spacing: 0) {
            // Top fade
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.2), location: 0.25),
                    .init(color: .white.opacity(0.5), location: 0.5),
                    .init(color: .white.opacity(0.8), location: 0.75),
                    .init(color: .white, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: edgeFadeHeight)

            // Fully visible middle
            Rectangle()
                .fill(Color.white)

            // Bottom fade
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.8), location: 0.25),
                    .init(color: .white.opacity(0.5), location: 0.5),
                    .init(color: .white.opacity(0.2), location: 0.75),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: edgeFadeHeight)
        }
    }

    // MARK: - Layout Constants

    /// Horizontal spacing between words in the flow layout
    private let wordSpacing: CGFloat = 8

    /// Vertical spacing between lines in the flow layout
    private let lineSpacing: CGFloat = 8
}

// MARK: - Word View

/// A single word with highlight animation state.
///
/// Extracted as a sub-component for clean animation boundaries.
/// Each word independently animates its color, scale, and glow
/// based on its match state.
private struct WordView: View {

    let word: String
    let index: Int
    let isMatched: Bool
    let isMostRecent: Bool
    let font: Font

    /// Tracks the glow pulse for the most recently matched word
    @State private var isGlowing = false

    var body: some View {
        Text(word)
            .font(font)
            .foregroundStyle(isMatched ? AppColors.accent : AppColors.textSecondary.opacity(0.4))
            .scaleEffect(isMatched ? 1.08 : 1.0)
            .shadow(
                color: isMostRecent && isGlowing ? AppColors.accent.opacity(0.5) : .clear,
                radius: 12
            )
            .animation(AppTheme.Animation.bouncy, value: isMatched)
            .animation(AppTheme.Animation.standard, value: isMostRecent)
            .onChange(of: isMostRecent) { _, newValue in
                if newValue {
                    // Trigger glow pulse
                    isGlowing = true
                    // Fade glow after brief pulse
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(AppTheme.Animation.slow) {
                            isGlowing = false
                        }
                    }
                }
            }
            .accessibilityLabel(word)
            .accessibilityAddTraits(isMatched ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview("Short Text") {
    WordHighlightAffirmationText(
        text: "I am confident and strong",
        matchedWordCount: 3,
        maxHeight: 300
    )
    .frame(maxWidth: .infinity)
    .background(AppColors.backgroundPrimary)
}

#Preview("Long Text - Scrolling") {
    WordHighlightAffirmationText(
        text: "I understand the boundaries of others and set my own with grace and confidence because I am worthy of respect and love in all of my relationships",
        matchedWordCount: 8,
        maxHeight: 200
    )
    .frame(maxWidth: .infinity)
    .background(AppColors.backgroundPrimary)
}

#Preview("All Matched") {
    WordHighlightAffirmationText(
        text: "I am enough",
        matchedWordCount: 3,
        maxHeight: 300
    )
    .frame(maxWidth: .infinity)
    .background(AppColors.backgroundPrimary)
}
