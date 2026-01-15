//
//  ResultsSummaryHeaderView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//


//
//  ResultsSummaryHeaderView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - ResultsSummaryHeaderView

/// Header component for the Results Summary view.
///
/// Displays:
/// - A large checkmark icon indicating session completion
/// - Loop progress indicator (when in multi-loop session)
/// - "Continue to Next Loop" prompt (when more loops remain)
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                           ✓                                     │  ← Checkmark
/// │                    Loop 2 of 3                                  │  ← Loop progress
/// │              Continue to next loop?                             │  ← Prompt (if more loops)
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## States
/// - **Single Loop**: Shows only checkmark
/// - **Multi-Loop (more remain)**: Shows checkmark + "Loop X of Y" + "Continue" prompt
/// - **Multi-Loop (final)**: Shows checkmark + "Loop X of Y" + "Session Complete" text
struct ResultsSummaryHeaderView: View {
    
    // MARK: - Properties
    
    /// Current loop configuration
    let loopConfiguration: LoopConfiguration
    
    /// Whether this is a saved session being played
    let isPlayingSavedSession: Bool
    
    /// Optional saved session title
    let savedSessionTitle: String?
    
    // MARK: - Computed Properties
    
    /// Whether we're in a multi-loop session
    private var isMultiLoop: Bool {
        loopConfiguration.loopCount > 1
    }
    
    /// Whether there are more loops to complete
    private var hasMoreLoops: Bool {
        loopConfiguration.currentLoopIteration < loopConfiguration.loopCount
    }
    
    /// Loop progress text (e.g., "Loop 2 of 3")
    private var loopProgressText: String? {
        loopConfiguration.progressText
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Checkmark icon
            checkmarkIcon
            
            // Saved session context (if applicable)
            if isPlayingSavedSession, let title = savedSessionTitle {
                savedSessionLabel(title: title)
            }
            
            // Loop progress (if multi-loop)
            if isMultiLoop {
                loopProgressSection
            }
        }
        .padding(.top, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.md)
    }
    
    // MARK: - Checkmark Icon
    
    private var checkmarkIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 56, weight: .medium))
            .foregroundStyle(AppColors.success)
            .accessibilityLabel("Session completed")
    }
    
    // MARK: - Saved Session Label
    
    private func savedSessionLabel(title: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
            Text(title)
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(AppColors.textSecondary)
        .padding(.top, AppTheme.Spacing.xs)
    }
    
    // MARK: - Loop Progress Section
    
    private var loopProgressSection: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            // Loop X of Y
            if let progressText = loopProgressText {
                Text(progressText)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            // Status text
            if hasMoreLoops {
                Text("Continue to next loop?")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("All loops complete!")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.success)
            }
        }
    }
}

// MARK: - Previews

#Preview("Single Loop") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        ResultsSummaryHeaderView(
            loopConfiguration: .default,
            isPlayingSavedSession: false,
            savedSessionTitle: nil
        )
    }
}

#Preview("Multi-Loop - Mid Progress") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        ResultsSummaryHeaderView(
            loopConfiguration: LoopConfiguration(
                loopCount: 3,
                isShuffleEnabled: false,
                currentLoopIteration: 2
            ),
            isPlayingSavedSession: false,
            savedSessionTitle: nil
        )
    }
}

#Preview("Multi-Loop - Final Loop") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        ResultsSummaryHeaderView(
            loopConfiguration: LoopConfiguration(
                loopCount: 3,
                isShuffleEnabled: true,
                currentLoopIteration: 3
            ),
            isPlayingSavedSession: false,
            savedSessionTitle: nil
        )
    }
}

#Preview("Saved Session") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        ResultsSummaryHeaderView(
            loopConfiguration: .default,
            isPlayingSavedSession: true,
            savedSessionTitle: "Morning Confidence"
        )
    }
}

#Preview("Saved Session - Multi-Loop") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        ResultsSummaryHeaderView(
            loopConfiguration: LoopConfiguration(
                loopCount: 5,
                isShuffleEnabled: true,
                currentLoopIteration: 3
            ),
            isPlayingSavedSession: true,
            savedSessionTitle: "Evening Gratitude"
        )
    }
}