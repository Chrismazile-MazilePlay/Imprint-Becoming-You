//
//  SessionContainerView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - SessionDestination

/// Navigation destinations within the session fullScreenCover.
///
/// Used with NavigationStack's type-safe path for session flow:
/// - Root: PracticePageView + overlays (session UI)
/// - `.summary`: Pushed when session completes
enum SessionDestination: Hashable {
    case summary
}

// MARK: - SessionContainerView

/// Container view for the fullScreenCover session experience.
///
/// ## Architecture
/// ```
/// SessionContainerView
/// └── ZStack
///     ├── Opaque base (swappable — solid color or backgroundPrimary)
///     └── NavigationStack(path: $sessionPath)
///         ├── Root: ZStack {
///         │   ├── PracticePageView (session — renders morphing/solid background + content + HUD/dock)
///         │   ├── TimeoutAlertView (zIndex 20)
///         │   ├── PermissionDeniedAlertView (zIndex 20)
///         │   └── SessionPreparationView (zIndex 25)
///         │   }
///         └── .navigationDestination(.summary)
///             └── ResultsSummaryView (no own NavigationStack)
/// ```
///
/// ## Key Behaviors
/// - **Immediate presentation**: Cover presents as soon as user taps Play/mode
/// - **Opaque base**: Prevents see-through to home during loading and transitions
/// - **NavigationStack push for summary**: Animated push within the cover
/// - **`interactiveDismissDisabled()`**: Prevents accidental swipe-to-dismiss
/// - **`onChange(of: store.isShowingSummary)`**: Coordinates NavigationStack path
/// - **Scene phase handling**: Pause on background, resume on foreground (with summary guard)
///
/// ## Dismiss Pattern
/// All dismiss paths call `store.setSessionPresented(false)`. The cover animates down,
/// then `onDismiss` fires in `MainPracticeView` which sends `.sessionCoverDismissed`
/// for consolidated state cleanup.
struct SessionContainerView: View {

    // MARK: - Environment

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appState) private var appState

    // MARK: - Properties

    @Bindable var store: PracticeStore

    // MARK: - State

    /// Navigation path for session → summary transitions.
    @State private var sessionPath: [SessionDestination] = []

    /// Whether the save session sheet is showing.
    @State private var showingSaveSessionSheet = false

    /// Current count of saved sessions (for limit display).
    @State private var savedSessionCount: Int = 0

    /// Whether a dock selector menu is expanded.
    /// Communicated from PracticePageView via binding.
    @State private var isDockMenuExpanded: Bool = false

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

    // MARK: - Body

    var body: some View {
        ZStack {
            // Opaque base layer — prevents see-through to home.
            // Uses solid color for user-selected backgrounds, or backgroundPrimary for morphing.
            opaqueBaseLayer
                .ignoresSafeArea()

            NavigationStack(path: $sessionPath) {
                // Session root content
                sessionRootContent
                    .navigationBarHidden(true)
                    .navigationDestination(for: SessionDestination.self) { destination in
                        switch destination {
                        case .summary:
                            summaryDestination
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: store.isShowingSummary) { _, isShowingSummary in
            if isShowingSummary {
                // Push summary onto NavigationStack (animated)
                sessionPath.append(.summary)
            } else {
                // Pop summary (animated)
                sessionPath = []
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleSessionScenePhase(from: oldPhase, to: newPhase)
        }
        .onAppear {
            // Signal MainPracticeView that the cover is fully presented.
            // Delay allows the fullScreenCover present animation (~350ms)
            // to complete so the behind-cover cleanup (instant pager jump
            // to Practice + Profile pop) is invisible to the user.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                store.sessionCoverDidPresent = true
            }
        }
    }

    // MARK: - Opaque Base Layer

    /// Renders the opaque base layer based on user's background preference.
    ///
    /// - Solid color backgrounds: renders that color
    /// - Morphing gradient: renders `AppColors.backgroundPrimary` (black base)
    @ViewBuilder
    private var opaqueBaseLayer: some View {
        let style = appState.userProfile?.backgroundStyle ?? .morphingGradient
        if let solidColor = style.solidColor {
            solidColor
        } else {
            AppColors.backgroundPrimary
        }
    }

    // MARK: - Session Root Content

    /// The root of the session NavigationStack — practice UI with overlays.
    private var sessionRootContent: some View {
        ZStack {
            // Practice page view (renders background + content + HUD + dock)
            PracticePageView(
                store: store,
                onNavigateToProfile: { },  // Disabled in session
                onNavigateToPrompts: { },  // Disabled in session
                isDockMenuExpanded: $isDockMenuExpanded
            )
            .ignoresSafeArea()

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
                .zIndex(20)
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
                .zIndex(20)
            }

            // Session Preparation overlay (loading screen)
            if store.isPreparingSession {
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
                .transition(.opacity)
                .zIndex(25)
            }
        }
    }

    // MARK: - Summary Destination

    /// ResultsSummaryView configured as a NavigationStack destination.
    private var summaryDestination: some View {
        ResultsSummaryView(
            summary: store.sessionSummary,
            loopConfiguration: store.loopConfiguration,
            isPlayingSavedSession: store.isPlayingSavedSession,
            isFavoritesSession: store.isFavoritesSession,
            isSessionSaved: store.hasSessionBeenSaved,
            onClose: {
                store.send(.dismissSummary)
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
        .navigationBarBackButtonHidden(true)
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

    // MARK: - Scene Phase Handling

    /// Handles background/foreground transitions within the session cover.
    ///
    /// - Background: Pauses session (stops TTS, listening, timers)
    /// - Foreground: Resumes session (only if not showing summary)
    ///
    /// Note: Extended background timeout is handled by `MainPracticeView`.
    /// This handler only manages pause/resume within the cover.
    private func handleSessionScenePhase(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Cancel session preparation if loading screen is showing
            if store.isPreparingSession {
                store.send(.cancelSessionPreparation)
            }

            // Pause active session
            if store.isSessionActive {
                store.send(.pauseSession)
            }

        case .active:
            // Guard: Don't resume during summary (TTS should not auto-play)
            guard !store.isShowingSummary else { return }

            // Resume active session
            if store.isSessionActive {
                store.send(.resumeSession)
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Helpers

    /// Refreshes the saved session count for limit display.
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

#Preview("Session Container") {
    SessionContainerView(store: .preview)
        .previewEnvironment()
}
