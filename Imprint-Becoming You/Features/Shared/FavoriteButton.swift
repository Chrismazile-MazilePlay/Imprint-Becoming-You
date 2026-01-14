//
//  FavoriteButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import SwiftUI

// MARK: - FavoriteButton

/// A stateless favorite button that displays the current favorite state.
///
/// ## Architecture: Pure Presentation Component
///
/// This component follows the **Single Source of Truth** principle:
/// - The model (`Affirmation.isFavorited`) is the only source of truth
/// - This view is a pure function of its inputs
/// - No local `@State` for display value (eliminates sync issues)
///
/// ### Why No Local State?
/// Previous implementations used `@State` to provide "immediate feedback",
/// but this caused animation artifacts when scrolling (the heart would
/// animate from filled to empty when scrolling to an unfavorited card).
///
/// The "immediate feedback" concern is actually unfounded because:
/// 1. SwiftData model mutations are synchronous on MainActor
/// 2. SwiftUI re-renders immediately when @Observable/@Model changes
/// 3. The actual toggle happens in <1ms
///
/// ### Animation Strategy
/// - **Icon change**: No automatic animation - prevents animation on scroll
/// - **Scale pulse**: Triggered explicitly on tap via `@State` scale factor
/// - Each affirmation has its own independent button with no shared state
///
/// ## SOLID Compliance
/// - **SRP**: Only responsible for rendering favorite state and handling tap
/// - **OCP**: Animation behavior can be extended via `animationStyle` without modification
/// - **LSP**: Behaves consistently regardless of how/when state changes
/// - **ISP**: Clean interface with only necessary inputs
/// - **DIP**: Depends on abstractions (Bool, closure) not concrete implementations
struct FavoriteButton: View {
    
    // MARK: - Properties
    
    /// Whether the item is currently favorited (from model)
    let isFavorited: Bool
    
    /// Whether the button is interactive
    let isEnabled: Bool
    
    /// Animation style for tap feedback
    let animationStyle: FavoriteButtonAnimationStyle
    
    /// Callback when user taps the button
    let onToggle: () -> Void
    
    // MARK: - Animation State
    
    /// Scale factor for tap pulse animation.
    /// This is the ONLY local state, and it's purely for animation.
    @State private var scale: CGFloat = 1.0
    
    // MARK: - Initialization
    
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
        Button(action: handleTap) {
            VStack(spacing: AppTheme.Spacing.sm) {
                heartIcon
                label
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
    }
    
    // MARK: - Subviews
    
    private var heartIcon: some View {
        Image(systemName: isFavorited ? "heart.fill" : "heart")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textSecondary)
            .frame(width: 56, height: 56)
            .scaleEffect(scale)
    }
    
    private var label: some View {
        Text("Favorite")
            .font(AppTypography.caption1.weight(.medium))
            .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textSecondary)
    }
    
    // MARK: - Actions
    
    private func handleTap() {
        // Trigger scale animation if using full style
        if animationStyle == .full {
            triggerScalePulse()
            HapticFeedback.impact(.medium)
        }
        
        // Notify parent - model update happens synchronously
        onToggle()
    }
    
    private func triggerScalePulse() {
        withAnimation(.easeOut(duration: 0.15)) {
            scale = 1.3
        }
        
        // Use Task for cleaner async without DispatchQueue
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeIn(duration: 0.1)) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Animation Style

/// Controls the level of feedback when favoriting.
enum FavoriteButtonAnimationStyle: Sendable {
    /// Full feedback: scale pulse + haptic + icon transition
    case full
    
    /// Minimal feedback: icon transition only (no scale, no haptic)
    case minimal
}

// MARK: - Previews

#Preview("Favorite Button States") {
    HStack(spacing: 40) {
        VStack {
            FavoriteButton(isFavorited: false, isEnabled: true, onToggle: {})
            Text("Not Favorited").font(.caption)
        }
        
        VStack {
            FavoriteButton(isFavorited: true, isEnabled: true, onToggle: {})
            Text("Favorited").font(.caption)
        }
        
        VStack {
            FavoriteButton(isFavorited: false, isEnabled: false, onToggle: {})
            Text("Disabled").font(.caption)
        }
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Interactive Toggle") {
    struct PreviewWrapper: View {
        @State private var isFavorited = false
        
        var body: some View {
            VStack(spacing: 20) {
                FavoriteButton(
                    isFavorited: isFavorited,
                    isEnabled: true,
                    onToggle: { isFavorited.toggle() }
                )
                
                Text(isFavorited ? "Favorited ❤️" : "Not favorited")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding()
            .background(AppColors.backgroundPrimary)
        }
    }
    
    return PreviewWrapper()
}
