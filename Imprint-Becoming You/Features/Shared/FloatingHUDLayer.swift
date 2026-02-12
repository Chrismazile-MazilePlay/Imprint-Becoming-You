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
/// │  [✨ AI]       [🎤 Listening]   [👤]│  ← Top row only
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
    
    // MARK: - Safe Area State

    /// Cached top safe area inset from the window.
    ///
    /// Stored as `@State` and set once in `.onAppear` instead of being a computed
    /// property that reads UIKit on every body evaluation. This prevents the HUD's
    /// top padding from flickering during background→foreground transitions, where
    /// `UIApplication.shared.connectedScenes` can momentarily return `nil` and
    /// cause a fallback value to be used for one render frame.
    @State private var topSafeAreaInset: CGFloat = 59
    
    // MARK: - Computed State
    
    private var isActiveMode: Bool {
        store.isSessionActive
    }
    
    private var isListening: Bool {
        store.flow.isListening
    }
    
    private var isCelebrating: Bool {
        store.flow.isCelebrating
    }
    
    /// Whether to show the loop progress chip
    private var showLoopChip: Bool {
        isActiveMode && store.loopConfiguration.loopCount > 1
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            topButtons
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, topPadding)

            Spacer()
        }
        .onAppear {
            // Read the actual safe area inset once when the view appears.
            // This value doesn't change during the app lifecycle (same device,
            // same orientation), so reading it once is sufficient.
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                topSafeAreaInset = window.safeAreaInsets.top
            }
        }
    }
    
    /// Top padding accounts for safe area (notch/Dynamic Island) plus spacing.
    /// Always uses safe area inset since parent view (HorizontalPager) ignores
    /// safe areas for full-screen content.
    private var topPadding: CGFloat {
        topSafeAreaInset + AppTheme.Spacing.xs
    }
    
    // MARK: - Chip Dimensions
    
    /// Standard height for all HUD chips to ensure visual consistency
    private let chipHeight: CGFloat = 48
    
    /// Fixed width for Exit and Loop chips for perfect symmetry
    private let symmetricChipWidth: CGFloat = 78
    
    // MARK: - Top Buttons
    
    private var topButtons: some View {
        HStack {
            // LEFT: Exit button (active mode) or AI button (home mode)
            leftButtons
            
            Spacer()
            
            // CENTER: Listening chip (overlaid, doesn't push other elements)
            // Using ZStack so it floats over the Spacers without affecting layout
            
            Spacer()
            
            // RIGHT: Loop chip (active + looping) or Profile (home mode)
            rightButtons
        }
        .overlay {
            // Center chip overlaid so it doesn't affect left/right positioning
            centerChip
        }
    }
    
    // MARK: - Left Buttons
    
    @ViewBuilder
    private var leftButtons: some View {
        if isActiveMode {
            exitButton
        } else {
            aiPromptsButton
        }
    }
    
    // MARK: - Right Buttons
    
    @ViewBuilder
    private var rightButtons: some View {
        if isActiveMode {
            if showLoopChip {
                loopProgressChip
            } else {
                // Invisible spacer to maintain layout - same size as Exit button
                Color.clear.frame(width: 48, height: 48)
            }
        } else {
            profileButton
        }
    }
    
    // MARK: - Center Chip (Listening/Score)
    
    @ViewBuilder
    private var centerChip: some View {
        if isListening {
            ListeningChip(isVisible: true)
        }
    }
    
    /// Chip showing current loop iteration (e.g., "🔁 1 of 3")
    /// Uses icon instead of text to match Exit chip width
    private var loopProgressChip: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "repeat")
                .font(.system(size: 17, weight: .semibold))
            
            Text(loopChipNumbers)
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(AppColors.textSecondary)
        .frame(width: symmetricChipWidth, height: chipHeight)
        .background(AppColors.surfaceTertiary.opacity(0.8))
        .clipShape(Capsule())
    }
    
    /// Just the numbers for the loop chip (e.g., "1 of 3")
    private var loopChipNumbers: String {
        "\(store.loopConfiguration.currentLoopIteration) of \(store.loopConfiguration.loopCount)"
    }
    
    // MARK: - Buttons
    
    private var aiPromptsButton: some View {
        Button {
            onPromptsTap()
            HapticFeedback.impact(.light)
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 48, height: 48)
                .background(AppColors.accent.opacity(0.15))
                .clipShape(Circle())
        }
        .accessibilityLabel("AI Prompts")
    }
    
    private var profileButton: some View {
        Button {
            onProfileTap()
            HapticFeedback.impact(.light)
        } label: {
            Image(systemName: "person.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 48, height: 48)
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
            Image(systemName: "xmark")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 48, height: 48)
                .background(AppColors.surfaceTertiary.opacity(0.8))
                .clipShape(Circle())
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
            onPromptsTap: {}
        )
    }
}

#Preview("HUD - Active") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .previewReadAloud,
            onProfileTap: {},
            onPromptsTap: {}
        )
    }
}

#Preview("HUD - Listening") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .previewListening,
            onProfileTap: {},
            onPromptsTap: {}
        )
    }
}

#Preview("HUD - Celebrating") {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingHUDLayer(
            store: .previewCelebrating,
            onProfileTap: {},
            onPromptsTap: {}
        )
    }
}
