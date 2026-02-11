//
//  BackgroundSelectionView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/9/26.
//

import SwiftUI

// MARK: - BackgroundSelectionView

/// Settings screen for selecting the practice background style.
///
/// Displays a scrollable grid of background options with preview cards.
/// Uses the pending/saved state pattern — changes only persist when Save is tapped.
///
/// ## Behavior
/// - Tap a card to select it (pending until Save is tapped)
/// - Save button appears when selection differs from saved style
/// - After save: saved baseline updates → button disappears
///
/// ## Navigation
/// This view is pushed onto the Profile NavigationStack via `.backgroundStyle` destination.
struct BackgroundSelectionView: View {

    // MARK: - Environment

    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    /// The style that was last saved.
    /// Updated each time the user taps Save, so change detection stays reactive.
    @State private var savedStyle: BackgroundStyle = .morphingGradient

    /// The currently selected (pending) style.
    @State private var pendingStyle: BackgroundStyle = .morphingGradient

    /// Whether the view has loaded its initial style from the profile.
    @State private var hasLoadedInitialStyle: Bool = false

    // MARK: - Computed Properties

    /// Whether the user has made a change that differs from the saved style.
    private var hasUnsavedChanges: Bool {
        pendingStyle != savedStyle
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // Header description
                headerSection

                // Background options grid
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(BackgroundStyle.allCases) { style in
                        BackgroundPreviewCard(
                            style: style,
                            isSelected: pendingStyle == style
                        )
                        .onTapGesture {
                            selectStyle(style)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SaveToolbarButton(
                    hasUnsavedChanges: hasUnsavedChanges,
                    accessibilityHint: "Saves \(pendingStyle.displayName) as your background style",
                    onSave: { saveSelection() }
                )
            }
        }
        .onAppear {
            guard !hasLoadedInitialStyle else { return }
            hasLoadedInitialStyle = true
            let style = appState.userProfile?.backgroundStyle ?? .morphingGradient
            savedStyle = style
            pendingStyle = style
        }
    }

    // MARK: - Grid Columns

    /// Adaptive grid layout: 2 columns on most devices, adapts for larger screens.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 16)]
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Choose a background for your practice sessions.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Text(hasUnsavedChanges ? "Tap Save to confirm your selection" : "Tap to select")
                .font(AppTypography.caption1)
                .foregroundStyle(hasUnsavedChanges ? AppColors.accent : AppColors.textTertiary)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // MARK: - Selection

    private func selectStyle(_ style: BackgroundStyle) {
        guard pendingStyle != style else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            pendingStyle = style
        }

        // Haptic feedback for selection
        HapticFeedback.selection()

        #if DEBUG
        print("BackgroundSelectionView: Pending selection \(style.displayName)")
        #endif
    }

    // MARK: - Save

    private func saveSelection() {
        // Update the profile
        appState.userProfile?.backgroundStyleRawValue = pendingStyle.rawValue

        // Persist to SwiftData
        try? modelContext.save()

        // Update saved baseline — hasUnsavedChanges becomes false
        savedStyle = pendingStyle

        // Haptic feedback for save
        HapticFeedback.notification(.success)

        #if DEBUG
        print("BackgroundSelectionView: Saved \(pendingStyle.displayName)")
        #endif
    }
}

// MARK: - Previews

#Preview("Background Selection View") {
    NavigationStack {
        BackgroundSelectionView()
    }
    .previewEnvironment()
}
