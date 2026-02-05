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
/// - **Active navigation** (progress != 0): Uses `interpolatedBackground` for real-time color blending
/// - **At rest** (progress ~= 0): Uses `staticBackground` with `displayedBackgroundCategory`
///
/// When navigation completes, `displayedBackgroundCategory` is immediately updated
/// to match the new index, ensuring seamless handoff between modes.
///
/// ## Dock Architecture
/// Uses `AdaptiveDockContainer` with `PracticeDockAdapter` which handles:
/// - Mapping PracticeStore state to dock protocol
/// - Dismiss overlay (tap anywhere to close expanded menus)
/// - Mode and Binaural selector expansion
/// - Dock positioning (anchored to bottom, grows upward)
///
/// ## Auto-Advance Integration
/// - Store sets `pendingAutoAdvance` to trigger animated transition
/// - VerticalPager performs animation and calls `onAutoAdvanceComplete`
/// - Store's `continueFlow()` starts the next affirmation flow
/// - DockProgressBars stay in sync via store state
///
/// ## Gesture Architecture
/// Vertical gestures are handled by `VerticalPager` (child). Horizontal gestures
/// are handled by `HorizontalPager` (parent) via `.simultaneousGesture()`.
/// Direction locking in each pager routes events to the correct axis.
///
/// When dock menus (mode/binaural selectors) are expanded, this view relays
/// that state to the parent via `isDockMenuExpanded` binding, which disables
/// `HorizontalPager`'s gesture entirely. The `DockMenuDismissModifier` handles
/// closing the menus on touch.
struct PracticePageView: View {
    
    // MARK: - Properties
    
    @Bindable var store: PracticeStore
    
    /// Callback to navigate to profile page
    let onNavigateToProfile: () -> Void
    
    /// Callback to navigate to prompts page
    let onNavigateToPrompts: () -> Void
    
    /// Binding to communicate dock menu expansion state to parent.
    /// When `true`, parent disables horizontal pager gesture to prevent
    /// page navigation while dock selectors are open.
    @Binding var isDockMenuExpanded: Bool
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    
    // MARK: - State
    
    /// Tracks the background category to display when at rest (progress ~= 0).
    /// Updated immediately (no animation) when index changes, because the
    /// progress-based interpolation already handles the visual transition.
    @State private var displayedBackgroundCategory: GoalCategory?
    
    /// Dock adapter that bridges PracticeStore to DockModule
    @State private var dockAdapter: PracticeDockAdapter
    
    // MARK: - Initialization
    
    init(
        store: PracticeStore,
        onNavigateToProfile: @escaping () -> Void,
        onNavigateToPrompts: @escaping () -> Void,
        isDockMenuExpanded: Binding<Bool>
    ) {
        self.store = store
        self.onNavigateToProfile = onNavigateToProfile
        self.onNavigateToPrompts = onNavigateToPrompts
        self._isDockMenuExpanded = isDockMenuExpanded
        self._dockAdapter = State(initialValue: PracticeDockAdapter(store: store))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
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
            .dismissesDockMenuOnTouch(adapter: dockAdapter)

            
            VStack {
                // Top HUD (doesn't move with gesture)
                FloatingHUDLayer(
                    store: store,
                    onProfileTap: onNavigateToProfile,
                    onPromptsTap: onNavigateToPrompts
                )
                .dismissesDockMenuOnTouch(adapter: dockAdapter)
                
                Spacer()
                
                AdaptiveDockContainer(adapter: dockAdapter) {
                    AdaptiveBottomDock(adapter: dockAdapter)
                }
                .imprintDockEnvironment(waveformType: appState.userProfile?.waveformType ?? .layeredWaves)
            }
            .ignoresSafeArea(edges: .bottom)
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
        .onChange(of: dockAdapter.isModeSelectorExpanded) { _, _ in
            updateDockMenuExpanded()
        }
        .onChange(of: dockAdapter.isBinauralSelectorExpanded) { _, _ in
            updateDockMenuExpanded()
        }
    }
    
    // MARK: - Dock Menu State
    
    /// Relays dock selector expansion state to the parent binding.
    /// When either selector is expanded, horizontal paging is disabled.
    private func updateDockMenuExpanded() {
        isDockMenuExpanded = dockAdapter.isModeSelectorExpanded || dockAdapter.isBinauralSelectorExpanded
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
        guard !dockAdapter.isModeSelectorExpanded else { return false }
        guard !dockAdapter.isBinauralSelectorExpanded else { return false }
        
        // Block if timeout alert is showing to prevent race conditions
        // that could cause double-skip behavior
        guard !store.isShowingTimeoutAlert else { return false }
        
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
    /// - **During navigation** (|progress| >= 0.01): Interpolates between current and target colors
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
                    
                    // Affirmation text — auto-scrolls long texts in sync with TTS
                    AutoScrollingAffirmationText(
                        text: affirmation.text,
                        progress: index == store.currentIndex ? store.flow.ttsProgress : nil,
                        progressRange: ttsProgressRange,
                        maxHeight: maxAffirmationTextHeight(in: geometry)
                    )
                    
                    Spacer()
                    
                    // Action buttons - shown on ALL pages for unified animation
                    // Buttons animate together with text via ContentTransitionModifier
                    actionButtons(for: affirmation, isCurrentPage: index == store.currentIndex)
                        .padding(.bottom, dockOffset)
                }
                .padding(.top, topContentOffset + verticalCenteringOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Content Offset Calculations
    
    /// Offset from top to account for the floating HUD layer.
    ///
    /// This is the base offset for the HUD area (exit button, navigation buttons).
    private var topContentOffset: CGFloat {
        AppTheme.Layout.hudContentOffset
    }
    
    /// Additional top offset that compensates for the dock/HUD height asymmetry.
    ///
    /// The dock (bottom) is significantly taller than the HUD (top). Two equal
    /// `Spacer()` views split the remaining space 50/50, which centers content
    /// within the *available area* — but that area is shifted upward because
    /// the dock consumes more space. This offset balances the asymmetry so
    /// content centers on the actual screen rather than the available area.
    ///
    /// Math: top padding = HUD (80) + centering (123) = 203 = bottom padding (203)
    private var verticalCenteringOffset: CGFloat {
        max(dockOffset - topContentOffset, 0)
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
    
    /// The maximum TTS progress value for the current practice mode.
    ///
    /// Read Aloud caps progress at 0.95 while Read & Speak caps at 0.45.
    /// Passed to `AutoScrollingAffirmationText` so the scroll range adapts
    /// to ensure all text scrolls fully in both modes.
    private var ttsProgressRange: Double {
        switch store.flow {
        case .readAndSpeak:
            return 0.45
        default:
            return 0.95
        }
    }
    
    /// Maximum height available for the affirmation text before auto-scrolling activates.
    ///
    /// Computed from the available content area by subtracting all fixed elements:
    /// - **Top**: HUD offset + vertical centering offset
    /// - **Badge**: Category badge + bottom padding (~54pt)
    /// - **Buttons**: Share/Favorite buttons + labels (~80pt)
    /// - **Dock**: Bottom dock offset (varies by session state)
    ///
    /// Uses 85% of the remaining available height to maximize readable area
    /// while preserving vertical breathing room above and below.
    /// Short texts that fit within this height render at their natural size.
    /// Only texts exceeding this threshold will clip and auto-scroll.
    private func maxAffirmationTextHeight(in geometry: GeometryProxy) -> CGFloat {
        let totalHeight = geometry.size.height
        let effectiveTopOffset = topContentOffset + verticalCenteringOffset
        // Badge (~30) + badge padding (24) + buttons (~80)
        let fixedContentHeight: CGFloat = 134
        let availableHeight = totalHeight - effectiveTopOffset - dockOffset - fixedContentHeight
        let maxTextHeight = availableHeight * 0.85
        return max(maxTextHeight, 120)
    }
    
    private func affirmation(at index: Int) -> Affirmation? {
        guard store.affirmations.indices.contains(index) else { return nil }
        return store.affirmations[index]
    }
    
    // MARK: - Action Buttons
    
    /// Action buttons for share and favorite.
    ///
    /// These buttons are part of the affirmation content VStack and move
    /// together with the text during scroll. No `.id()` is needed because
    /// VerticalPager already provides unique identity per page index.
    ///
    /// The `isCurrentPage` parameter enables/disables interactivity
    /// without affecting appearance during transitions.
    private func actionButtons(for affirmation: Affirmation, isCurrentPage: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.xxl + 8) {
            // Share button
            shareButton(isEnabled: isCurrentPage)
            
            // Favorite button
            FavoriteButton(
                isFavorited: affirmation.isFavorited,
                isEnabled: isCurrentPage,
                onToggle: { store.send(.toggleFavorite) }
            )
        }
    }
    
    /// Share button with consistent styling to match FavoriteButton.
    private func shareButton(isEnabled: Bool) -> some View {
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
        .disabled(!isEnabled)
    }
    
    // MARK: - Overlay Layers
    
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
            case .preparingToListen: return .waitingToSpeak
            case .listening: return .listening
            case .analyzing: return .analyzing
            case .showingScore: return .showingScore
            }
        case .speakOnly(let phase):
            switch phase {
            case .idle: return .displaying
            case .preparingToListen: return .waitingToSpeak
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
        onNavigateToPrompts: {},
        isDockMenuExpanded: .constant(false)
    )
    .previewEnvironment()
}

#Preview("Practice Page - Active Mode") {
    PracticePageView(
        store: .previewReadAloud,
        onNavigateToProfile: {},
        onNavigateToPrompts: {},
        isDockMenuExpanded: .constant(false)
    )
    .previewEnvironment()
}
