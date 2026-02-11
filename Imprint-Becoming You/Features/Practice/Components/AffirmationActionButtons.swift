//
//  AffirmationActionButtons.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - AffirmationActionButtons

/// Action buttons row displayed below affirmation text.
///
/// Contains Share and Favorite buttons arranged horizontally with consistent styling.
/// The `isEnabled` parameter controls interactivity without affecting appearance
/// during page transitions — buttons on non-current pages appear normal but don't respond.
///
/// ## Layout
/// Buttons are spaced with `AppTheme.Spacing.xxl + 8` to create visual breathing room.
/// Each button uses a VStack with icon + label for a compact vertical layout.
///
/// ## Integration
/// Used inside `AffirmationContentView` as part of the per-index affirmation card.
/// Also usable standalone in any context requiring share + favorite actions.
struct AffirmationActionButtons: View {

    // MARK: - Properties

    /// The affirmation to display actions for (used for favorite state).
    let affirmation: Affirmation

    /// Whether the buttons are interactive (current page only).
    let isEnabled: Bool

    /// Callback when share button is tapped.
    let onShare: () -> Void

    /// Callback when favorite button is toggled.
    let onToggleFavorite: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxl + 8) {
            // Share button
            shareButton

            // Favorite button
            FavoriteButton(
                isFavorited: affirmation.isFavorited,
                isEnabled: isEnabled,
                onToggle: onToggleFavorite
            )
        }
    }

    // MARK: - Share Button

    /// Share button with consistent styling to match FavoriteButton.
    private var shareButton: some View {
        Button {
            onShare()
            HapticFeedback.impact(.light)
        } label: {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 56, height: 56)

                Text("Share")
                    .font(AppTypography.caption1.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .accessibilityLabel("Share affirmation")
        .disabled(!isEnabled)
    }
}

// MARK: - Previews

#Preview("Action Buttons") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()

        AffirmationActionButtons(
            affirmation: Affirmation(
                text: "I am confident and capable",
                category: GoalCategory.confidence.rawValue
            ),
            isEnabled: true,
            onShare: {},
            onToggleFavorite: {}
        )
    }
    .previewEnvironment()
}
