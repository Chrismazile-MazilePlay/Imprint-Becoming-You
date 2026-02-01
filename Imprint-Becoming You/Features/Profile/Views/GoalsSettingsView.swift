//
//  GoalsSettingsView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - GoalsSettingsView

/// Placeholder view for editing user goals.
///
/// This view will be expanded to allow users to:
/// - View their current selected goals
/// - Add or remove goal categories
/// - Reorder goals by priority
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
struct GoalsSettingsView: View {
    
    // MARK: - Environment
    
    @Environment(\.appState) private var appState
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()
                
                // Icon
                Image(systemName: "target")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.accentSecondary.opacity(0.6))
                    .accessibilityHidden(true)
                
                // Title
                Text("Goals Settings")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                
                // Current goals summary
                currentGoalsSummary
                
                // Coming soon
                Text("Goal customization coming soon")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
                
                Spacer()
            }
            .padding(AppTheme.Spacing.xl)
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Current Goals Summary
    
    private var currentGoalsSummary: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            let goals = appState.userProfile?.selectedGoals ?? []
            
            if goals.isEmpty {
                Text("No goals selected")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("Your current goals:")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                
                FlowLayout(spacing: AppTheme.Spacing.sm) {
                    ForEach(goals, id: \.self) { goal in
                        goalChip(goal)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
    
    private func goalChip(_ goal: String) -> some View {
        Text(goal)
            .font(AppTypography.caption1)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.accentSecondary.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Previews

#Preview("Goals Settings") {
    NavigationStack {
        GoalsSettingsView()
    }
    .previewEnvironment()
}
