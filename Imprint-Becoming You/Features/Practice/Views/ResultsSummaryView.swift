//
//  ResultsSummaryView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import SwiftUI

// MARK: - ResultsSummaryView

/// Displays the results of a completed practice session.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │  [X]                                        │  ← Floating exit button
/// │                                             │
/// │              ✓                              │  ← SF Symbol
/// │        Session Complete                     │  ← Title
/// │                                             │
/// │  ┌─────────────────────────────────────┐   │
/// │  │  Scored Card 1                      │   │
/// │  └─────────────────────────────────────┘   │
/// │  ┌─────────────────────────────────────┐   │  ← Scored affirmations first
/// │  │  Scored Card 2                      │   │
/// │  └─────────────────────────────────────┘   │
/// │  ┌─────────────────────────────────────┐   │
/// │  │  Skipped Card 1                     │   │  ← Skipped affirmations after
/// │  └─────────────────────────────────────┘   │
/// │                                             │
/// │  ┌─────────────────────────────────────┐   │
/// │  │        Retry Session                │   │  ← Full width button
/// │  └─────────────────────────────────────┘   │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Ordering
/// Results are displayed with scored affirmations first (in original order),
/// followed by skipped affirmations (in original order).
///
/// ## Dismissal
/// - **Exit button**: Slide down dismiss → shows home/default mode
/// - **Retry Session**: Slide down dismiss → shows restarted session
struct ResultsSummaryView: View {
    
    // MARK: - Properties
    
    /// The session summary to display
    let summary: SessionSummary
    
    /// Callback when exit is tapped
    let onExit: () -> Void
    
    /// Callback when retry is tapped
    let onRetry: () -> Void
    
    /// Callback when favorite is toggled for an affirmation
    /// - Parameter affirmationId: The ID of the affirmation to toggle
    let onToggleFavorite: (_ affirmationId: UUID) -> Void
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            AppColors.backgroundPrimary
                .ignoresSafeArea()
            
            // Scrollable content - cards scroll behind the exit button
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Header (with top padding to clear exit button)
                    headerSection
                        .padding(.top, 60) // Clear the floating exit button area
                    
                    // Affirmation cards (sorted: scored first, then skipped)
                    cardsSection
                    
                    // Retry button
                    retryButton
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xxl)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            
            // Floating exit button - stays fixed, content scrolls behind it
            exitButton
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(AppColors.success)
            
            // Title
            Text("Session Complete")
                .font(AppTypography.title1)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.top, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.lg)
    }
    
    // MARK: - Cards Section
    
    private var cardsSection: some View {
        LazyVStack(spacing: AppTheme.Spacing.md) {
            ForEach(summary.sortedResults) { result in
                SessionAffirmationCard(
                    result: result,
                    onToggleFavorite: {
                        onToggleFavorite(result.affirmationId)
                    }
                )
            }
        }
    }
    
    // MARK: - Retry Button
    
    private var retryButton: some View {
        Button {
            onRetry()
        } label: {
            Text("Retry Session")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.md + 4)
                .background(
                    Capsule()
                        .fill(AppColors.accent)
                )
        }
        .accessibilityLabel("Retry this session with the same affirmations")
    }
    
    // MARK: - Exit Button
    
    private var exitButton: some View {
        Button {
            onExit()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(AppColors.backgroundSecondary)
                )
        }
        .padding(.top, AppTheme.Spacing.xl)
        .padding(.leading, AppTheme.Spacing.lg)
        .accessibilityLabel("Exit and return to home")
    }
}

// MARK: - Previews

#Preview("Results Summary View - Scoring Mode") {
    ResultsSummaryView(
        summary: .sample,
        onExit: {},
        onRetry: {},
        onToggleFavorite: { _ in }
    )
}

#Preview("Results Summary - Read Aloud") {
    ResultsSummaryView(
        summary: SessionSummary(
            mode: .readAloud,
            results: SessionAffirmationResult.samplesReadAloud,
            startedAt: Date().addingTimeInterval(-300)
        ),
        onExit: {},
        onRetry: {},
        onToggleFavorite: { _ in }
    )
}

#Preview("Results Summary - Mixed (Scored + Skipped)") {
    ResultsSummaryView(
        summary: .sample,
        onExit: {},
        onRetry: {},
        onToggleFavorite: { _ in }
    )
}
