//
//  FloatingHUDLayer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - FloatingHUDLayer

/// Layer containing the top navigation buttons that overlay the practice view.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────┐
/// │  [✨ AI] [⊞]   [🎤 Listening]   [👤]│  ← Top row only
/// │                                     │
/// │        (Content scrolls here)       │
/// │                                     │
/// └─────────────────────────────────────┘
/// ```
///
/// Note: Save/Share buttons are in the scrolling content layer.
struct FloatingHUDLayer: View {
    
    // MARK: - Environment
    
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    
    let onProfileTap: () -> Void
    let onPromptsTap: () -> Void
    let onCategoriesTap: () -> Void
    
    // MARK: - Safe Area Helper
    
    /// Gets the actual top safe area inset from the window.
    /// This works regardless of SwiftUI's .ignoresSafeArea() modifiers.
    private var topSafeAreaInset: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 59 // Default for Dynamic Island devices
        }
        return window.safeAreaInsets.top
    }
    
    // MARK: - Computed State
    
    private var isActiveMode: Bool {
        store.isSessionActive
    }
    
    private var isListening: Bool {
        store.flow.isListening
    }
    
    private var isShowingScore: Bool {
        store.flow.isShowingScore
    }
    
    private var currentScore: Double? {
        store.flow.scoreResult?.score
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            topButtons
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, topPadding)
            
            Spacer()
        }
    }
    
    /// Top padding varies by mode:
    /// - Home mode: TabView handles safe area, so use minimal padding
    /// - Active mode: No TabView, so we must add safe area inset ourselves
    private var topPadding: CGFloat {
        if isActiveMode {
            return topSafeAreaInset + AppTheme.Spacing.xs
        } else {
            return 8
        }
    }
    
    // MARK: - Top Buttons
    
    private var topButtons: some View {
        HStack {
            if isActiveMode {
                exitButton
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    aiPromptsButton
                    categoriesButton
                }
            }
            
            Spacer()
            
            centerChip
            
            Spacer()
            
            if !isActiveMode {
                profileButton
            } else {
                Color.clear.frame(width: 70, height: 44)
            }
        }
    }
    
    // MARK: - Center Chip
    
    @ViewBuilder
    private var centerChip: some View {
        if isShowingScore, let score = currentScore {
            ResonanceChip(score: score)
        } else if isListening {
            ListeningChip(isVisible: true)
        } else {
            Color.clear.frame(width: 100, height: 32)
        }
    }
    
    // MARK: - Buttons
    
    private var aiPromptsButton: some View {
        Button {
            onPromptsTap()
            HapticFeedback.impact(.light)
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 44, height: 44)
                .background(AppColors.accent.opacity(0.15))
                .clipShape(Circle())
        }
        .accessibilityLabel("AI Prompts")
    }
    
    private var categoriesButton: some View {
        Button {
            onCategoriesTap()
            HapticFeedback.impact(.light)
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 44, height: 44)
                .background(AppColors.surfaceTertiary.opacity(0.8))
                .clipShape(Circle())
        }
        .accessibilityLabel("Categories")
    }
    
    private var profileButton: some View {
        Button {
            onProfileTap()
            HapticFeedback.impact(.light)
        } label: {
            Image(systemName: "person.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 44, height: 44)
                .background(AppColors.surfaceTertiary.opacity(0.8))
                .clipShape(Circle())
        }
        .accessibilityLabel("Profile")
    }
    
    private var exitButton: some View {
        Button {
            store.send(.exitSession)
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                Text("Exit")
                    .font(AppTypography.caption1.weight(.medium))
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.surfaceTertiary.opacity(0.8))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Exit session")
    }
}

// MARK: - Previews

#Preview("HUD - Home") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .preview,
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}

#Preview("HUD - Active") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .previewReadAloud,
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}

#Preview("HUD - Listening") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .previewListening,
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}

#Preview("HUD - Showing Score") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .previewShowingScore,
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}
