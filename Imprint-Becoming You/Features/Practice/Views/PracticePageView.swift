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
/// - Content fades and scales as it moves (via ContentTransitionModifier)
///
/// ## Vertical Centering
/// Affirmation content is centered between two boundaries:
/// - **Top**: Bottom edge of the floating HUD (exit button area)
/// - **Bottom**: Top edge of the Share/Save buttons
///
/// This is achieved by applying matching top and bottom offsets to the content VStack.
/// The `topContentOffset` accounts for the HUD, while `dockOffset` accounts for the dock.
///
/// ## Color Morphing
/// Background colors use true RGB interpolation (not opacity crossfade) for smooth
/// transitions. The system has two modes:
/// - **Active navigation** (progress Ã¢â€°Â  0): Uses `interpolatedBackground` for real-time color blending
/// - **At rest** (progress Ã¢â€°Ë† 0): Uses `staticBackground` with `displayedBackgroundCategory`
///
/// When navigation completes, `displayedBackgroundCategory` is immediately updated
/// to match the new index, ensuring seamless handoff between modes.
///
/// ## Auto-Advance Integration
/// - Store sets `pendingAutoAdvance` to trigger animated transition
/// - VerticalPager performs animation and calls `onAutoAdvanceComplete`
/// - Store's `continueFlow()` starts the next affirmation flow
/// - DockProgressBars stay in sync via store state
///
/// ## Gesture Priority
/// Vertical gestures take strict priority over horizontal (parent TabView).
struct PracticePageView: View {
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    
    /// Callback to navigate to profile page
    let onNavigateToProfile: () -> Void
    
    /// Callback to navigate to prompts page
    let onNavigateToPrompts: () -> Void
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var showCategories = false
    
    /// Tracks the background category to display when at rest (progress Ã¢â€°Ë† 0).
    /// Updated immediately (no animation) when index changes, because the
    /// progress-based interpolation already handles the visual transition.
    @State private var displayedBackgroundCategory: GoalCategory?
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dismiss overlay - appears when selectors are expanded
            // This must be BELOW the dock but ABOVE the pager content
            if store.isModeSelectorExpanded || store.isBinauralSelectorExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.closeSelectors)
                    }
                    .zIndex(1)
            }
            
            // Vertical pager with auto-advance support
            VerticalPager(
                currentIndex: currentIndexBinding,
                itemCount: store.affirmations.count,
                canNavigate: canNavigate,
                canNavigateNext: store.canGoNext,
                canNavigatePrevious: store.canGoPrevious,
                pendingAdvance: pendingAdvanceBinding,
                onNavigate: handleUserNavigation,
                onAutoAdvanceComplete: handleAutoAdvanceComplete
            ) { index in
                // Content for each index (moves with gesture)
                affirmationContent(at: index)
            } background: { currentIndex, progress in
                // Background with smooth color morphing
                morphingBackground(currentIndex: currentIndex, progress: progress)
            }
            
            // Fixed overlay layers (don't move with gesture)
            overlayLayers
                .zIndex(2) // Dock is above the dismiss overlay
        }
        .gesture(horizontalBlockingGesture)
        .fullScreenCover(isPresented: $showCategories) {
            CategoriesFullScreenView(store: store)
        }
        .onAppear {
            // Initialize background to current category
            displayedBackgroundCategory = store.currentAffirmation?.goalCategory
        }
        .onChange(of: store.currentIndex) { _, newIndex in
            // Immediately update displayed category (no animation needed).
            // The progress-based interpolation already handled the visual transition
            // during drag or auto-advance. This ensures staticBackground shows
            // the correct color when progress returns to 0.
            displayedBackgroundCategory = affirmation(at: newIndex)?.goalCategory
        }
    }
    
    // MARK: - Bindings
    
    /// Binding for currentIndex that updates store
    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { store.currentIndex },
            set: { store.updateIndex($0) }
        )
    }
    
    /// Binding for pendingAutoAdvance
    private var pendingAdvanceBinding: Binding<NavigationDirection?> {
        Binding(
            get: { store.pendingAutoAdvance },
            set: { store.pendingAutoAdvance = $0 }
        )
    }
    
    // MARK: - Navigation Handlers
    
    /// Called when user swipes to navigate
    private func handleUserNavigation(_ direction: NavigationDirection) {
        store.send(.userNavigated(direction))
    }
    
    /// Called when auto-advance animation completes
    private func handleAutoAdvanceComplete() {
        store.send(.autoAdvanceCompleted)
    }
    
    // MARK: - Navigation Logic
    
    private var canNavigate: Bool {
        // Block if selectors are expanded
        guard !store.isModeSelectorExpanded else { return false }
        guard !store.isBinauralSelectorExpanded else { return false }
        
        // Allow navigation even during active phases - swipe will interrupt
        // The navigate() method handles cancelling current activity
        return true
    }
    
    // MARK: - Morphing Background
    
    /// Determines the target category based on drag direction
    private func targetCategory(for currentIndex: Int, progress: CGFloat) -> GoalCategory? {
        let currentCategory = affirmation(at: currentIndex)?.goalCategory
        
        if progress > 0.05 && currentIndex < store.affirmations.count - 1 {
            return affirmation(at: currentIndex + 1)?.goalCategory
        } else if progress < -0.05 && currentIndex > 0 {
            return affirmation(at: currentIndex - 1)?.goalCategory
        } else {
            return currentCategory
        }
    }
    
    /// Background view that smoothly morphs between category colors.
    ///
    /// Uses two rendering modes:
    /// - **At rest** (|progress| < 0.01): Shows static gradient for `displayedBackgroundCategory`
    /// - **During navigation** (|progress| Ã¢â€°Â¥ 0.01): Interpolates between current and target colors
    ///
    /// The handoff between modes is seamless because `displayedBackgroundCategory`
    /// is updated immediately when the index changes.
    @ViewBuilder
    private func morphingBackground(currentIndex: Int, progress: CGFloat) -> some View {
        if abs(progress) < 0.01 {
            // At rest - show static background for current category
            staticBackground(for: displayedBackgroundCategory)
        } else {
            // Active navigation - interpolate colors based on progress
            interpolatedBackground(currentIndex: currentIndex, progress: progress)
        }
    }
    
    /// Static background for a single category (used when at rest)
    @ViewBuilder
    private func staticBackground(for category: GoalCategory?) -> some View {
        let gradient = CategoryGradient.forCategory(category)
        
        ZStack {
            LinearGradient(
                colors: [gradient.primary.opacity(0.3), gradient.secondary],
                startPoint: .top,
                endPoint: .bottom
            )
            
            RadialGradient(
                colors: [gradient.primary.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }
    
    /// Interpolated background using true RGB blending (used during navigation)
    @ViewBuilder
    private func interpolatedBackground(currentIndex: Int, progress: CGFloat) -> some View {
        let currentCategory = affirmation(at: currentIndex)?.goalCategory
        let targetCat = targetCategory(for: currentIndex, progress: progress)
        
        let currentGradient = CategoryGradient.forCategory(currentCategory)
        let targetGradient = CategoryGradient.forCategory(targetCat)
        
        // Use absolute progress for interpolation (0 to 1)
        let t = min(abs(progress), 1.0)
        
        // Interpolate primary and secondary colors
        let blendedPrimary = Color.interpolate(from: currentGradient.primary, to: targetGradient.primary, t: t)
        let blendedSecondary = Color.interpolate(from: currentGradient.secondary, to: targetGradient.secondary, t: t)
        
        ZStack {
            LinearGradient(
                colors: [blendedPrimary.opacity(0.3), blendedSecondary],
                startPoint: .top,
                endPoint: .bottom
            )
            
            RadialGradient(
                colors: [blendedPrimary.opacity(0.12), Color.clear],
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
                    
                    // Action buttons - shown on ALL pages for unified animation
                    // Buttons animate together with text via ContentTransitionModifier
                    actionButtons(for: affirmation, isCurrentPage: index == store.currentIndex)
                        .padding(.bottom, dockOffset)
                }
                .padding(.top, topContentOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Content Offset Calculations
    
    /// Offset from top to account for the floating HUD layer.
    ///
    /// This ensures the affirmation text is vertically centered between:
    /// - Top: Bottom edge of the HUD (exit button area)
    /// - Bottom: Top edge of the Share/Save buttons
    ///
    /// The offset equals the HUD height to create balanced spacing with the bottom dock offset.
    private var topContentOffset: CGFloat {
        AppTheme.Layout.hudContentOffset
    }
    
    /// Offset from bottom to position buttons just above dock.
    /// Uses centralized layout constants from AppTheme.Layout.
    private var dockOffset: CGFloat {
        if store.isSessionActive {
            return AppTheme.Layout.activeDockOffset
        } else {
            return AppTheme.Layout.homeDockOffset
        }
    }
    
    private func affirmation(at index: Int) -> Affirmation? {
        guard store.affirmations.indices.contains(index) else { return nil }
        return store.affirmations[index]
    }
    
    // MARK: - Action Buttons
    
    /// Action buttons for share and favorite.
    ///
    /// The Share button is implemented inline. The Favorite button uses the
    /// `FavoriteButton` component which maintains local state for guaranteed
    /// immediate UI feedback. This is necessary because SwiftUI observation
    /// breaks when views are created inside nested closures (VerticalPager content).
    ///
    /// The `isCurrentPage` parameter enables/disables interactivity
    /// without affecting appearance during transitions.
    private func actionButtons(for affirmation: Affirmation, isCurrentPage: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.xxl + 8) {
            // Share button
            Button {
                store.send(.shareAffirmation)
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
            .disabled(!isCurrentPage)
            
            // Favorite button - uses dedicated component with local state
            // for guaranteed immediate UI feedback
            FavoriteButton(
                isFavorited: affirmation.isFavorited,
                isEnabled: isCurrentPage,
                onToggle: { store.send(.toggleFavorite) }
            )
        }
    }
    
    // MARK: - Overlay Layers
    
    @ViewBuilder
    private var overlayLayers: some View {
        // Top HUD
        FloatingHUDLayer(
            store: store,
            onProfileTap: onNavigateToProfile,
            onPromptsTap: onNavigateToPrompts,
            onCategoriesTap: { showCategories = true }
        )
        
        // Bottom dock - anchored to bottom edge, grows upward
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            
            AdaptiveBottomDock(store: store)
                .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .padding(.bottom, AppTheme.Layout.dockBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    
    // MARK: - Horizontal Blocking Gesture
    
    /// Blocks horizontal swipes from reaching parent TabView when in active mode
    private var horizontalBlockingGesture: some Gesture {
        DragGesture(minimumDistance: store.isSessionActive ? 0 : 10000)
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
        switch store.flow {
        case .home:
            return .displaying
        case .readAloud(let phase):
            switch phase {
            case .idle: return .displaying
            case .playing: return .playing
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

// MARK: - Color Interpolation Extension

extension Color {
    /// Interpolates between two colors using RGB values.
    ///
    /// - Parameters:
    ///   - from: Starting color
    ///   - to: Ending color
    ///   - t: Interpolation factor (0.0 = from, 1.0 = to)
    /// - Returns: Interpolated color
    static func interpolate(from: Color, to: Color, t: CGFloat) -> Color {
        let t = min(max(t, 0), 1) // Clamp to 0-1
        
        // Convert to UIColor to extract RGB components
        let fromUIColor = UIColor(from)
        let toUIColor = UIColor(to)
        
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        
        fromUIColor.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        toUIColor.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)
        
        // Linear interpolation
        let r = fromR + (toR - fromR) * t
        let g = fromG + (toG - fromG) * t
        let b = fromB + (toB - fromB) * t
        let a = fromA + (toA - fromA) * t
        
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Previews

#Preview("Practice Page") {
    PracticePageView(
        store: .preview,
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}

#Preview("Practice Page - Active Mode") {
    PracticePageView(
        store: .previewReadAloud,
        onNavigateToProfile: {},
        onNavigateToPrompts: {}
    )
    .previewEnvironment()
}
