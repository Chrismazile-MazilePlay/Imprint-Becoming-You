//
//  FloatingHUDLayer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - FloatingHUDLayer

/// Layer containing all floating buttons that overlay the practice view.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────┐
/// │  [✨ AI] [⊞]   [🎤 Listening]   [👤]│  ← Top row (ANCHORED AT TOP)
/// │                                     │
/// │        (Affirmation Text)           │
/// │                                     │
/// │            [↗️]  [❤️]               │  ← Action buttons (above dock)
/// │                                     │
/// │  ┌─────────────────────────────┐    │
/// │  │         Dock                │    │
/// │  └─────────────────────────────┘    │
/// └─────────────────────────────────────┘
/// ```
///
/// Center chip shows:
/// - "Listening" during listening phase (with pulsing green dot)
/// - "Resonance • Good" during score phase (with quality label)
struct FloatingHUDLayer: View {
    
    // MARK: - Environment
    
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    
    /// Callback for profile button tap (navigate to profile page - RIGHT)
    let onProfileTap: () -> Void
    
    /// Callback for prompts button tap (navigate to prompts page - LEFT)
    let onPromptsTap: () -> Void
    
    /// Callback for categories button tap (open full screen cover)
    let onCategoriesTap: () -> Void
    
    // MARK: - Private
    
    private var isActiveMode: Bool {
        viewModel.dockManager.isInActiveMode
    }
    
    private var isFavorited: Bool {
        viewModel.currentAffirmation?.isFavorited ?? false
    }
    
    /// Whether currently in listening state
    private var isListening: Bool {
        let state = viewModel.dockManager.state
        switch state {
        case .readAndSpeak(let phase):
            return phase == .listening
        case .speakOnly(let phase):
            return phase == .listening
        default:
            return false
        }
    }
    
    /// Whether currently showing score
    private var isShowingScore: Bool {
        let state = viewModel.dockManager.state
        switch state {
        case .readAndSpeak(let phase):
            if case .showingScore = phase { return true }
            return false
        case .speakOnly(let phase):
            if case .showingScore = phase { return true }
            return false
        default:
            return false
        }
    }
    
    /// Current score value (if showing)
    private var currentScore: Double? {
        let state = viewModel.dockManager.state
        switch state {
        case .readAndSpeak(let phase):
            if case .showingScore(let score) = phase { return score }
            return nil
        case .speakOnly(let phase):
            if case .showingScore(let score) = phase { return score }
            return nil
        default:
            return nil
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Top row - ANCHORED AT TOP
                VStack(spacing: 0) {
                    topButtons
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.md)
                    
                    Spacer()
                }
                
                // Action buttons - ANCHORED AT BOTTOM (above dock)
                VStack {
                    Spacer()
                    
                    actionButtons
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.bottom, dockSpacing)
                }
            }
        }
    }
    
    /// Spacing above dock - adjusts based on dock height
    private var dockSpacing: CGFloat {
        isActiveMode ? 160 : 100
    }
    
    // MARK: - Top Buttons
    
    private var topButtons: some View {
        HStack {
            // Left side: Exit (in active mode) OR AI + Categories (in home mode)
            if isActiveMode {
                exitButton
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    aiPromptsButton
                    categoriesButton
                }
            }
            
            Spacer()
            
            // Center: Status chip (Listening or Resonance score)
            centerChip
            
            Spacer()
            
            // Right side: Profile button (only in home mode) or spacer for centering
            if !isActiveMode {
                profileButton
            } else {
                // Invisible spacer to keep chip centered
                Color.clear
                    .frame(width: 70, height: 44)
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
            // Empty space to maintain layout
            Color.clear
                .frame(width: 100, height: 32)
        }
    }
    
    // MARK: - AI Prompts Button (Left side)
    
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
        .accessibilityHint("Opens custom prompts page")
    }
    
    // MARK: - Categories Button (Left side, next to AI)
    
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
        .accessibilityHint("Opens category selection")
    }
    
    // MARK: - Profile Button (Right side)
    
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
        .accessibilityHint("Opens your profile page")
    }
    
    // MARK: - Exit Button
    
    private var exitButton: some View {
        Button {
            Task {
                await viewModel.returnToHome(audioService: dependencies.audioService)
            }
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
        .accessibilityHint("Returns to browse mode")
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            // Share button (disabled for now)
            shareButton
            
            // Favorite button
            favoriteButton
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
    
    // MARK: - Share Button
    
    private var shareButton: some View {
        Button {
            viewModel.shareAffirmation()
        } label: {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 44, height: 44)
                
                Text("Share")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .accessibilityLabel("Share")
        .accessibilityHint("Share this affirmation")
        .disabled(true)
        .opacity(0.5)
    }
    
    // MARK: - Favorite Button
    
    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isFavorited ? 1.1 : 1.0)
                    .animation(AppTheme.Animation.bouncy, value: isFavorited)
                
                Text(isFavorited ? "Saved" : "Save")
                    .font(AppTypography.caption2)
                    .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textSecondary)
            }
        }
        .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFavorited ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Floating HUD - Home State") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            Text("I am confident and capable.")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        
        FloatingHUDLayer(
            viewModel: {
                let vm = PracticeViewModel()
                vm.affirmations = Affirmation.samples
                return vm
            }(),
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}

#Preview("Floating HUD - Active Mode") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            Text("I embrace challenges.")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        
        FloatingHUDLayer(
            viewModel: {
                let vm = PracticeViewModel()
                vm.affirmations = Affirmation.samples
                vm.dockManager.setMode(.speakOnly)
                return vm
            }(),
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}

#Preview("Floating HUD - Listening") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            Text("I am grateful for today.")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        
        FloatingHUDLayer(
            viewModel: {
                let vm = PracticeViewModel()
                vm.affirmations = Affirmation.samples
                vm.dockManager.setMode(.speakOnly)
                vm.dockManager.updateSpeakOnlyPhase(.listening)
                return vm
            }(),
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}

#Preview("Floating HUD - Score Shown") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            Text("I am worthy of success.")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        
        FloatingHUDLayer(
            viewModel: {
                let vm = PracticeViewModel()
                vm.affirmations = Affirmation.samples
                vm.dockManager.setMode(.speakOnly)
                vm.dockManager.updateSpeakOnlyPhase(.showingScore(score: 0.82))
                return vm
            }(),
            onProfileTap: {},
            onPromptsTap: {},
            onCategoriesTap: {}
        )
    }
}
