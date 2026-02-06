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
/// ## Active Mode Behavior
/// When in an active session mode (Read Aloud, Read & Speak, Speak Only),
/// horizontal swiping is completely disabled. User must exit the mode
/// to navigate between pages.
///
/// ## Dock Menu Behavior
/// When dock selector menus (Mode or Binaural) are expanded on the Practice
/// page, horizontal paging is disabled. This prevents accidental page
/// navigation while interacting with dock controls. The `DockMenuDismissModifier`
/// handles closing menus on touch, and the next swipe navigates normally.
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
///
/// Navigation:
/// - AI button (top-left) -> slides to Prompts page (left) [home mode only]
/// - Profile button (top-right) -> slides to Profile page (right) [home mode only]
/// - Categories button -> full-screen cover (no slide)
/// - Swipe left/right -> Works in home mode (simultaneous with vertical paging)
struct MainPracticeView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - State
    
    /// The single source of truth for practice state
    @State private var store = PracticeStore()
    @State private var currentPage: AppPage = .practice
    @State private var isInitialized = false
    
    /// Whether the save session sheet is showing
    @State private var showingSaveSessionSheet = false
    
    /// Current count of saved sessions (for limit display)
    @State private var savedSessionCount: Int = 0
    
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
    
    // MARK: - Computed Properties
    
    /// Whether the horizontal pager gesture should be enabled.
    ///
    /// Disabled when:
    /// - Active session is running (user focused on practice)
    /// - Profile has navigation depth > 0 (let NavigationStack handle back gesture)
    /// - Dock selector menus are expanded (prevent navigation during menu interaction)
    private var isPagerGestureEnabled: Bool {
        // Disable during active sessions
        guard !store.isSessionActive else { return false }
        
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
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            if isInitialized {
                // Horizontal page navigation
                pageContent
            } else {
                // Loading state
                loadingView
            }
        }
        .task {
            await initializePractice()
        }
        .onChange(of: store.isSessionActive) { wasActive, isActive in
            // When exiting active mode, ensure we're on practice page
            if wasActive && !isActive {
                currentPage = .practice
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
    
    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            // Base content layer
            if store.isSessionActive && !store.isShowingSummary {
                // ACTIVE SESSION MODE: Show only PracticePageView
                // No pager, no navigation - user is focused on practice
                PracticePageView(
                    store: store,
                    onNavigateToProfile: { }, // Disabled in active mode
                    onNavigateToPrompts: { }, // Disabled in active mode
                    isDockMenuExpanded: $isDockMenuExpanded
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else if !store.isShowingSummary {
                // HOME MODE: HorizontalPager with three pages
                // Uses .simultaneousGesture() so both horizontal paging and
                // VerticalPager's vertical swiping work concurrently.
                // Direction locking in each pager routes events to the correct axis.
                HorizontalPager(
                    currentPage: currentPageIndex,
                    pageCount: AppPage.allCases.count,
                    isGestureEnabled: isPagerGestureEnabled,
                    isHorizontallyDragging: $isHorizontallyDragging
                ) {
                    // Page 0: Prompts (Left)
                    PromptsPageView(
                        onNavigateToCenter: { navigateToPage(.practice) },
                        isHorizontallyDragging: isHorizontallyDragging
                    )
                    
                    // Page 1: Practice (Center - Main)
                    PracticePageView(
                        store: store,
                        onNavigateToProfile: { navigateToPage(.profile) },
                        onNavigateToPrompts: { navigateToPage(.prompts) },
                        isDockMenuExpanded: $isDockMenuExpanded
                    )
                    
                    // Page 2: Profile (Right)
                    ProfilePageView(
                        store: store,
                        onNavigateToCenter: { navigateToPage(.practice) },
                        navigationDepth: $profileNavigationDepth,
                        isHorizontallyDragging: isHorizontallyDragging,
                        isActive: currentPage == .profile,
                        resetScrollToTop: $resetProfileScroll
                    )
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
            
            // Results Summary overlay with slide-down dismissal
            if store.isShowingSummary {
                ResultsSummaryView(
                    summary: store.sessionSummary,
                    loopConfiguration: store.loopConfiguration,
                    isPlayingSavedSession: store.isPlayingSavedSession,
                    isFavoritesSession: store.isFavoritesSession,
                    isSessionSaved: store.hasSessionBeenSaved,
                    onClose: {
                        dismissSummary()
                    },
                    onRepeat: { mode, loopCount, shuffle in
                        store.send(.repeatSessionWithConfig(mode: mode, loopCount: loopCount, shuffle: shuffle))
                    },
                    onSaveSession: {
                        refreshSavedSessionCount()
                        showingSaveSessionSheet = true
                    },
                    onToggleFavorite: { affirmationId in
                        store.send(.toggleFavoriteInSummary(affirmationId))
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10) // Ensure summary is on top
                .sheet(isPresented: $showingSaveSessionSheet) {
                    SaveSessionSheet(
                        defaultName: PracticeStore.generateDefaultSessionName(),
                        currentSavedCount: savedSessionCount,
                        maxSavedSessions: Constants.FreeTier.maxSavedSessions,
                        onSave: { name in
                            store.send(.saveSession(name: name))
                            showingSaveSessionSheet = false
                        },
                        onCancel: {
                            showingSaveSessionSheet = false
                        }
                    )
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
                }
            }
            
            // Timeout Alert overlay
            if store.isShowingTimeoutAlert {
                TimeoutAlertView(
                    affirmationText: store.currentAffirmation?.text ?? "",
                    onRetry: {
                        store.send(.retryListening)
                    },
                    onSkip: {
                        store.send(.skipAffirmation)
                    },
                    onExit: {
                        store.send(.exitSession)
                    }
                )
                .transition(.opacity)
                .zIndex(20) // Above summary
            }
            
            // Permission Denied Alert overlay
            if store.isShowingPermissionAlert {
                PermissionDeniedAlertView(
                    permissionType: store.deniedPermissionType.toViewType,
                    onOpenSettings: {
                        store.send(.openSettings)
                    },
                    onContinue: {
                        store.send(.continueWithoutPermission)
                    }
                )
                .transition(.opacity)
                .zIndex(20) // Above summary
            }
            
            // Session Preparation overlay
            if store.isPreparingSession {
                sessionPreparationOverlay
                    .transition(.opacity)
                    .zIndex(25) // Above everything
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether the "Start Now" button should be enabled for large sessions.
    ///
    /// Only applicable when:
    /// 1. Session is large (>30 affirmations)
    /// 2. At least 15 affirmations are ready
    private var canStartSessionEarly: Bool {
        let isLargeSession = store.sessionPreparationTarget > Constants.SessionPreparation.largeSessionThreshold
        guard isLargeSession else { return false }
        return store.sessionPreparedCount >= Constants.SessionPreparation.readyToStartThreshold
    }
    
    // MARK: - Session Preparation Overlay
    
    /// Session preparation view with phase-aware progress and fallback handling.
    ///
    /// Displays:
    /// - Smooth progress bar with phase-based animation
    /// - Game-style cycling status messages
    /// - "Start Now" button for large sessions (when 15+ ready)
    /// - Fallback UI on Kokoro timeout ("Continue with System Voice" / "Retry")
    @ViewBuilder
    private var sessionPreparationOverlay: some View {
        SessionPreparationView(
            phase: store.sessionPreparationPhase,
            preparedCount: store.sessionPreparedCount,
            totalCount: store.sessionPreparationTarget,
            fractionalProgress: store.sessionPreparationProgress,
            canStartEarly: canStartSessionEarly,
            onStartNow: {
                store.send(.sessionPreparationCompleted)
            },
            onContinueWithSystemVoice: {
                store.continueWithSystemVoice()
            },
            onRetry: {
                store.retrySessionPreparation()
            },
            onCancel: {
                store.send(.cancelSessionPreparation)
            }
        )
    }
    
    // MARK: - Summary Dismissal
    
    /// Dismisses the summary and returns to home.
    private func dismissSummary() {
        store.send(.dismissSummary)
    }
    
    // MARK: - Background Handling
    
    /// Handles app lifecycle transitions with centralized reset and memory management.
    ///
    /// ## Reset Hierarchy
    ///
    /// | Condition | Action |
    /// |-----------|--------|
    /// | Background >= 10 min (any state) | Full reset to home |
    /// | Background < 10 min (active session) | Resume segment from beginning |
    /// | Background < 10 min (summary) | Keep summary open (cache preserved for repeat) |
    /// | Background < 10 min (other) | No action |
    ///
    /// ## Memory Management
    /// MemoryManager uses a tiered session-aware strategy:
    /// - Active session/summary: Pipeline release deferred 45s, audio cache preserved.
    /// - No session: Stale caches cleared immediately, pipeline released after 5s.
    /// - Memory warnings: Hard release everything immediately.
    ///
    /// The host (MainPracticeView) is the single decision point for resets.
    /// PracticeStore executes the reset via events.
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Record when we entered background
            backgroundedAt = Date()
            
            // Pause active session (stop TTS, listening, timers)
            if store.isSessionActive {
                store.send(.pauseSession)
                
                #if DEBUG
                AppLogger.debug("Paused session on background", category: .practice)
                #endif
            }
            
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
            // Log memory status for debugging
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
                
                // Navigate to Practice page
                currentPage = .practice
                
                // Reset Profile scroll position (invisible since we're on Practice page)
                resetProfileScroll = true
                
                // Full state reset via centralized event
                store.send(.resetToHome)
                return
            }
            
            // ===============================================================
            // DECISION: Short background (<10 min) during summary
            // ACTION: Keep summary open — cache preserved for repeat/save
            // Extended background (>10 min) triggers .resetToHome above.
            // ===============================================================
            if store.isShowingSummary {
                #if DEBUG
                AppLogger.debug("Keeping summary open after short background (\(Int(timeInBackground))s)", category: .practice)
                #endif
                return
            }
            
            // ===============================================================
            // DECISION: Short background (<10 min) during active session
            // ACTION: Resume session, restart current segment from beginning
            // ===============================================================
            if store.isSessionActive {
                #if DEBUG
                AppLogger.debug("Resuming session after \(Int(timeInBackground))s in background", category: .practice)
                #endif
                store.send(.resumeSession)
                return
            }
            
            // No action needed for other states (home, profile, prompts)
            
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
    
    // MARK: - Helpers
    
    /// Refreshes the saved session count for limit display
    private func refreshSavedSessionCount() {
        guard let repo = store.savedSessionRepository else {
            savedSessionCount = 0
            return
        }
        
        do {
            savedSessionCount = try repo.count()
        } catch {
            savedSessionCount = 0
            #if DEBUG
            AppLogger.warning("Failed to get saved session count: \(error)", category: .practice)
            #endif
        }
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
        
        var body: some View {
            ZStack {
                PracticePageView(
                    store: store,
                    onNavigateToProfile: {},
                    onNavigateToPrompts: {},
                    isDockMenuExpanded: $isDockMenuExpanded
                )
            }
            .onAppear {
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
