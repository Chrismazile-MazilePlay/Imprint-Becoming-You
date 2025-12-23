//
//  CategoriesFullScreenView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI
import SwiftData

// MARK: - CategoriesFullScreenView

/// Full-screen cover for category selection.
///
/// Presents the goal picker with a semi-transparent background,
/// keeping the context of what the user is selecting for.
struct CategoriesFullScreenView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appState) private var appState
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    
    // MARK: - State
    
    @State private var selectedGoals: Set<GoalCategory> = []
    @State private var hasChanges = false
    
    private let maxSelections = 5
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            AppColors.backgroundPrimary
                .opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Goal picker
                GoalPickerView(
                    selectedGoals: $selectedGoals,
                    maxSelections: maxSelections,
                    showCounter: true
                )
                .onChange(of: selectedGoals) { _, _ in
                    hasChanges = true
                }
                
                // Footer
                footer
            }
        }
        .onAppear {
            loadCurrentGoals()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(AppColors.surfaceTertiary)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Categories")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            // Invisible spacer for centering
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.md)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Save button
            Button {
                saveAndDismiss()
            } label: {
                Text(hasChanges ? "Save Changes" : "Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(selectedGoals.isEmpty)
            
            // Cancel/reset option
            if hasChanges && !selectedGoals.isEmpty {
                Button {
                    loadCurrentGoals()
                    hasChanges = false
                } label: {
                    Text("Reset to Current")
                }
                .buttonStyle(.ghost)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.xl)
        .background(
            LinearGradient(
                colors: [
                    AppColors.backgroundPrimary.opacity(0),
                    AppColors.backgroundPrimary.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .offset(y: -40),
            alignment: .top
        )
    }
    
    // MARK: - Actions
    
    private func loadCurrentGoals() {
        if let profile = appState.userProfile {
            selectedGoals = Set(
                profile.selectedGoals.compactMap { GoalCategory(rawValue: $0) }
            )
        }
    }
    
    private func saveAndDismiss() {
        if let profile = appState.userProfile {
            profile.selectedGoals = selectedGoals.map { $0.rawValue }
            try? modelContext.save()
            appState.updateProfile(profile)
        }
        
        // Reload affirmations with new categories
        Task {
            await viewModel.loadAffirmations(from: modelContext)
        }
        
        HapticFeedback.notification(.success)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Categories Full Screen") {
    CategoriesFullScreenView(viewModel: PracticeViewModel())
        .previewEnvironment()
}
