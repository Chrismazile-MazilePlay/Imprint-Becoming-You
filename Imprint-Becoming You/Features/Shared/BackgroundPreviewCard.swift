//
//  BackgroundPreviewCard.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - BackgroundPreviewCard

/// Preview card for a background style in the selection grid.
///
/// Displays a rounded thumbnail showing the background appearance
/// with a label and selection indicator below.
///
/// ## Layout
/// - **Preview area**: 120pt tall rounded rect showing the background fill
/// - **Morphing gradient preview**: Miniature linear + radial gradient composite
/// - **Selection ring**: 2pt accent stroke on the preview when selected
/// - **Label**: Display name beneath the preview, tinted accent when selected
///
/// ## Accessibility
/// Each card is a single accessible element with label and selection state.
struct BackgroundPreviewCard: View {

    // MARK: - Properties

    /// The background style this card represents.
    let style: BackgroundStyle

    /// Whether this card is the currently selected option.
    let isSelected: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Preview area — rounded rect showing the background
            previewArea

            // Display name
            Text(style.displayName)
                .font(AppTypography.caption1)
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.displayName) background")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
            .fill(Color.clear)
            .frame(height: 120)
            .overlay {
                // Background fill
                Group {
                    if style.isMorphingGradient {
                        morphingGradientPreview
                    } else {
                        solidColorPreview
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(isSelected ? AppColors.accent : AppColors.textTertiary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
    }

    // MARK: - Morphing Gradient Preview

    /// Miniature version of the morphing gradient using the default category gradient.
    private var morphingGradientPreview: some View {
        let gradient = CategoryGradient.default
        return ZStack {
            LinearGradient(
                colors: [gradient.primary.opacity(0.3), gradient.secondary],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [gradient.primary.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 10,
                endRadius: 100
            )
        }
    }

    // MARK: - Solid Color Preview

    /// Solid color fill for non-gradient styles.
    private var solidColorPreview: some View {
        (style.solidColor ?? AppColors.backgroundPrimary)
    }
}

// MARK: - Previews

#Preview("Background Preview Card - Morphing Gradient (Selected)") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()

        BackgroundPreviewCard(
            style: .morphingGradient,
            isSelected: true
        )
        .frame(width: 170)
        .padding()
    }
}

#Preview("Background Preview Card - Solid (Unselected)") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()

        BackgroundPreviewCard(
            style: .solidDeepNavy,
            isSelected: false
        )
        .frame(width: 170)
        .padding()
    }
}

#Preview("Background Preview Card - Grid") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
            ForEach(BackgroundStyle.allCases) { style in
                BackgroundPreviewCard(
                    style: style,
                    isSelected: style == .morphingGradient
                )
            }
        }
        .padding()
    }
}
