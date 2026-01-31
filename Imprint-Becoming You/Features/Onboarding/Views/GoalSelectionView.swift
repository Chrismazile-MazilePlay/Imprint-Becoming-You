//
//  GoalSelectionView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - GoalSelectionView

/// Goal selection screen for onboarding flow.
///
/// Wraps the reusable `GoalPickerView` with onboarding-specific
/// header, footer, and navigation logic.
///
/// ## Faith Content Filtering
/// This view respects the user's faith preference from the previous
/// onboarding step. If `includeFaithContent` is `false`, the
/// Faith & Bible-Based group is hidden from the picker.
///
/// Features:
/// - Custom header with title and instructions
/// - Reusable goal picker component
/// - Continue button with validation
/// - Clear selection option
struct GoalSelectionView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Reusable goal picker (counter is shown here, not in picker)
            GoalPickerView(
                selectedGoals: $viewModel.selectedGoals,
                maxSelections: viewModel.maxGoals,
                showCounter: true,
                excludeFaithCategories: viewModel.includeFaithContent == false
            )
            
            // Footer
            footer
        }
        .accessibilityElement(children: .contain)
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("What matters to you?")
                .font(AppTypography.title1)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            
            Text("Choose up to \(viewModel.maxGoals) areas to focus your affirmations")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What matters to you? Choose up to \(viewModel.maxGoals) areas to focus your affirmations")
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Button {
                viewModel.nextStep()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(!viewModel.canProceedFromGoals)
            .accessibilityLabel("Continue")
            .accessibilityHint(viewModel.canProceedFromGoals ? "Proceed to next step" : "Select at least one goal to continue")
            
            if !viewModel.selectedGoals.isEmpty {
                Button {
                    viewModel.clearGoals()
                } label: {
                    Text("Clear Selection")
                }
                .buttonStyle(.ghost)
                .accessibilityLabel("Clear selection")
                .accessibilityHint("Remove all selected goals")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.xl)
    }
}

// MARK: - Previews

#Preview("Goal Selection - Empty") {
    GoalSelectionView(viewModel: OnboardingViewModel())
        .background(AppColors.backgroundPrimary)
}

#Preview("Goal Selection - With Selections") {
    let vm = OnboardingViewModel()
    vm.includeFaithContent = true
    vm.selectedGoals = [.confidence, .faith, .abundance]
    
    return GoalSelectionView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
}

#Preview("Goal Selection - Faith Excluded") {
    let vm = OnboardingViewModel()
    vm.includeFaithContent = false
    vm.selectedGoals = [.confidence, .focus]
    
    return GoalSelectionView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
}
