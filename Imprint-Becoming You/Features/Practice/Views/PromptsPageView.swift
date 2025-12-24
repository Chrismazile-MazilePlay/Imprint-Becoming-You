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
/// ## Navigation
/// - Right arrow navigates back to center Practice page
struct PromptsPageView: View {
    
    // MARK: - Properties
    
    /// Callback to navigate to center (Practice) page
    let onNavigateToCenter: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xl) {
                // Navigation header
                navigationHeader
                
                Spacer()
                
                // Placeholder content
                placeholderContent
                
                Spacer()
                Spacer()
            }
        }
    }
    
    // MARK: - Navigation Header
    
    private var navigationHeader: some View {
        HStack {
            Spacer()
            
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
            .accessibilityHint("Double tap to navigate to the practice page")
            .padding(.trailing, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.xl)
        }
    }
    
    // MARK: - Placeholder Content
    
    private var placeholderContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
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
        }
    }
}

// MARK: - Previews

#Preview("Prompts Page") {
    PromptsPageView(onNavigateToCenter: {})
}

#Preview("Prompts Page - Dark") {
    PromptsPageView(onNavigateToCenter: {})
        .preferredColorScheme(.dark)
}
