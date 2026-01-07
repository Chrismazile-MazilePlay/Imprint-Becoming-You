//
//  FavoriteButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import SwiftUI

// MARK: - FavoriteButton Animation Style

/// Controls the level of feedback when favoriting.
enum FavoriteButtonAnimationStyle: Sendable {
    /// Full feedback: scale pulse + haptic + icon change
    case full
    
    /// Minimal feedback: icon change only (no scale, no haptic)
    case minimal
}

// MARK: - FavoriteButton

/// A favorite button with guaranteed immediate UI feedback.
///
/// ## Why Local State is Required
/// SwiftUI's observation system can break when views are created inside closures
/// (like `VerticalPager.content(index)`). This component uses local `@State` to
/// guarantee the heart icon toggles immediately when tapped.
///
/// ## Animation Styles
/// - `.full`: Scale pulse + haptic + icon change (use during practice)
/// - `.minimal`: Icon change only (use in Results Summary cards)
///
/// ## Visual Feedback
/// - Heart icon toggles between outline and filled
/// - Scale pulse animation (1.0 → 1.3 → 1.0) [full only]
/// - Haptic feedback on tap [full only]
/// - Static "Favorite" label (does not change)
struct FavoriteButton: View {
    
    // MARK: - Properties
    
    /// The current favorite state from the model.
    let isFavorited: Bool
    
    /// Whether the button is interactive.
    let isEnabled: Bool
    
    /// Animation style for feedback level.
    let animationStyle: FavoriteButtonAnimationStyle
    
    /// Callback when the button is tapped.
    let onToggle: () -> Void
    
    // MARK: - Local State
    
    /// Local display state for immediate UI feedback.
    @State private var displayFavorited: Bool = false
    
    /// Scale factor for the pulse animation.
    @State private var scale: CGFloat = 1.0
    
    // MARK: - Initializer
    
    /// Creates a favorite button.
    /// - Parameters:
    ///   - isFavorited: Current favorite state from model
    ///   - isEnabled: Whether button is interactive
    ///   - animationStyle: Feedback level (default: .full)
    ///   - onToggle: Callback when tapped
    init(
        isFavorited: Bool,
        isEnabled: Bool,
        animationStyle: FavoriteButtonAnimationStyle = .full,
        onToggle: @escaping () -> Void
    ) {
        self.isFavorited = isFavorited
        self.isEnabled = isEnabled
        self.animationStyle = animationStyle
        self.onToggle = onToggle
    }
    
    // MARK: - Body
    
    var body: some View {
        Button {
            // 1. Toggle local state IMMEDIATELY
            displayFavorited.toggle()
            
            // 2. Trigger animation (style-dependent)
            triggerAnimation()
            
            // 3. Notify parent to update model
            onToggle()
        } label: {
            VStack(spacing: AppTheme.Spacing.sm) {
                // Heart icon only - no background circle
                Image(systemName: displayFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(displayFavorited ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 56, height: 56)
                    .scaleEffect(scale)
                    .animation(AppTheme.Animation.bouncy, value: displayFavorited)
                
                // Static label - always says "Favorite"
                Text("Favorite")
                    .font(AppTypography.caption1.weight(.medium))
                    .foregroundStyle(displayFavorited ? AppColors.accent : AppColors.textSecondary)
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(displayFavorited ? "Remove from favorites" : "Add to favorites")
        .onAppear {
            displayFavorited = isFavorited
        }
        .onChange(of: isFavorited) { _, newValue in
            if displayFavorited != newValue {
                displayFavorited = newValue
            }
        }
    }
    
    // MARK: - Animation
    
    private func triggerAnimation() {
        switch animationStyle {
        case .full:
            // Full animation: scale pulse + haptic
            withAnimation(.easeOut(duration: 0.15)) {
                scale = 1.3
            }
            
            HapticFeedback.impact(.medium)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.1)) {
                    scale = 1.0
                }
            }
            
        case .minimal:
            // Minimal animation: icon change only (handled by SwiftUI animation modifier)
            break
        }
    }
}

// MARK: - Previews

#Preview("Favorite Button") {
    VStack(spacing: 40) {
        FavoriteButton(isFavorited: false, isEnabled: true, onToggle: {})
        FavoriteButton(isFavorited: true, isEnabled: true, onToggle: {})
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

// MARK: - Previews

#Preview("Favorite Button - Full Animation") {
    VStack(spacing: 40) {
        FavoriteButton(isFavorited: false, isEnabled: true, onToggle: {})
        FavoriteButton(isFavorited: true, isEnabled: true, onToggle: {})
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Favorite Button - Minimal Animation") {
    VStack(spacing: 40) {
        FavoriteButton(isFavorited: false, isEnabled: true, animationStyle: .minimal, onToggle: {})
        FavoriteButton(isFavorited: true, isEnabled: true, animationStyle: .minimal, onToggle: {})
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
