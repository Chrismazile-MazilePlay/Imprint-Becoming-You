//
//  PracticePageView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI
import SwiftData

// MARK: - PracticePageView

/// The center page containing the affirmation practice experience.
///
/// ## Architecture
/// Uses `VerticalPager` which shows BOTH current AND adjacent content during drag:
/// - Current content moves with finger (1:1 tracking)
/// - Next/Previous content slides in from edge simultaneously
/// - Background morphs color based on drag progress
/// - NO opacity/fade on content - pure vertical movement
///
/// ## Auto-Advance Integration
/// - ViewModel sets `pendingAutoAdvance` to trigger animated transition
/// - VerticalPager performs animation and calls `onAutoAdvanceComplete`
/// - ViewModel's `continueFlow()` starts the next affirmation flow
/// - DockProgressBars stay in sync via `currentIndex.didSet`
///
/// ## Gesture Priority
/// Vertical gestures take strict priority over horizontal (parent TabView).
struct PracticePageView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    
    /// Callback to navigate to profile page
    let onNavigateToProfile: () -> Void
    
    /// Callback to navigate to prompts page
    let onNavigateToPrompts: () -> Void
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var showCategories = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Vertical pager with auto-advance support
            VerticalPager(
                currentIndex: $viewModel.currentIndex,
                itemCount: viewModel.affirmations.count,
                canNavigate: canNavigate,
                pendingAdvance: $viewModel.pendingAutoAdvance,
                onNavigate: handleUserNavigation,
                onAutoAdvanceComplete: handleAutoAdvanceComplete
            ) { index in
                // Content for each index (moves with gesture)
                affirmationContent(at: index)
            } background: { currentIndex, progress in
                // Background with color morphing
                morphingBackground(currentIndex: currentIndex, progress: progress)
            }
            
            // Fixed overlay layers (don't move with gesture)
            overlayLayers
        }
        .simultaneousGesture(tapGesture)
        .gesture(horizontalBlockingGesture)
        .fullScreenCover(isPresented: $showCategories) {
            CategoriesFullScreenView(viewModel: viewModel)
        }
    }
    
    // MARK: - Navigation Handlers
    
    /// Called when user swipes to navigate
    private func handleUserNavigation(_ direction: NavigationDirection) {
        viewModel.navigate(direction)
    }
    
    /// Called when auto-advance animation completes
    private func handleAutoAdvanceComplete() {
        viewModel.continueFlow()
    }
    
    // MARK: - Navigation Logic
    
    private var canNavigate: Bool {
        // Block if selectors are expanded
        guard !viewModel.dockManager.isModeSelectorExpanded else { return false }
        guard !viewModel.dockManager.isBinauralSelectorExpanded else { return false }
        
        // Allow navigation even during active phases - swipe will interrupt
        // The navigate() method handles cancelling current activity
        return true
    }
    
    // MARK: - Morphing Background
    
    /// Determines the target category based on drag direction
    private func targetCategory(for currentIndex: Int, progress: CGFloat) -> GoalCategory? {
        let currentCategory = affirmation(at: currentIndex)?.goalCategory
        
        if progress > 0 && currentIndex < viewModel.affirmations.count - 1 {
            return affirmation(at: currentIndex + 1)?.goalCategory
        } else if progress < 0 && currentIndex > 0 {
            return affirmation(at: currentIndex - 1)?.goalCategory
        } else {
            return currentCategory
        }
    }
    
    @ViewBuilder
    private func morphingBackground(currentIndex: Int, progress: CGFloat) -> some View {
        let currentCategory = affirmation(at: currentIndex)?.goalCategory
        let currentGradient = CategoryGradient.forCategory(currentCategory)
        let targetGradient = CategoryGradient.forCategory(targetCategory(for: currentIndex, progress: progress))
        let interpolation = min(abs(progress), 1.0)
        
        ZStack {
            // Current gradient
            LinearGradient(
                colors: [currentGradient.primary.opacity(0.3), currentGradient.secondary],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Target gradient (fades in based on progress)
            LinearGradient(
                colors: [targetGradient.primary.opacity(0.3), targetGradient.secondary],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(Double(interpolation))
            
            // Center glow
            RadialGradient(
                colors: [
                    currentGradient.primary.opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Affirmation Content
    
    @ViewBuilder
    private func affirmationContent(at index: Int) -> some View {
        if let affirmation = affirmation(at: index) {
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
                    
                    // Recognized text (only current index, during listening)
                    if index == viewModel.currentIndex,
                       currentPhase == .listening,
                       !viewModel.recognizedText.isEmpty {
                        RecognizedTextView(text: viewModel.recognizedText)
                            .padding(.bottom, AppTheme.Spacing.md)
                    }
                    
                    // Action buttons - positioned close to dock
                    // Only show for current index to avoid duplicate buttons
                    if index == viewModel.currentIndex {
                        actionButtons(for: affirmation)
                            .padding(.bottom, dockOffset)
                    } else {
                        // Spacer for consistent layout on adjacent pages
                        Color.clear
                            .frame(height: 80 + dockOffset)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    /// Offset from bottom to position buttons just above dock
    private var dockOffset: CGFloat {
        viewModel.dockManager.isInActiveMode ? 140 : 110
    }
    
    private func affirmation(at index: Int) -> Affirmation? {
        guard viewModel.affirmations.indices.contains(index) else { return nil }
        return viewModel.affirmations[index]
    }
    
    // MARK: - Action Buttons
    
    private func actionButtons(for affirmation: Affirmation) -> some View {
        HStack(spacing: AppTheme.Spacing.xxl + 8) {
            // Share button
            Button {
                viewModel.shareAffirmation()
            } label: {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 56, height: 56)
                    
                    Text("Share")
                        .font(AppTypography.caption1.weight(.medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .accessibilityLabel("Share affirmation")
            .disabled(true)
            .opacity(0.5)
            
            // Favorite button
            Button {
                viewModel.toggleFavorite()
            } label: {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: affirmation.isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(affirmation.isFavorited ? AppColors.accent : AppColors.textSecondary)
                        .frame(width: 56, height: 56)
                        .scaleEffect(affirmation.isFavorited ? 1.15 : 1.0)
                        .animation(AppTheme.Animation.bouncy, value: affirmation.isFavorited)
                    
                    Text(affirmation.isFavorited ? "Saved" : "Save")
                        .font(AppTypography.caption1.weight(.medium))
                        .foregroundStyle(affirmation.isFavorited ? AppColors.accent : AppColors.textSecondary)
                }
            }
            .accessibilityLabel(affirmation.isFavorited ? "Remove from favorites" : "Add to favorites")
        }
    }
    
    // MARK: - Overlay Layers
    
    @ViewBuilder
    private var overlayLayers: some View {
        // Top HUD
        FloatingHUDLayer(
            viewModel: viewModel,
            onProfileTap: onNavigateToProfile,
            onPromptsTap: onNavigateToPrompts,
            onCategoriesTap: { showCategories = true }
        )
        
        // Bottom dock
        VStack {
            Spacer()
            
            AdaptiveBottomDock(
                viewModel: viewModel,
                onBinauralChange: { preset in
                    await viewModel.changeBinauralPreset(
                        preset,
                        audioService: dependencies.audioService
                    )
                },
                onModeChange: { mode in
                    await viewModel.changeMode(
                        mode,
                        audioService: dependencies.audioService
                    )
                }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }
    
    // MARK: - Tap Gesture
    
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { _ in
                if viewModel.dockManager.isModeSelectorExpanded ||
                   viewModel.dockManager.isBinauralSelectorExpanded {
                    viewModel.dockManager.closeSelectors()
                } else {
                    viewModel.recordInteraction()
                }
            }
    }
    
    // MARK: - Horizontal Blocking Gesture
    
    /// Blocks horizontal swipes from reaching parent TabView when in active mode
    private var horizontalBlockingGesture: some Gesture {
        DragGesture(minimumDistance: viewModel.isSessionActive ? 0 : 10000)
            .onChanged { _ in
                // Consume the gesture - do nothing
                // This prevents horizontal swipes from propagating to TabView
            }
            .onEnded { _ in
                // Do nothing
            }
    }
    
    // MARK: - Phase Mapping
    
    private var currentPhase: AffirmationPhase {
        switch viewModel.dockManager.state {
        case .home:
            return .displaying
        case .readAloud(let phase):
            switch phase {
            case .idle: return .displaying
            case .speaking: return .playing
            case .complete: return .displaying
            }
        case .readAndSpeak(let phase):
            switch phase {
            case .idle: return .displaying
            case .ttsPlaying: return .playing
            case .waitingForUser: return .waitingToSpeak
            case .listening: return .listening
            case .analyzing: return .analyzing
            case .showingScore: return .showingScore
            }
        case .speakOnly(let phase):
            switch phase {
            case .idle: return .displaying
            case .listening: return .listening
            case .analyzing: return .analyzing
            case .showingScore: return .showingScore
            }
        }
    }
}

// MARK: - Previews

#Preview("Practice Page") {
    PracticePageView(
        viewModel: {
            let vm = PracticeViewModel()
            vm.affirmations = Affirmation.samples
            return vm
        }(),
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}

#Preview("Practice Page - Multi Category") {
    PracticePageView(
        viewModel: {
            let vm = PracticeViewModel()
            vm.affirmations = [
                Affirmation(text: "I am confident and capable in all I do.", category: GoalCategory.confidence.rawValue, batchIndex: 0),
                Affirmation(text: "Peace flows through me effortlessly.", category: GoalCategory.peace.rawValue, batchIndex: 1),
                Affirmation(text: "My faith grows stronger each day.", category: GoalCategory.faith.rawValue, batchIndex: 2),
                Affirmation(text: "I maintain sharp focus on my goals.", category: GoalCategory.focus.rawValue, batchIndex: 3),
                Affirmation(text: "I nurture meaningful connections.", category: GoalCategory.relationships.rawValue, batchIndex: 4),
            ]
            return vm
        }(),
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}

#Preview("Practice Page - Active Mode") {
    PracticePageView(
        viewModel: {
            let vm = PracticeViewModel()
            vm.affirmations = Affirmation.samples
            vm.dockManager.setMode(.readAloud)
            return vm
        }(),
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}
