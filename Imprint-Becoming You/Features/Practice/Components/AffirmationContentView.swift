//
//  AffirmationContentView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - AffirmationContentView

/// A single affirmation page — category badge, auto-scrolling text, and action buttons.
///
/// ## Layout
/// The content is vertically centered between the floating HUD (top) and dock (bottom):
/// - `topPadding`: accounts for HUD height + vertical centering offset
/// - `bottomPadding`: accounts for dock offset (varies by session state)
/// - Two `Spacer()` views split remaining space equally around the text
///
/// ## Auto-Scrolling
/// The affirmation text auto-scrolls when `isScrollActive` is true. The `scrollGeneration`
/// counter resets scroll position on each new segment start.
///
/// ## Interaction
/// Action buttons (share + favorite) are always rendered for animation continuity,
/// but only respond to taps on the current page (`isCurrentPage`).
struct AffirmationContentView: View {

    // MARK: - Properties

    /// The affirmation to display.
    let affirmation: Affirmation

    /// Whether this page is the currently active page in the pager.
    let isCurrentPage: Bool

    /// Whether auto-scrolling should be active for this page.
    let isScrollActive: Bool

    /// Generation counter for scroll position reset.
    let scrollGeneration: Int

    /// Maximum height for the affirmation text before scrolling activates.
    let maxTextHeight: CGFloat

    /// Top padding to account for HUD and vertical centering.
    let topPadding: CGFloat

    /// Bottom padding to account for dock area.
    let bottomPadding: CGFloat

    /// Callback when share button is tapped.
    let onShare: () -> Void

    /// Callback when favorite button is toggled.
    let onToggleFavorite: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Category badge
            if let category = affirmation.goalCategory {
                CategoryBadge(category: category)
                    .padding(.bottom, AppTheme.Spacing.lg)
            }

            // Affirmation text — auto-scrolls long texts with fixed timing.
            // scrollGeneration guarantees position reset on every segment start.
            AutoScrollingAffirmationText(
                text: affirmation.text,
                isActive: isCurrentPage && isScrollActive,
                scrollGeneration: scrollGeneration,
                maxHeight: maxTextHeight
            )

            Spacer()

            // Action buttons — shown on ALL pages for unified animation.
            // Buttons animate together with text via ContentTransitionModifier.
            AffirmationActionButtons(
                affirmation: affirmation,
                isEnabled: isCurrentPage,
                onShare: onShare,
                onToggleFavorite: onToggleFavorite
            )
            .padding(.bottom, bottomPadding)
        }
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Affirmation Content") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()

        GeometryReader { geometry in
            AffirmationContentView(
                affirmation: Affirmation(
                    text: "I am confident and capable of achieving my goals",
                    category: GoalCategory.confidence.rawValue
                ),
                isCurrentPage: true,
                isScrollActive: false,
                scrollGeneration: 0,
                maxTextHeight: 300,
                topPadding: 100,
                bottomPadding: 120,
                onShare: {},
                onToggleFavorite: {}
            )
        }
    }
    .previewEnvironment()
}
