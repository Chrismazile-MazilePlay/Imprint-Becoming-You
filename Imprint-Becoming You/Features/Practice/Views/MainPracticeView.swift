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
enum AppPage: Int, CaseIterable, Sendable {
    case prompts = 0   // Left
    case practice = 1  // Center (default)
    case profile = 2   // Right
    
    /// Display name for debugging
    var name: String {
        switch self {
        case .prompts: return "Prompts"
        case .practice: return "Practice"
        case .profile: return "Profile"
        }
    }
}

// MARK: - MainPracticeView

/// The root view for the entire app experience.
///
/// A horizontal pager with three pages:
/// - **Left (Page 0)**: Prompts - AI prompt management
/// - **Center (Page 1)**: Practice - Affirmations with adaptive dock
/// - **Right (Page 2)**: Profile - Stats, progress, favorites, settings
///
/// ## Navigation
/// - AI button (top-left) → slides to Prompts page (left)
/// - Profile button (top-right) → slides to Profile page (right)
/// - Categories button → full-screen cover (no slide)
/// - Swipe left → Prompts
/// - Swipe right → Profile
///
/// ## Architecture
/// This view acts as the navigation coordinator, managing:
/// - Page state and transitions
/// - ViewModel lifecycle
/// - Initialization sequence
/// - Error presentation
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
            } else {
                // Loading state
                loadingView
            }
        }
        .task {
            await initializePractice()
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
        withAnimation(AppTheme.Animation.standard) {
            currentPage = page
        }
    }
    
    // MARK: - Initialization
    
    private func initializePractice() async {
        await viewModel.loadAffirmations(from: modelContext)
        isInitialized = true
    }
}

// MARK: - Previews

#Preview("Main Practice View") {
    MainPracticeView()
        .previewEnvironment()
}
