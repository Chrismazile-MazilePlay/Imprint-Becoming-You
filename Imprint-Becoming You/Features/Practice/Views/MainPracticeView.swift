//
//  MainPracticeView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI
import SwiftData

// MARK: - AppPage

/// Represents the three main pages of the app.
///
/// Page order supports natural navigation flow:
/// - Prompts (left) - AI features, no further navigation
/// - Practice (center) - Main experience
/// - Profile (right) - Settings, account, nested navigation flows right
enum AppPage: Int, CaseIterable {
    case prompts = 0   // Left
    case practice = 1  // Center (default)
    case profile = 2   // Right
}

// MARK: - MainPracticeView

/// The root view for the entire app experience.
///
/// A horizontal pager with three pages:
/// - **Left (Page 0)**: Prompts - AI prompt management
/// - **Center (Page 1)**: Practice - Affirmations with adaptive dock
/// - **Right (Page 2)**: Profile - Stats, progress, favorites, settings
///
/// ## FullScreenCover Architecture
/// Sessions are presented via `.fullScreenCover` over the pager. The cover
/// contains `SessionContainerView` which handles the entire session lifecycle:
/// loading, practice, alerts, and summary. This eliminates visible navigation
/// artifacts when starting sessions from Profile subpages.
///
/// ## Cosmetic Cleanup
/// When the cover presents from a non-Practice page (e.g., Profile → Favorites),
/// `SessionContainerView` signals `sessionCoverDidPresent` after a ~400ms delay
/// (allowing the present animation to complete). `MainPracticeView` then performs
/// an instant non-animated pager jump to Practice and pops Profile's NavigationStack.
/// This cleanup is invisible because the cover is fully opaque by then.
///
/// ## Active Mode Behavior
/// During an active session, horizontal swiping is disabled by the cover.
/// In browse mode, standard pager gestures work normally.
///
/// ## Dock Menu Behavior
/// When dock selector menus (Mode or Binaural) are expanded on the Practice
/// page, horizontal paging is disabled. This prevents accidental page
/// navigation while interacting with dock controls.
///
/// ## Memory Management
/// Coordinates with `MemoryManager` to release heavy resources (Kokoro ML pipelines)
/// when app enters background for extended periods. This prevents iOS from
/// terminating the app due to excessive memory usage.
///
/// ## Affirmation Loading
/// On appear, loads affirmations from SwiftData filtered by user's selected
/// goals using the `AffirmationRepository` smart queue algorithm.
///
/// ## Voice Selection
/// On appear, loads the user's selected voice from their profile and
/// configures the PracticeStore to use it for TTS playback.
struct MainPracticeView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    /// The single source of truth for practice state
    @State private var store = PracticeStore()

    /// Dock adapter for the home pager (behind fullScreenCover).
    ///
    /// Configured with `suppressSegments: true` to prevent phantom segment
    /// timers from running invisibly while the session cover is presented.
    /// Initialized lazily on first body evaluation since `store` is needed.
    @State private var homeDockAdapter: PracticeDockAdapter?

    @State private var currentPage: AppPage = .practice
    @State private var isInitialized = false

    /// Timestamp when app entered background (for timeout calculation)
    @State private var backgroundedAt: Date?

    /// Profile page's navigation depth, communicated via binding.
    /// Used to disable pager gestures when Profile has pushed views.
    @State private var profileNavigationDepth: Int = 0

    /// Whether the horizontal pager is actively being dragged.
    /// Communicated to child pages to disable their ScrollViews.
    @State private var isHorizontallyDragging: Bool = false

    /// Whether a dock selector menu (Mode or Binaural) is expanded.
    /// Relayed from PracticePageView via binding. When true, horizontal
    /// paging is disabled to prevent page navigation during menu interaction.
    @State private var isDockMenuExpanded: Bool = false

    /// Signal to reset Profile page's scroll position to the top.
    /// Set to `true` during full reset (extended background timeout).
    /// ProfilePageView observes this and resets scroll, then clears the flag.
    @State private var resetProfileScroll: Bool = false

    /// Signal to pop Profile's NavigationStack to root.
    /// Set to `true` during cosmetic cleanup when cover presents.
    @State private var popProfileToRoot: Bool = false

    /// Controls whether the next programmatic page change is animated.
    /// Set to `false` for instant behind-cover jumps, auto-resets to `true`.
    @State private var animatePageChange: Bool = true

    // MARK: - Computed Properties

    /// Whether the horizontal pager gesture should be enabled.
    ///
    /// Disabled when:
    /// - Session preparation (loading screen) is active
    /// - Profile has navigation depth > 0 (let NavigationStack handle back gesture)
    /// - Dock selector menus are expanded (prevent navigation during menu interaction)
    private var isPagerGestureEnabled: Bool {
        // Disable during session preparation (loading screen is showing)
        guard !store.isPreparingSession else { return false }

        // Disable when Profile has navigation depth (NavigationStack needs the gesture)
        guard profileNavigationDepth == 0 else { return false }

        // Disable when dock menus are expanded (DockMenuDismissModifier closes them on touch)
        guard !isDockMenuExpanded else { return false }

        return true
    }

    /// Binding to convert AppPage to Int for HorizontalPager
    private var currentPageIndex: Binding<Int> {
        Binding(
            get: { currentPage.rawValue },
            set: { currentPage = AppPage(rawValue: $0) ?? .practice }
        )
    }

    /// Binding for `isSessionPresented` on the store.
    /// Used by `.fullScreenCover(isPresented:onDismiss:content:)`.
    private var sessionPresentedBinding: Binding<Bool> {
        Binding(
            get: { store.isSessionPresented },
            set: { store.setSessionPresented($0) }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            if isInitialized {
                // Horizontal page navigation (ALWAYS present — never replaced)
                pageContent
            } else {
                // Loading state
                loadingView
            }
        }
        .fullScreenCover(isPresented: sessionPresentedBinding, onDismiss: {
            store.send(.sessionCoverDismissed)
        }) {
            SessionContainerView(store: store)
        }
        .task {
            await initializePractice()
        }
        .onChange(of: store.sessionCoverDidPresent) { _, didPresent in
            // Behind-cover cleanup: triggered by SessionContainerView after the
            // fullScreenCover present animation completes (~400ms delay).
            // The cover is now fully opaque, so the instant pager jump and
            // Profile pop are invisible to the user.
            if didPresent {
                animatePageChange = false
                currentPage = .practice
                popProfileToRoot = true
                store.sessionCoverDidPresent = false
            }
        }
        .onChange(of: appState.userProfile?.selectedVoiceId) { _, newVoiceId in
            // Update store voice when user changes it in settings
            updateStoreVoice(from: newVoiceId)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .alert(
            "Error",
            isPresented: errorBinding,
            presenting: store.error
        ) { _ in
            Button("OK") { store.send(.dismissError) }
        } message: { error in
            Text(error.userMessage)
        }
    }

    /// Binding for error alert presentation
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.error != nil },
            set: { if !$0 { store.send(.dismissError) } }
        )
    }

    // MARK: - Page Content

    /// The main pager — always present, never conditionally replaced.
    ///
    /// Sessions are presented via `.fullScreenCover` (above), so this pager
    /// remains mounted during the entire app lifecycle. No more conditional
    /// branching between session/home/summary — the cover handles all of that.
    @ViewBuilder
    private var pageContent: some View {
        HorizontalPager(
            currentPage: currentPageIndex,
            pageCount: AppPage.allCases.count,
            isGestureEnabled: isPagerGestureEnabled,
            isHorizontallyDragging: $isHorizontallyDragging,
            animatePageChange: $animatePageChange
        ) {
            // Page 0: Prompts (Left)
            PromptsPageView(
                onNavigateToCenter: { navigateToPage(.practice) },
                isHorizontallyDragging: isHorizontallyDragging
            )

            // Page 1: Practice (Center - Main)
            if let homeDockAdapter {
                PracticePageView(
                    store: store,
                    onNavigateToProfile: { navigateToPage(.profile) },
                    onNavigateToPrompts: { navigateToPage(.prompts) },
                    isDockMenuExpanded: $isDockMenuExpanded,
                    dockAdapter: homeDockAdapter
                )
            }

            // Page 2: Profile (Right)
            ProfilePageView(
                store: store,
                onNavigateToCenter: { navigateToPage(.practice) },
                navigationDepth: $profileNavigationDepth,
                isHorizontallyDragging: isHorizontallyDragging,
                isActive: currentPage == .profile,
                resetScrollToTop: $resetProfileScroll,
                popToRoot: $popProfileToRoot
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Background Handling

    /// Handles app lifecycle transitions with centralized reset and memory management.
    ///
    /// ## Reset Hierarchy
    ///
    /// | Condition | Action |
    /// |-----------|--------|
    /// | Background >= 10 min (any state) | Full reset to home |
    /// | Background < 10 min (active session in cover) | Handled by SessionContainerView |
    /// | Background < 10 min (other) | No action |
    ///
    /// ## Memory Management
    /// MemoryManager uses a tiered session-aware strategy:
    /// - Active session/summary: Pipeline release deferred 45s, audio cache preserved.
    /// - No session: Stale caches cleared immediately, pipeline released after 5s.
    /// - Memory warnings: Hard release everything immediately.
    ///
    /// Note: Short-background pause/resume for active sessions is now handled by
    /// `SessionContainerView`'s own `scenePhase` observer. This handler only
    /// manages the extended background timeout (full reset).
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Record when we entered background
            backgroundedAt = Date()

            #if DEBUG
            AppLogger.debug("App entered background", category: .practice)
            MemoryManager.shared.logMemoryUsage()
            #endif

            // MemoryManager handles delayed memory release via its own background observer

        case .active:
            // Only handle if we were actually backgrounded (backgroundedAt was set)
            // Note: Phase transitions go Background -> Inactive -> Active, so oldPhase
            // will be .inactive, not .background. We use backgroundedAt to track this.
            guard let backgroundTime = backgroundedAt else { return }

            let timeInBackground = Date().timeIntervalSince(backgroundTime)
            backgroundedAt = nil

            #if DEBUG
            AppLogger.debug("Returned from background after \(Int(timeInBackground))s", category: .practice)
            MemoryManager.shared.logMemoryUsage()
            #endif

            // ===============================================================
            // MEMORY: MemoryManager handles resource release/restore automatically
            // ===============================================================
            if timeInBackground >= Constants.Background.memoryReleaseThreshold {
                #if DEBUG
                AppLogger.debug("Memory threshold reached (\(Int(timeInBackground))s)", category: .practice)
                let memoryMB = MemoryManager.shared.currentMemoryUsageMB()
                AppLogger.debug("Current memory usage: \(memoryMB)MB", category: .practice)
                AppLogger.debug("MemoryManager released = \(MemoryManager.shared.hasReleasedForBackground)", category: .practice)
                #endif
            }

            // ===============================================================
            // DECISION: Extended background (>= 10 min) from ANY state
            // ACTION: Full reset to home (Practice page, Read Only mode)
            // ===============================================================
            if timeInBackground >= Constants.Background.sessionTimeout {
                #if DEBUG
                AppLogger.debug("Full reset after \(Int(timeInBackground))s in background", category: .practice)
                #endif

                // Navigate to Practice page (instant, no animation after background)
                animatePageChange = false
                currentPage = .practice

                // Reset Profile scroll position (invisible since we're on Practice page)
                resetProfileScroll = true

                // Reset gesture-blocking state that lives in MainPracticeView's @State
                // (not in PracticeStore, so resetToHome doesn't clear these)

                // Pop Profile NavigationStack to root (clears profileNavigationDepth → 0)
                popProfileToRoot = true

                // Close any stale dock menus / error bars on the home adapter
                homeDockAdapter?.closeAllSelectors()

                // Safety: force-clear in case adapter is nil or onChange hasn't fired
                isDockMenuExpanded = false

                // Full state reset via centralized event
                store.send(.resetToHome)
                return
            }

            // Short background handling for active sessions is now in SessionContainerView.
            // No action needed here for short backgrounds.

        case .inactive:
            // No action needed for inactive state
            break

        @unknown default:
            break
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.5)

            Text("Preparing your practice...")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading. Preparing your practice.")
    }

    // MARK: - Navigation

    private func navigateToPage(_ page: AppPage) {
        // Block navigation when in active session mode
        guard !store.isSessionActive else { return }

        // Close any open selectors before navigating
        store.send(.closeSelectors)

        withAnimation(AppTheme.Animation.standard) {
            currentPage = page
        }
    }

    // MARK: - Initialization

    private func initializePractice() async {
        // Get user's selected goals from profile
        let categories = appState.userProfile?.selectedGoals ?? []

        // Create repository for this context
        let repository = dependencies.makeAffirmationRepository(modelContext: modelContext)

        // Load affirmations using repository with user's selected categories
        await store.loadAffirmations(
            using: repository,
            forCategories: categories
        )

        // Initialize saved session repository
        store.savedSessionRepository = dependencies.makeSavedSessionRepository(modelContext: modelContext)

        // Initialize voice selection from user profile
        updateStoreVoice(from: appState.userProfile?.selectedVoiceId)

        // Create the home dock adapter with suppressed segments.
        // Must be created before isInitialized triggers PracticePageView rendering.
        if homeDockAdapter == nil {
            homeDockAdapter = PracticeDockAdapter(store: store, suppressSegments: true)
        }

        // Ensure we're on practice page when starting
        currentPage = .practice
        isInitialized = true
    }

    // MARK: - Voice Configuration

    /// Updates the store's voice ID from the user profile's stored voice.
    ///
    /// Now passes the full Voice.id directly (e.g., "kokoro_af_heart").
    /// The TTSService handles conversion to raw engine format internally.
    /// This ensures VoiceSettingsManager lookups work correctly since
    /// settings are stored by full Voice.id.
    private func updateStoreVoice(from storedVoiceId: String?) {
        // Pass full Voice.id directly - TTSService handles conversion
        store.selectedVoiceId = storedVoiceId

        #if DEBUG
        AppLogger.debug("Set voice to \(storedVoiceId ?? "default")", category: .practice)
        #endif
    }
}

// MARK: - Previews

#Preview("Main Practice View") {
    MainPracticeView()
        .previewEnvironment()
}

#Preview("Main - Active Mode (No Swipe)") {
    // This preview shows that horizontal swiping is blocked
    struct ActiveModePreview: View {
        @State private var store = PracticeStore()
        @State private var isDockMenuExpanded = false
        @State private var dockAdapter: PracticeDockAdapter?

        var body: some View {
            ZStack {
                if let dockAdapter {
                    PracticePageView(
                        store: store,
                        onNavigateToProfile: {},
                        onNavigateToPrompts: {},
                        isDockMenuExpanded: $isDockMenuExpanded,
                        dockAdapter: dockAdapter
                    )
                }
            }
            .onAppear {
                dockAdapter = PracticeDockAdapter(store: store)
                store.send(.affirmationsLoaded(Affirmation.samples))
                store.send(.selectMode(.readAloud))
            }
        }
    }

    return ActiveModePreview()
        .previewEnvironment()
}

// MARK: - PermissionType Conversion

extension PermissionType {
    /// Converts to the view-layer PermissionType for PermissionDeniedAlertView.
    ///
    /// Note: The `notifications` case maps to `microphone` as a fallback since
    /// PermissionDeniedAlertView is only used for audio-related permissions.
    var toViewType: PermissionDeniedAlertView.PermissionType {
        switch self {
        case .microphone:
            return .microphone
        case .speechRecognition:
            return .speechRecognition
        case .both:
            return .both
        case .notifications:
            // Notifications permission is not handled by PermissionDeniedAlertView
            // This case should not occur in practice flow, but we need exhaustive matching
            return .microphone
        }
    }
}
