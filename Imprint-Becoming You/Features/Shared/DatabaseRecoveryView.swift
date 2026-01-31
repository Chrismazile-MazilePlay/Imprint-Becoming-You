//
//  DatabaseRecoveryView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/30/26.
//

import SwiftUI

// MARK: - Database Recovery View

/// Full-screen view shown when SwiftData initialization fails completely.
///
/// This view provides users with recovery options when the app cannot
/// initialize its database. It offers:
/// - Clear explanation of what went wrong
/// - Option to reset app data (delete corrupted database)
/// - Option to continue in limited mode (in-memory only)
/// - Technical details for support purposes
///
/// ## Design Philosophy
/// - Uses the app's standard design tokens for visual consistency
/// - Prioritizes user understanding over technical details
/// - Provides actionable recovery options
/// - Maintains accessibility standards
struct DatabaseRecoveryView: View {
    
    // MARK: - Properties
    
    /// The error message describing what went wrong
    let errorMessage: String
    
    /// Callback when user chooses to reset app data
    let onReset: () -> Void
    
    /// Callback when user chooses to continue without persistent data
    let onContinue: () -> Void
    
    // MARK: - State
    
    @State private var showResetConfirmation = false
    @State private var showTechnicalDetails = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    Spacer()
                        .frame(height: AppTheme.Spacing.xxl)
                    
                    // Error Icon
                    errorIcon
                    
                    // Title and Description
                    titleSection
                    
                    Spacer()
                        .frame(height: AppTheme.Spacing.lg)
                    
                    // Action Buttons
                    actionButtons
                    
                    // Technical Details (Expandable)
                    technicalDetailsSection
                    
                    Spacer()
                        .frame(height: AppTheme.Spacing.xxl)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
        }
        .alert("Reset All Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                onReset()
            }
        } message: {
            Text("This will delete all your affirmations, progress, saved sessions, and settings. This action cannot be undone.")
        }
    }
    
    // MARK: - Subviews
    
    /// Warning icon at the top of the view
    private var errorIcon: some View {
        ZStack {
            Circle()
                .fill(AppColors.warning.opacity(0.15))
                .frame(width: 120, height: 120)
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)
        }
        .accessibilityHidden(true)
    }
    
    /// Title and description text
    private var titleSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text("Unable to Load Data")
                .font(AppTypography.title1)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("There was a problem loading your saved data. This may be caused by a software update or data corruption.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
    
    /// Primary and secondary action buttons
    private var actionButtons: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Reset Button (Primary Action)
            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Reset App Data")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColors.accent)
                .foregroundStyle(AppColors.textInverted)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            }
            .accessibilityLabel("Reset app data")
            .accessibilityHint("Deletes all saved data and allows a fresh start. Requires confirmation.")
            
            // Continue Button (Secondary Action)
            Button {
                onContinue()
            } label: {
                Text("Continue Without Saving")
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AppColors.backgroundSecondary)
                    .foregroundStyle(AppColors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Continue without saving")
            .accessibilityHint("Use the app but your progress will not be saved between sessions")
            
            // Explanation for continue option
            Text("If you continue, the app will work but your data won't be saved when you close it.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, AppTheme.Spacing.xs)
        }
    }
    
    /// Expandable technical details for support
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Button {
                withAnimation(AppTheme.Animation.quick) {
                    showTechnicalDetails.toggle()
                }
            } label: {
                HStack {
                    Text("Technical Details")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Spacer()
                    
                    Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .accessibilityLabel("Technical details")
            .accessibilityValue(showTechnicalDetails ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to \(showTechnicalDetails ? "hide" : "show") error details")
            
            if showTechnicalDetails {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Error:")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text(errorMessage)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(AppTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small))
                    
                    // Copy button for support purposes
                    Button {
                        UIPasteboard.general.string = errorMessage
                    } label: {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                            Text("Copy to Clipboard")
                                .font(AppTypography.caption1)
                        }
                        .foregroundStyle(AppColors.accent)
                    }
                    .padding(.top, AppTheme.Spacing.xs)
                    .accessibilityLabel("Copy error to clipboard")
                    .accessibilityHint("Copies the error message for sharing with support")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, AppTheme.Spacing.lg)
    }
}

// MARK: - Fallback Warning Banner

/// A non-blocking banner shown when the app is running in fallback mode.
///
/// This is used when persistent storage fails but in-memory storage works.
/// Shows a dismissible warning that data won't persist.
struct DatabaseFallbackBanner: View {
    
    /// Callback when user dismisses the banner
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.warning)
            
            Text("Data won't be saved between sessions")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityLabel("Dismiss warning")
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.warning.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small))
    }
}

// MARK: - Preview

#Preview("Database Recovery View") {
    DatabaseRecoveryView(
        errorMessage: "Failed to load persistent stores: The file couldn't be opened because you don't have permission to view it.",
        onReset: { print("Reset tapped") },
        onContinue: { print("Continue tapped") }
    )
}

#Preview("Fallback Banner") {
    VStack {
        DatabaseFallbackBanner(onDismiss: { })
            .padding()
        
        Spacer()
    }
    .background(AppColors.backgroundPrimary)
}
