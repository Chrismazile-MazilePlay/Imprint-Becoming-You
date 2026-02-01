//
//  AccountSettingsView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI

// MARK: - AccountSettingsView

/// Placeholder view for account management.
///
/// This view will be expanded to include:
/// - Sign in / Sign out functionality
/// - Account details and email
/// - Data sync settings
/// - Delete account option
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
struct AccountSettingsView: View {
    
    // MARK: - Environment
    
    @Environment(\.appState) private var appState
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()
                
                // Avatar
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 80))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.6))
                    .accessibilityHidden(true)
                
                // Status
                VStack(spacing: AppTheme.Spacing.sm) {
                    Text(appState.isAuthenticated ? "Signed In" : "Not Signed In")
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    
                    if appState.isAuthenticated {
                        Text("Account details will appear here")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                // Action card
                actionCard
                
                Spacer()
                
                // Coming soon
                Text("Account management coming soon")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                
                Spacer()
            }
            .padding(AppTheme.Spacing.xl)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Action Card
    
    private var actionCard: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            if appState.isAuthenticated {
                // Sign out button (placeholder)
                Button {
                    // TODO: Implement sign out
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18))
                        Text("Sign Out")
                            .font(AppTypography.headline)
                    }
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity)
                    .padding(AppTheme.Spacing.md)
                    .background(AppColors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                }
                .disabled(true) // Placeholder
                .opacity(0.5)
            } else {
                // Sign in button (placeholder)
                Button {
                    // TODO: Implement sign in
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 18))
                        Text("Sign In")
                            .font(AppTypography.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(AppTheme.Spacing.md)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                }
                .disabled(true) // Placeholder
                .opacity(0.5)
                
                Text("Create an account to sync your progress across devices")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
    }
}

// MARK: - Previews

#Preview("Account Settings - Not Signed In") {
    NavigationStack {
        AccountSettingsView()
    }
    .previewEnvironment()
}
