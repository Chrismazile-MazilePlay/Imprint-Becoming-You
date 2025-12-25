//
//  AffirmationContentView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - AffirmationContentView

/// The scrollable content layer for affirmation display.
///
/// This view contains only the elements that move during vertical swiping:
/// - Category badge
/// - Affirmation text
/// - Action buttons (favorite, share)
///
/// The background is handled separately by `AffirmationBackgroundView`.
///
/// ## Transition Behavior
/// Content slides vertically with the gesture, then animates to snap position.
/// Old content slides out while new content slides in from the opposite direction.
struct AffirmationContentView: View {
    
    // MARK: - Properties
    
    /// The affirmation to display
    let affirmation: Affirmation
    
    /// Current vertical offset from gesture
    let dragOffset: CGFloat
    
    /// Direction of exit animation (-1 for up, 1 for down, 0 for none)
    let exitDirection: Int
    
    /// Whether this is the incoming (next/previous) content
    let isIncoming: Bool
    
    /// Callback when favorite button is tapped
    let onFavoriteTap: () -> Void
    
    /// Callback when share button is tapped
    let onShareTap: () -> Void
    
    // MARK: - Environment
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // MARK: - State
    
    @State private var hasAppeared = false
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                // Category badge
                if let category = affirmation.goalCategory {
                    CategoryBadge(category: category)
                        .padding(.bottom, AppTheme.Spacing.lg)
                }
                
                // Affirmation text
                Text(affirmation.text)
                    .font(AppTypography.affirmation)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                
                Spacer()
                
                // Action buttons
                actionButtons
                    .padding(.bottom, AppTheme.Spacing.xxl + 100) // Space for dock
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: computedOffset(screenHeight: geometry.size.height))
            .opacity(computedOpacity)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(AppTheme.Animation.standard) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Affirmation: \(affirmation.text)")
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            // Favorite button
            Button {
                onFavoriteTap()
            } label: {
                Image(systemName: affirmation.isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(affirmation.isFavorited ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: Constants.Layout.minimumTouchTarget, height: Constants.Layout.minimumTouchTarget)
            }
            .accessibilityLabel(affirmation.isFavorited ? "Remove from favorites" : "Add to favorites")
            
            // Share button
            Button {
                onShareTap()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: Constants.Layout.minimumTouchTarget, height: Constants.Layout.minimumTouchTarget)
            }
            .accessibilityLabel("Share affirmation")
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
    
    // MARK: - Computed Animation Values
    
    /// Computes the Y offset based on drag state and transition direction
    private func computedOffset(screenHeight: CGFloat) -> CGFloat {
        if isIncoming {
            // Incoming content: starts off-screen, moves toward center
            let startOffset = exitDirection < 0 ? screenHeight : -screenHeight
            let progress = hasAppeared ? 0 : 1
            return CGFloat(progress) * startOffset + dragOffset
        } else {
            // Current content: follows drag directly
            return dragOffset
        }
    }
    
    /// Computes opacity based on drag distance
    private var computedOpacity: Double {
        if isIncoming {
            return hasAppeared ? 1.0 : 0.0
        } else {
            // Fade out as content moves away
            let normalizedOffset = abs(dragOffset) / 300
            return max(0, 1 - Double(normalizedOffset) * 0.5)
        }
    }
}

// MARK: - Previews

#Preview("Content View") {
    ZStack {
        AffirmationBackgroundView(category: .confidence)
        
        AffirmationContentView(
            affirmation: .sample,
            dragOffset: 0,
            exitDirection: 0,
            isIncoming: false,
            onFavoriteTap: {},
            onShareTap: {}
        )
    }
}

#Preview("Content - Favorited") {
    ZStack {
        AffirmationBackgroundView(category: .peace)
        
        AffirmationContentView(
            affirmation: {
                let a = Affirmation.sample
                a.isFavorited = true
                return a
            }(),
            dragOffset: 0,
            exitDirection: 0,
            isIncoming: false,
            onFavoriteTap: {},
            onShareTap: {}
        )
    }
}

#Preview("Content - Dragging Up") {
    ZStack {
        AffirmationBackgroundView(category: .focus)
        
        AffirmationContentView(
            affirmation: .sample,
            dragOffset: -100,
            exitDirection: 0,
            isIncoming: false,
            onFavoriteTap: {},
            onShareTap: {}
        )
    }
}
