//
//  DeleteConfirmationPopup.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - DeleteConfirmationPopup

/// A custom styled confirmation popup for delete actions.
///
/// Matches the app's minimalist/stoic aesthetic with a centered modal
/// design, blur background, and clear action hierarchy.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────┐
/// │                                         │
/// │            🗑️ Delete Session            │
/// │                                         │
/// │   Are you sure you want to delete       │
/// │   "Morning Confidence"?                 │
/// │   This cannot be undone.                │
/// │                                         │
/// │  ┌─────────────────────────────────┐   │
/// │  │           Delete                │   │  ← Destructive action
/// │  └─────────────────────────────────┘   │
/// │                                         │
/// │  ┌─────────────────────────────────┐   │
/// │  │           Cancel                │   │  ← Safe action
/// │  └─────────────────────────────────┘   │
/// │                                         │
/// └─────────────────────────────────────────┘
/// ```
///
/// ## Usage
/// ```swift
/// @State private var showDeleteConfirmation = false
/// @State private var sessionToDelete: SavedSession?
///
/// // Present as overlay
/// .overlay {
///     if showDeleteConfirmation, let session = sessionToDelete {
///         DeleteConfirmationPopup(
///             title: "Delete Session",
///             itemName: session.name,
///             onConfirm: { deleteSession(session) },
///             onCancel: { showDeleteConfirmation = false }
///         )
///     }
/// }
/// ```
struct DeleteConfirmationPopup: View {
    
    // MARK: - Properties
    
    /// Title of the popup (e.g., "Delete Session")
    let title: String
    
    /// Name of the item being deleted (shown in quotes)
    let itemName: String
    
    /// Callback when delete is confirmed
    let onConfirm: () -> Void
    
    /// Callback when cancelled
    let onCancel: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    // Tapping outside cancels
                    onCancel()
                }
            
            // Popup card
            popupContent
        }
    }
    
    // MARK: - Popup Content
    
    private var popupContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Header
            headerSection
            
            // Message
            messageSection
            
            // Action buttons
            actionButtons
        }
        .padding(AppTheme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                .fill(AppColors.backgroundSecondary)
        )
        .padding(.horizontal, AppTheme.Spacing.xl)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "trash.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppColors.destructive)
            
            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
    
    // MARK: - Message Section
    
    private var messageSection: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text("Are you sure you want to delete")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            
            Text("\"\(itemName)\"?")
                .font(AppTypography.body.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Text("This cannot be undone.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, AppTheme.Spacing.xs)
        }
        .multilineTextAlignment(.center)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Delete button (destructive)
            Button {
                HapticFeedback.notification(.warning)
                onConfirm()
            } label: {
                Text("Delete")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .fill(AppColors.destructive)
                    )
            }
            .accessibilityLabel("Confirm delete")
            
            // Cancel button (safe)
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                            .fill(AppColors.backgroundTertiary)
                    )
            }
            .accessibilityLabel("Cancel delete")
        }
        .padding(.top, AppTheme.Spacing.sm)
    }
}

// MARK: - AppColors Extension

extension AppColors {
    /// Destructive action color (red)
    static var destructive: Color {
        Color(red: 0.9, green: 0.2, blue: 0.2)
    }
}

// MARK: - Previews

#Preview("Delete Confirmation - Session") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Text("Background content")
                .foregroundStyle(AppColors.textSecondary)
        }
        
        DeleteConfirmationPopup(
            title: "Delete Session",
            itemName: "Morning Confidence",
            onConfirm: { print("Deleted") },
            onCancel: { print("Cancelled") }
        )
    }
}

#Preview("Delete Confirmation - Long Name") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        DeleteConfirmationPopup(
            title: "Delete Session",
            itemName: "My Super Long Session Name That Might Wrap",
            onConfirm: {},
            onCancel: {}
        )
    }
}
