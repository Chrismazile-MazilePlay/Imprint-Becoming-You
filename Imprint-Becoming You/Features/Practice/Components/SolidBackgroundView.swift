//
//  SolidBackgroundView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - SolidBackgroundView

/// Renders a solid color background for user-selected background styles.
///
/// Used when the user selects a non-gradient background option from
/// the Background settings in Profile. Falls back to `AppColors.backgroundPrimary`
/// if the style has no associated solid color.
///
/// ## Integration
/// This view replaces `MorphingBackgroundView` inside `PracticePageViewBuilder`
/// when the user's `BackgroundStyle` is not `.morphingGradient`.
///
/// ## Accessibility
/// Background is decorative and hidden from VoiceOver.
struct SolidBackgroundView: View {

    // MARK: - Properties

    /// The background style to render.
    let style: BackgroundStyle

    // MARK: - Body

    var body: some View {
        (style.solidColor ?? AppColors.backgroundPrimary)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Solid Background - Charcoal") {
    SolidBackgroundView(style: .solidCharcoal)
}

#Preview("Solid Background - Deep Navy") {
    SolidBackgroundView(style: .solidDeepNavy)
}

#Preview("Solid Background - Deep Plum") {
    SolidBackgroundView(style: .solidDeepPlum)
}
