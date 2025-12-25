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
/// Navigation:
/// - AI button (top-left) → slides to Prompts page (left) [home mode only]
/// - Profile button (top-right) → slides to Profile page (right) [home mode only]
/// - Categories button → full-screen cover (no slide)
/// - Swipe left/right → Only works in home mode
struct MainPracticeView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var viewModel = PracticeViewModel()
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
        .onChange(of: viewModel.isSessionActive) { wasActive, isActive in
            // When exiting active mode, ensure we're on practice page
            if wasActive && !isActive {
                currentPage = .practice
            }
        }
        .alert(
            "Error",
            isPresented: $viewModel.showError,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") { viewModel.dismissError() }
        } message: { message in
            Text(message)
        }
    }
    
    // MARK: - Page Content
    
    @ViewBuilder
    private var pageContent: some View {
        if viewModel.isSessionActive {
            // ACTIVE MODE: No TabView, no horizontal swiping possible
            // Just show PracticePageView directly
            PracticePageView(
                viewModel: viewModel,
                onNavigateToProfile: { }, // Disabled in active mode
                onNavigateToPrompts: { }  // Disabled in active mode
            )
            .ignoresSafeArea()
        } else {
            // HOME MODE: Full TabView with horizontal navigation
            TabView(selection: $currentPage) {
                // Page 0: Prompts (Left)
                PromptsPageView(
                    onNavigateToCenter: { navigateToPage(.practice) }
                )
                .tag(AppPage.prompts)
                
                // Page 1: Practice (Center - Main)
                PracticePageView(
                    viewModel: viewModel,
                    onNavigateToProfile: { navigateToPage(.profile) },
                    onNavigateToPrompts: { navigateToPage(.prompts) }
                )
                .tag(AppPage.practice)
                
                // Page 2: Profile (Right)
                ProfilePageView(
                    viewModel: viewModel,
                    onNavigateToCenter: { navigateToPage(.practice) }
                )
                .tag(AppPage.profile)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
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
        guard !viewModel.isSessionActive else { return }
        
        withAnimation(AppTheme.Animation.standard) {
            currentPage = page
        }
    }
    
    // MARK: - Initialization
    
    private func initializePractice() async {
        await viewModel.loadAffirmations(from: modelContext)
        
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
        @State private var viewModel = PracticeViewModel()
        
        var body: some View {
            ZStack {
                PracticePageView(
                    viewModel: viewModel,
                    onNavigateToProfile: {},
                    onNavigateToPrompts: {}
                )
            }
            .onAppear {
                viewModel.affirmations = Affirmation.samples
                viewModel.dockManager.setMode(.readAloud)
            }
        }
    }
    
    return ActiveModePreview()
        .previewEnvironment()
}
