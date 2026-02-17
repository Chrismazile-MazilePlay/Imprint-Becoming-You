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
/// Uses `PracticePageViewBuilder` to compose four independent layers:
/// 1. **Background** — `MorphingBackgroundView` or `SolidBackgroundView` (swappable via user preference)
/// 2. **Content** — `AffirmationContentView` per page index (via VerticalPager)
/// 3. **HUD** — `FloatingHUDLayer` (fixed position, top)
/// 4. **Dock** — `AdaptiveDockContainer` (fixed position, bottom)
///
/// The builder encapsulates component assembly and background style switching.
/// This view handles orchestration: bindings, navigation logic, layout calculations,
/// dock menu state, and auto-advance coordination.
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
/// - **Active navigation** (progress != 0): Uses interpolated gradient for real-time color blending
/// - **At rest** (progress ~= 0): Uses static gradient with `displayedBackgroundCategory`
///
/// When navigation completes, `displayedBackgroundCategory` is immediately updated
/// to match the new index, ensuring seamless handoff between modes.
///
/// ## Dock Architecture
/// Uses `AdaptiveDockContainer` with `PracticeDockAdapter` which handles:
/// - Mapping PracticeStore state to dock protocol
/// - Dismiss overlay (tap anywhere to close expanded menus)
/// - Mode and Music selector expansion
/// - Dock positioning (anchored to bottom, grows upward)
///
/// ## Auto-Advance Integration
/// - Store sets `pendingAutoAdvance` to trigger animated transition
/// - VerticalPager performs animation and calls `onAutoAdvanceComplete`
/// - Store's `continueFlow()` starts the next affirmation flow
/// - DockSegmentsView stays in sync via store state
///
/// ## Gesture Architecture
/// Vertical gestures are handled by `VerticalPager` (child). Horizontal gestures
/// are handled by `HorizontalPager` (parent) via `.simultaneousGesture()`.
/// Direction locking in each pager routes events to the correct axis.
///
/// When dock menus (mode/music selectors) are expanded, this view relays
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

    /// Programmatic auto-advance direction, injected by the parent.
    ///
    /// The parent decides whether this pager should process auto-advance:
    /// - **Home context** (MainPracticeView): passes `.constant(nil)` — pager
    ///   never receives auto-advance signals, preventing double-advance when
    ///   both pagers share the same store.
    /// - **Session context** (SessionContainerView): passes the real
    ///   `$store.pendingAutoAdvance` binding — pager drives session navigation.
    @Binding var pendingAdvance: NavigationDirection?

    /// Dock adapter that bridges PracticeStore to DockModule, injected by parent.
    ///
    /// Each context configures its own adapter:
    /// - **Home context**: `PracticeDockAdapter(store:, suppressSegments: true)`
    ///   — prevents phantom segment timers behind the fullScreenCover.
    /// - **Session context**: `PracticeDockAdapter(store:)` — full segment
    ///   timer support for active sessions.
    let dockAdapter: PracticeDockAdapter

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState

    // MARK: - State

    /// Tracks the background category to display when at rest (progress ~= 0).
    /// Updated immediately (no animation) when index changes, because the
    /// progress-based interpolation already handles the visual transition.
    @State private var displayedBackgroundCategory: GoalCategory?

    /// Controls presentation of the background selection sheet.
    @State private var showingBackgroundSheet = false

    // MARK: - Computed Properties

    /// Builder that assembles the layered view composition.
    /// Reads the user's background style preference for background switching.
    private var builder: PracticePageViewBuilder {
        PracticePageViewBuilder(
            store: store,
            backgroundStyle: appState.userProfile?.backgroundStyle ?? .morphingGradient
        )
    }

    // MARK: - Initialization

    init(
        store: PracticeStore,
        onNavigateToProfile: @escaping () -> Void,
        onNavigateToPrompts: @escaping () -> Void,
        isDockMenuExpanded: Binding<Bool>,
        pendingAdvance: Binding<NavigationDirection?> = .constant(nil),
        dockAdapter: PracticeDockAdapter
    ) {
        self.store = store
        self.onNavigateToProfile = onNavigateToProfile
        self.onNavigateToPrompts = onNavigateToPrompts
        self._isDockMenuExpanded = isDockMenuExpanded
        self._pendingAdvance = pendingAdvance
        self.dockAdapter = dockAdapter
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
                pendingAdvance: $pendingAdvance,
                onNavigate: handleUserNavigation,
                onAutoAdvanceComplete: handleAutoAdvanceComplete
            ) { index in
                // Content for each index (moves with gesture)
                GeometryReader { geometry in
                    builder.buildContent(
                        at: index,
                        isScrollActive: isScrollActive,
                        topPadding: topContentOffset + verticalCenteringOffset,
                        bottomPadding: dockOffset,
                        maxTextHeight: maxAffirmationTextHeight(in: geometry)
                    )
                }
            } background: { currentIndex, progress in
                // Background with smooth color morphing (or solid color)
                builder.buildBackground(
                    currentIndex: currentIndex,
                    progress: progress,
                    displayedCategory: $displayedBackgroundCategory
                )
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        guard dockAdapter.expandedSelector != nil
                           || dockAdapter.isErrorBarVisible else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            dockAdapter.closeAllSelectors()
                        }
                    }
            )


            // Sparkle burst celebration overlay — above content, below HUD
            SparkleBurstView(isActive: store.flow.isCelebrating)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack {
                // Top HUD (doesn't move with gesture)
                builder.buildHUD(
                    onProfileTap: onNavigateToProfile,
                    onPromptsTap: onNavigateToPrompts,
                    onBackgroundTap: { showingBackgroundSheet = true }
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            guard dockAdapter.expandedSelector != nil
                               || dockAdapter.isErrorBarVisible else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dockAdapter.closeAllSelectors()
                            }
                        }
                )

                Spacer()

                builder.buildDock(
                    adapter: dockAdapter,
                    waveformType: appState.userProfile?.waveformType ?? .layeredWaves
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showingBackgroundSheet) {
            BackgroundSheetView()
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
        .onChange(of: dockAdapter.expandedSelector) { _, _ in
            updateDockMenuExpanded()
        }
        .onChange(of: dockAdapter.isErrorBarVisible) { _, _ in
            updateDockMenuExpanded()
        }
        .onChange(of: store.error) { _, newError in
            // Bridge PracticeStore errors to the dock error bar.
            // This replaces the .alert modifier in MainPracticeView.
            if let error = newError {
                dockAdapter.showError(error.userMessage)
                store.send(.dismissError)
            }
        }
    }

    // MARK: - Dock Menu State

    /// Relays dock selector expansion state to the parent binding.
    /// When any selector or error bar is expanded, horizontal paging is disabled.
    private func updateDockMenuExpanded() {
        isDockMenuExpanded = dockAdapter.expandedSelector != nil || dockAdapter.isErrorBarVisible
    }

    // MARK: - Bindings

    /// Binding for currentIndex that updates store
    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { store.currentIndex },
            set: { store.updateIndex($0) }
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
        // Block if any selector or error bar is expanded
        guard dockAdapter.expandedSelector == nil else { return false }
        guard !dockAdapter.isErrorBarVisible else { return false }

        // Block if timeout alert is showing to prevent race conditions
        // that could cause double-skip behavior
        guard !store.isShowingTimeoutAlert else { return false }

        // Allow navigation even during active phases - swipe will interrupt
        // The navigate() method handles cancelling current activity
        return true
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

    /// Whether auto-scrolling should be active for the current flow state.
    ///
    /// Returns `true` during each mode's active content phase:
    /// - **Read Aloud**: TTS playing + complete (holds scroll at bottom)
    /// - **Read & Speak**: TTS playing + user listening/speaking
    /// - **Speak Only**: user listening/speaking
    ///
    /// Read Aloud includes `.complete` so the text holds at the bottom after
    /// TTS ends — the scroll animation has finished and keeping `isActive=true`
    /// is a no-op. When the flow transitions to `.idle` (loop restart, background
    /// pause, or mode switch), `isActive` becomes `false` and the component
    /// smoothly resets to the top.
    ///
    /// In Read & Speak mode, scrolling activates during both the TTS phase
    /// (user follows along) and the listening phase (user speaks while reading).
    /// The scroll resets to top between phases (during `.preparingToListen`),
    /// giving the user a fresh start when they begin speaking.
    ///
    /// Identical timing across all modes — the component's internal delay
    /// and speed are applied uniformly.
    private var isScrollActive: Bool {
        switch store.flow {
        case .readAloud(.playing):
            return true
        case .readAloud(.complete):
            return true
        case .readAndSpeak(.ttsPlaying):
            return true
        case .readAndSpeak(.listening):
            return true
        case .speakOnly(.listening):
            return true
        default:
            return false
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

    /// Safe array access for affirmation at index.
    private func affirmation(at index: Int) -> Affirmation? {
        guard store.affirmations.indices.contains(index) else { return nil }
        return store.affirmations[index]
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
            case .preparingToListen: return .waitingToSpeak
            case .listening: return .listening
            case .celebrating: return .celebrating
            }
        case .speakOnly(let phase):
            switch phase {
            case .idle: return .displaying
            case .preparingToListen: return .waitingToSpeak
            case .listening: return .listening
            case .celebrating: return .celebrating
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
    let store = PracticeStore.preview
    PracticePageView(
        store: store,
        onNavigateToProfile: {},
        onNavigateToPrompts: {},
        isDockMenuExpanded: .constant(false),
        dockAdapter: PracticeDockAdapter(store: store)
    )
    .previewEnvironment()
}

#Preview("Practice Page - Active Mode") {
    let store = PracticeStore.previewReadAloud
    PracticePageView(
        store: store,
        onNavigateToProfile: {},
        onNavigateToPrompts: {},
        isDockMenuExpanded: .constant(false),
        dockAdapter: PracticeDockAdapter(store: store)
    )
    .previewEnvironment()
}
