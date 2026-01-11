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
/// ## Affirmation Loading
/// On appear, loads affirmations from SwiftData filtered by user's selected
/// goals using the `AffirmationRepository` smart queue algorithm.
///
/// Navigation:
/// - AI button (top-left) ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ slides to Prompts page (left) [home mode only]
/// - Profile button (top-right) ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ slides to Profile page (right) [home mode only]
/// - Categories button ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ full-screen cover (no slide)
/// - Swipe left/right ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Only works in home mode
struct MainPracticeView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.appState) private var appState
    
    // MARK: - State
    
    /// The single source of truth for practice state
    @State private var store = PracticeStore()
    @State private var currentPage: AppPage = .practice
    @State private var isInitialized = false
    
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
                // ACTIVE MODE: No TabView, no horizontal swiping possible
                // Just show PracticePageView directly
                PracticePageView(
                    store: store,
                    onNavigateToProfile: { }, // Disabled in active mode
                    onNavigateToPrompts: { }  // Disabled in active mode
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else if !store.isShowingSummary {
                // HOME MODE: Full TabView with horizontal navigation
                TabView(selection: $currentPage) {
                    // Page 0: Prompts (Left)
                    PromptsPageView(
                        onNavigateToCenter: { navigateToPage(.practice) }
                    )
                    .tag(AppPage.prompts)
                    
                    // Page 1: Practice (Center - Main)
                    PracticePageView(
                        store: store,
                        onNavigateToProfile: { navigateToPage(.profile) },
                        onNavigateToPrompts: { navigateToPage(.prompts) }
                    )
                    .tag(AppPage.practice)
                    
                    // Page 2: Profile (Right)
                    ProfilePageView(
                        store: store,
                        onNavigateToCenter: { navigateToPage(.practice) }
                    )
                    .tag(AppPage.profile)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .transition(.opacity)
            }
            
            // Results Summary overlay with slide-down dismissal
            if store.isShowingSummary {
                ResultsSummaryView(
                    summary: store.sessionSummary,
                    onExit: {
                        dismissSummary(retry: false)
                    },
                    onRetry: {
                        dismissSummary(retry: true)
                    },
                    onToggleFavorite: { affirmationId in
                        store.send(.toggleFavoriteInSummary(affirmationId))
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10) // Ensure summary is on top
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
        }
    }
    
    // MARK: - Summary Dismissal
    
    /// Dismisses the summary with slide-down animation.
    ///
    /// - Parameter retry: If true, restarts session. If false, returns to home.
    private func dismissSummary(retry: Bool) {
        // First, update the store state (this prepares the underlying view)
        if retry {
            store.send(.retrySession)
        } else {
            store.send(.dismissSummary)
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
    }
    
    // MARK: - Navigation
    
    private func navigateToPage(_ page: AppPage) {
        // Block navigation when in active session mode
        guard !store.isSessionActive else { return }
        
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
        
        // Ensure we're on practice page when starting
        currentPage = .practice
        isInitialized = true
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
        
        var body: some View {
            ZStack {
                PracticePageView(
                    store: store,
                    onNavigateToProfile: {},
                    onNavigateToPrompts: {}
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
