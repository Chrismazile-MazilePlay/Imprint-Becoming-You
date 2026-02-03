//
//  GoalsSettingsView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/1/26.
//

import SwiftUI
import SwiftData

// MARK: - GoalsSettingsView

/// View for editing user goals with the same Save button pattern as other settings.
///
/// Features:
/// - Uses the reusable GoalPickerView component
/// - Changes are pending until Save is tapped
/// - Save button appears when selection differs from saved goals
/// - Save button appears when selection differs from saved goals, disables after save
/// - Reloads affirmations when saved
///
/// ## Navigation
/// This view is pushed onto the Profile navigation stack.
struct GoalsSettingsView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    /// PracticeStore for reloading affirmations after save
    @Bindable var store: PracticeStore
    
    // MARK: - State
    
    /// The goals that were last saved.
    /// Updated each time the user taps Save, so change detection stays reactive.
    @State private var savedGoals: Set<GoalCategory> = []
    
    /// The currently selected (pending) goals
    @State private var selectedGoals: Set<GoalCategory> = []
    
    // MARK: - Constants
    
    private let maxSelections = 5
    
    // MARK: - Computed Properties
    
    /// Whether the user has made changes that differ from the saved goals
    private var hasUnsavedChanges: Bool {
        selectedGoals != savedGoals
    }
    
    /// Whether faith-based categories should be excluded
    private var excludeFaithCategories: Bool {
        appState.userProfile?.includeFaithContent == false
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Goal picker (reusable component)
                GoalPickerView(
                    selectedGoals: $selectedGoals,
                    maxSelections: maxSelections,
                    showCounter: true,
                    excludeFaithCategories: excludeFaithCategories
                )
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SaveToolbarButton(
                    hasUnsavedChanges: hasUnsavedChanges,
                    accessibilityHint: "Saves your goal selections and updates affirmations",
                    onSave: { saveGoals() }
                )
            }
        }
        .onAppear {
            loadCurrentGoals()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Choose your focus areas")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            
            Text(hasUnsavedChanges ? "Tap Save to update your affirmations" : "Select up to \(maxSelections) goals")
                .font(AppTypography.caption1)
                .foregroundStyle(hasUnsavedChanges ? AppColors.accent : AppColors.textSecondary)
        }
        .padding(.vertical, AppTheme.Spacing.md)
    }
    
    // MARK: - Actions
    
    private func loadCurrentGoals() {
        if let profile = appState.userProfile {
            let goals = Set(profile.selectedGoals.compactMap { GoalCategory(rawValue: $0) })
            savedGoals = goals
            selectedGoals = goals
        }
    }
    
    private func saveGoals() {
        guard let profile = appState.userProfile else { return }
        
        // Update profile
        profile.selectedGoals = selectedGoals.map { $0.rawValue }
        try? modelContext.save()
        appState.updateProfile(profile)
        
        // Update saved baseline - hasUnsavedChanges becomes false
        savedGoals = selectedGoals
        
        // Reload affirmations with new categories
        let categories = selectedGoals.map { $0.rawValue }
        let repository = dependencies.makeAffirmationRepository(modelContext: modelContext)
        
        Task {
            await store.loadAffirmations(
                using: repository,
                forCategories: categories
            )
        }
        
        // Haptic feedback
        HapticFeedback.notification(.success)
        
        #if DEBUG
        print("GoalsSettingsView: Saved \(selectedGoals.count) goals")
        #endif
    }
}

// MARK: - Previews

#Preview("Goals Settings") {
    NavigationStack {
        GoalsSettingsView(store: .preview)
    }
    .previewEnvironment()
}

#Preview("Goals Settings - With Selections") {
    NavigationStack {
        GoalsSettingsView(store: .preview)
    }
    .previewEnvironment()
}
