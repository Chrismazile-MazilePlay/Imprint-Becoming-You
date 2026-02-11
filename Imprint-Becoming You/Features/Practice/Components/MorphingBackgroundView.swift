//
//  MorphingBackgroundView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - MorphingBackgroundView

/// Renders a category-driven gradient background that morphs during navigation.
///
/// ## Rendering Modes
/// - **At rest** (`|progress| < 0.01`): Static gradient for current category
/// - **During navigation** (`|progress| >= 0.01`): RGB-interpolated gradient between current and target
///
/// ## Color Morphing
/// Uses true RGB interpolation (not opacity crossfade) via `Color.interpolate(from:to:t:)`.
/// Each category maps to a `CategoryGradient` with primary and secondary colors.
/// The gradient composition is:
/// - `LinearGradient` from primary (30% opacity) to secondary
/// - `RadialGradient` overlay of primary (12% opacity) centered
///
/// ## Integration
/// This view is used as the `background` closure of `VerticalPager`, which passes
/// `(currentIndex, progress)` during drag gestures and auto-advance animations.
///
/// ## Accessibility
/// Background gradients are decorative and hidden from VoiceOver.
struct MorphingBackgroundView: View {

    // MARK: - Properties

    /// The affirmations array for category lookup by index.
    let affirmations: [Affirmation]

    /// The current page index in the vertical pager.
    let currentIndex: Int

    /// Drag progress from the vertical pager (-1.0 to 1.0).
    /// Positive = dragging toward next, negative = dragging toward previous.
    let progress: CGFloat

    /// Tracks the background category to display when at rest.
    /// Updated immediately (no animation) when index changes.
    @Binding var displayedCategory: GoalCategory?

    // MARK: - Body

    var body: some View {
        if abs(progress) < 0.01 {
            // At rest — show static background for current category
            staticBackground(for: displayedCategory)
        } else {
            // Active navigation — interpolate colors based on progress
            interpolatedBackground(currentIndex: currentIndex, progress: progress)
        }
    }

    // MARK: - Static Background

    /// Static background for a single category (used when at rest).
    @ViewBuilder
    private func staticBackground(for category: GoalCategory?) -> some View {
        let gradient = CategoryGradient.forCategory(category)

        ZStack {
            LinearGradient(
                colors: [gradient.primary.opacity(0.3), gradient.secondary],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [gradient.primary.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Interpolated Background

    /// Interpolated background using true RGB blending (used during navigation).
    @ViewBuilder
    private func interpolatedBackground(currentIndex: Int, progress: CGFloat) -> some View {
        let currentCategory = affirmation(at: currentIndex)?.goalCategory
        let targetCat = targetCategory(for: currentIndex, progress: progress)

        let currentGradient = CategoryGradient.forCategory(currentCategory)
        let targetGradient = CategoryGradient.forCategory(targetCat)

        // Use absolute progress for interpolation (0 to 1)
        let t = min(abs(progress), 1.0)

        // Interpolate primary and secondary colors
        let blendedPrimary = Color.interpolate(from: currentGradient.primary, to: targetGradient.primary, t: t)
        let blendedSecondary = Color.interpolate(from: currentGradient.secondary, to: targetGradient.secondary, t: t)

        ZStack {
            LinearGradient(
                colors: [blendedPrimary.opacity(0.3), blendedSecondary],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [blendedPrimary.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    /// Determines the target category based on drag direction.
    private func targetCategory(for currentIndex: Int, progress: CGFloat) -> GoalCategory? {
        let currentCategory = affirmation(at: currentIndex)?.goalCategory

        if progress > 0.05 && currentIndex < affirmations.count - 1 {
            return affirmation(at: currentIndex + 1)?.goalCategory
        } else if progress < -0.05 && currentIndex > 0 {
            return affirmation(at: currentIndex - 1)?.goalCategory
        } else {
            return currentCategory
        }
    }

    /// Safe array access for affirmation at index.
    private func affirmation(at index: Int) -> Affirmation? {
        guard affirmations.indices.contains(index) else { return nil }
        return affirmations[index]
    }
}

// MARK: - Previews

#Preview("Morphing Background - At Rest") {
    MorphingBackgroundView(
        affirmations: [],
        currentIndex: 0,
        progress: 0,
        displayedCategory: .constant(.confidence)
    )
}

#Preview("Morphing Background - During Drag") {
    MorphingBackgroundView(
        affirmations: [],
        currentIndex: 0,
        progress: 0.5,
        displayedCategory: .constant(.confidence)
    )
}
