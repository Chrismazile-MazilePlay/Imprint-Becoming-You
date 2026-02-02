//
//  PromptsPageView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - PromptsPageView

/// The left page for AI prompt management.
///
/// Currently a placeholder that will be implemented in Phase 3
/// to provide custom prompt creation and management.
///
/// ## Planned Features
/// - Create custom prompts for personalized affirmations
/// - Edit and delete existing prompts
/// - View generated affirmations from prompts
/// - Claude API integration for generation
///
/// ## Navigation Architecture
/// Uses NavigationStack with standard toolbar for navigation.
/// The right chevron navigates to the center Practice page.
/// Mirrors the navigation structure of ProfilePageView.
struct PromptsPageView: View {
    
    // MARK: - Properties
    
    /// Callback to navigate to center (Practice) page
    let onNavigateToCenter: () -> Void
    
    /// Whether the horizontal pager is actively being dragged.
    /// Used to disable vertical scrolling during horizontal paging.
    /// (Reserved for future use when ScrollView is added)
    let isHorizontallyDragging: Bool
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                placeholderContent
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    forwardToPracticeButton
                }
            }
        }
        .tint(AppColors.accent)
    }
    
    // MARK: - Forward Button
    
    private var forwardToPracticeButton: some View {
        Button {
            onNavigateToCenter()
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                Text("Practice")
                    .font(AppTypography.body)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppColors.accent)
        }
        .accessibilityLabel("Go to Practice")
        .accessibilityHint("Navigate to the practice screen")
    }
    
    // MARK: - Placeholder Content
    
    private var placeholderContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            
            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(AppColors.accent.opacity(0.6))
                .accessibilityHidden(true)
            
            // Title
            Text("AI Prompts")
                .font(AppTypography.title1)
                .foregroundStyle(AppColors.textPrimary)
            
            // Description
            Text("Create custom prompts to generate\npersonalized affirmations.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            // Coming soon badge
            Text("Coming Soon")
                .font(AppTypography.caption1.weight(.medium))
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppColors.accent.opacity(0.15))
                .clipShape(Capsule())
                .padding(.top, AppTheme.Spacing.md)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Prompts Page") {
    PromptsPageView(
        onNavigateToCenter: {},
        isHorizontallyDragging: false
    )
}

#Preview("Prompts Page - Dark") {
    PromptsPageView(
        onNavigateToCenter: {},
        isHorizontallyDragging: false
    )
    .preferredColorScheme(.dark)
}
