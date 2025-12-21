//
//  OnboardingContainerView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - OnboardingContainerView

/// Container view that coordinates the onboarding flow.
///
/// Manages navigation between:
/// 1. Welcome screen
/// 2. Goal selection
/// 3. Voice calibration
/// 4. Completion
///
/// ## Usage
/// ```swift
/// OnboardingContainerView()
///     .environment(\.appState, appState)
/// ```
struct OnboardingContainerView: View {
    
    // MARK: - Environment
    
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - State
    
    @State private var viewModel = OnboardingViewModel()
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                if viewModel.currentStep != .welcome {
                    OnboardingProgressBar(progress: viewModel.overallProgress)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.md)
                }
                
                // Content
                TabView(selection: $viewModel.currentStep) {
                    WelcomeView(viewModel: viewModel)
                        .tag(OnboardingStep.welcome)
                    
                    GoalSelectionView(viewModel: viewModel)
                        .tag(OnboardingStep.goalSelection)
                    
                    VoiceCalibrationView(viewModel: viewModel)
                        .tag(OnboardingStep.calibration)
                    
                    OnboardingCompleteView(viewModel: viewModel)
                        .tag(OnboardingStep.complete)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppTheme.Animation.standard, value: viewModel.currentStep)
            }
        }
        .alert(
            "Error",
            isPresented: $viewModel.showError,
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") {
                viewModel.dismissError()
            }
        } message: { message in
            Text(message)
        }
    }
}

// MARK: - OnboardingProgressBar

/// Progress bar showing advancement through onboarding
struct OnboardingProgressBar: View {
    
    /// Current progress (0.0 - 1.0)
    let progress: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.full)
                    .fill(AppColors.surfaceTertiary)
                    .frame(height: 4)
                
                // Progress fill
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.full)
                    .fill(AppColors.accent)
                    .frame(
                        width: max(0, geometry.size.width * CGFloat(progress)),
                        height: 4
                    )
                    .animation(AppTheme.Animation.standard, value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(Int(progress * 100)) percent complete")
    }
}

// MARK: - OnboardingPageTemplate

/// Reusable template for onboarding pages
struct OnboardingPageTemplate<Content: View, Footer: View>: View {
    
    /// Page title
    let title: String
    
    /// Page subtitle/description
    let subtitle: String
    
    /// Main content
    @ViewBuilder let content: () -> Content
    
    /// Footer content (buttons)
    @ViewBuilder let footer: () -> Footer
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.xl)
            
            // Content
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Footer
            footer()
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xl)
        }
    }
}

// MARK: - Previews

#Preview("Onboarding Flow") {
    OnboardingContainerView()
        .previewEnvironment()
}

#Preview("Progress Bar") {
    VStack(spacing: 20) {
        OnboardingProgressBar(progress: 0)
        OnboardingProgressBar(progress: 0.33)
        OnboardingProgressBar(progress: 0.66)
        OnboardingProgressBar(progress: 1.0)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
