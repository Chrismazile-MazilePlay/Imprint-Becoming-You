//
//  SaveSessionSheet.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import SwiftUI

// MARK: - SaveSessionSheet

/// A bottom sheet for naming and saving a session.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │                                             │
/// │           Save Session                      │  ← Title
/// │                                             │
/// │  ┌─────────────────────────────────────┐   │
/// │  │  Session 1 - Jan 12                 │   │  ← Text field with default name
/// │  └─────────────────────────────────────┘   │
/// │                                             │
/// │  ⚠️ Free tier: 2 of 3 saved sessions      │  ← Limit warning (if applicable)
/// │                                             │
/// │  ┌─────────────────────────────────────┐   │
/// │  │             Save                    │   │  ← Save button
/// │  └─────────────────────────────────────┘   │
/// │                                             │
/// │              Cancel                         │  ← Cancel link
/// │                                             │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Behavior
/// - Pre-populates with auto-generated name ("Session X - Jan 12")
/// - Shows limit warning for free tier users approaching limit
/// - Disables save if at limit (free tier)
/// - Validates name is not empty
struct SaveSessionSheet: View {
    
    // MARK: - Properties
    
    /// The default session name (auto-generated)
    let defaultName: String
    
    /// Current count of saved sessions
    let currentSavedCount: Int
    
    /// Maximum allowed saved sessions (nil = unlimited/premium)
    let maxSavedSessions: Int?
    
    /// Callback when save is confirmed
    let onSave: (_ name: String) -> Void
    
    /// Callback when cancelled
    let onCancel: () -> Void
    
    // MARK: - State
    
    @State private var sessionName: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // MARK: - Computed Properties
    
    /// Whether the user is at their save limit
    private var isAtLimit: Bool {
        guard let max = maxSavedSessions else { return false }
        return currentSavedCount >= max
    }
    
    /// Whether the save button should be enabled
    private var canSave: Bool {
        !sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAtLimit
    }
    
    /// Remaining saves for display
    private var remainingSaves: Int {
        guard let maxAllowed = maxSavedSessions else { return Int.max }
        return max(0, maxAllowed - currentSavedCount)
    }
    
    /// Whether to show the limit warning
    private var showLimitWarning: Bool {
        guard let max = maxSavedSessions else { return false }
        // Show when at 2/3 or higher (approaching limit)
        return currentSavedCount >= max - 1
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            // Drag indicator
            dragIndicator
            
            // Title
            titleSection
            
            // Text field
            nameTextField
            
            // Limit warning (if applicable)
            if showLimitWarning {
                limitWarningSection
            }
            
            // Action buttons
            actionButtons
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.xxl)
        .background(AppColors.backgroundPrimary)
        .onAppear {
            sessionName = defaultName
            // Focus immediately - sheet animation handles visual transition
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Drag Indicator
    
    private var dragIndicator: some View {
        Capsule()
            .fill(AppColors.textTertiary.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, AppTheme.Spacing.sm)
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text("Save Session")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Save this combination of affirmations to practice again later.")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Name Text Field
    
    private var nameTextField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Session Name")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
            
            TextField("Enter a name", text: $sessionName)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppColors.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .stroke(isTextFieldFocused ? AppColors.accent : Color.clear, lineWidth: 2)
                )
                .focused($isTextFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    if canSave {
                        saveSession()
                    }
                }
                .disabled(isAtLimit)
        }
    }
    
    // MARK: - Limit Warning Section
    
    private var limitWarningSection: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: isAtLimit ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isAtLimit ? AppColors.warning : AppColors.textTertiary)
            
            if isAtLimit {
                Text("You've reached the free tier limit of \(maxSavedSessions ?? 3) saved sessions.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("Free tier: \(currentSavedCount) of \(maxSavedSessions ?? 3) saved sessions used.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small)
                .fill(isAtLimit ? AppColors.warning.opacity(0.1) : AppColors.backgroundSecondary)
        )
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Save button
            Button {
                saveSession()
            } label: {
                Text(isAtLimit ? "Upgrade to Save More" : "Save")
                    .font(AppTypography.headline)
                    .foregroundStyle(canSave ? AppColors.textPrimary : AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md + 4)
                    .background(
                        Capsule()
                            .fill(canSave ? AppColors.accent : AppColors.backgroundSecondary)
                    )
            }
            .disabled(!canSave && !isAtLimit)
            .accessibilityLabel(canSave ? "Save session" : "Cannot save - limit reached")
            
            // Cancel button
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityLabel("Cancel and return to results")
        }
    }
    
    // MARK: - Actions
    
    private func saveSession() {
        let trimmedName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isAtLimit else { return }
        onSave(trimmedName)
    }
}

// MARK: - Previews

#Preview("Save Session Sheet - Default") {
    SaveSessionSheet(
        defaultName: "Session 1 - Jan 12",
        currentSavedCount: 0,
        maxSavedSessions: 3,
        onSave: { name in print("Saved: \(name)") },
        onCancel: { print("Cancelled") }
    )
}

#Preview("Save Session Sheet - Approaching Limit") {
    SaveSessionSheet(
        defaultName: "Session 3 - Jan 12",
        currentSavedCount: 2,
        maxSavedSessions: 3,
        onSave: { name in print("Saved: \(name)") },
        onCancel: { print("Cancelled") }
    )
}

#Preview("Save Session Sheet - At Limit") {
    SaveSessionSheet(
        defaultName: "Session 4 - Jan 12",
        currentSavedCount: 3,
        maxSavedSessions: 3,
        onSave: { name in print("Saved: \(name)") },
        onCancel: { print("Cancelled") }
    )
}

#Preview("Save Session Sheet - Premium (Unlimited)") {
    SaveSessionSheet(
        defaultName: "Session 10 - Jan 12",
        currentSavedCount: 15,
        maxSavedSessions: nil,
        onSave: { name in print("Saved: \(name)") },
        onCancel: { print("Cancelled") }
    )
}
