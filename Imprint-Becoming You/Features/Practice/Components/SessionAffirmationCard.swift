//
//  SessionAffirmationCard.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import SwiftUI

// MARK: - SessionAffirmationCard

/// A card displaying a single affirmation result in the Results Summary.
///
/// ## Design Principles
/// - **Consistent Width**: Card ALWAYS takes full available width via `frame(maxWidth: .infinity)`
/// - **Mode-Aware**: Shows scores only for scoring modes (Read+Speak, Speak Only)
/// - **No Dynamic Width**: Internal elements never affect card width
///
/// ## Layout - Scoring Mode (Single Loop)
/// ```
/// ┌─────────────────────────────────────────────┐
/// │  [Category Badge]                           │
/// │  "Affirmation text goes here..."            │
/// │                                             │
/// │    87                                  ♡    │
/// │   Score                                     │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Layout - Scoring Mode (Multiple Loops)
/// ```
/// ┌─────────────────────────────────────────────┐
/// │  [Category Badge]                           │
/// │  "Affirmation text goes here..."            │
/// │                                             │
/// │  87    91    —     88    92            ♡    │
/// │ Loop  Loop  Loop  Loop  Loop                │
/// │  1     2     3     4     5                  │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Layout - Read Aloud Mode (No Scores)
/// ```
/// ┌─────────────────────────────────────────────┐
/// │  [Category Badge]                           │
/// │  "Affirmation text goes here..."            │
/// │                                        ♡    │
/// └─────────────────────────────────────────────┘
/// ```
struct SessionAffirmationCard: View {
    
    // MARK: - Properties
    
    /// The affirmation result to display
    let result: SessionAffirmationResult
    
    /// Total number of loops in the session (needed to show all labels)
    let loopCount: Int
    
    /// Callback when favorite is toggled
    let onToggleFavorite: () -> Void
    
    // MARK: - Convenience Init
    
    /// Creates a card for single-loop sessions
    init(result: SessionAffirmationResult, onToggleFavorite: @escaping () -> Void) {
        self.result = result
        self.loopCount = 1
        self.onToggleFavorite = onToggleFavorite
    }
    
    /// Creates a card for multi-loop sessions
    init(result: SessionAffirmationResult, loopCount: Int, onToggleFavorite: @escaping () -> Void) {
        self.result = result
        self.loopCount = loopCount
        self.onToggleFavorite = onToggleFavorite
    }
    
    // MARK: - Computed Properties
    
    /// Whether ALL loops were skipped (no scores at all) in a scoring mode
    private var allLoopsSkipped: Bool {
        result.isFromScoringMode && result.loopScores.isEmpty
    }
    
    /// Whether this is from a non-scoring mode (Read Aloud)
    private var isNonScoringMode: Bool {
        !result.isFromScoringMode
    }
    
    /// Whether to show the score section
    private var shouldShowScores: Bool {
        result.isFromScoringMode
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category badge
            if let category = result.goalCategory {
                CategoryBadge(category: category)
                    .padding(.bottom, AppTheme.Spacing.md)
            }
            
            // Affirmation text
            Text(result.text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Bottom section
            bottomSection
                .padding(.top, shouldShowScores ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
        }
        .padding(AppTheme.Spacing.lg)
        // CRITICAL: Force full width - this ensures ALL cards are identical width
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppColors.backgroundSecondary)
        )
    }
    
    // MARK: - Bottom Section
    
    @ViewBuilder
    private var bottomSection: some View {
        if shouldShowScores {
            // Scoring mode: show scores + favorite
            HStack(alignment: .center, spacing: 0) {
                scoreDisplayArea
                Spacer(minLength: AppTheme.Spacing.md)
                favoriteHeart
            }
        } else {
            // Non-scoring mode (Read Aloud): just favorite aligned right
            HStack {
                Spacer()
                favoriteHeart
            }
        }
    }
    
    // MARK: - Score Display Area
    
    @ViewBuilder
    private var scoreDisplayArea: some View {
        if allLoopsSkipped {
            skippedDisplay
        } else if loopCount > 1 {
            multiLoopScoreDisplay
        } else if let score = result.score {
            singleScoreDisplay(score: score)
        }
    }
    
    // MARK: - Skipped Display
    
    private var skippedDisplay: some View {
        Text("Skipped")
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.textTertiary)
    }
    
    // MARK: - Single Score Display
    
    private func singleScoreDisplay(score: Int) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text("\(score)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(for: score))
            
            Text("Score")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
    }
    
    // MARK: - Multi-Loop Score Display
    
    private var multiLoopScoreDisplay: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            ForEach(1...loopCount, id: \.self) { loopNumber in
                loopScoreColumn(for: loopNumber)
            }
        }
    }
    
    /// A single column showing score (or dash) and loop label.
    private func loopScoreColumn(for loopNumber: Int) -> some View {
        let scoreForLoop = result.score(forLoop: loopNumber)
        
        return VStack(alignment: .center, spacing: 4) {
            // Score or dash for skipped
            if let score = scoreForLoop {
                Text("\(score)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(for: score))
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.3))
            }
            
            // Loop label
            VStack(spacing: 0) {
                Text("Loop")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                Text("\(loopNumber)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(width: 40) // Fixed width per column
    }
    
    // MARK: - Favorite Heart
    
    private var favoriteHeart: some View {
        Button {
            onToggleFavorite()
        } label: {
            Image(systemName: result.isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(result.isFavorited ? AppColors.accent : AppColors.textSecondary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(result.isFavorited ? "Remove from favorites" : "Add to favorites")
    }
    
    // MARK: - Helpers
    
    private func scoreColor(for score: Int) -> Color {
        if score >= 90 {
            return AppColors.success
        } else if score >= 70 {
            return AppColors.accent
        } else {
            return AppColors.textSecondary
        }
    }
}

// MARK: - Previews

#Preview("Single Score") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: .sample,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Read Aloud - No Scores") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                isFromScoringMode: false
            ),
            onToggleFavorite: {}
        )
        
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(
                    text: "A much longer affirmation that spans multiple lines to test the card layout and ensure width consistency.",
                    category: GoalCategory.confidence.rawValue
                ),
                isFromScoringMode: false
            ),
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("All Skipped") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: .sampleSkipped,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Multiple Loops - All Scored") {
    SessionAffirmationCard(
        result: .sampleWithLoops,
        loopCount: 3,
        onToggleFavorite: {}
    )
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Multiple Loops - Some Skipped") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [87, 91],
                isFromScoringMode: true
            ),
            loopCount: 3,
            onToggleFavorite: {}
        )
        
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [91],
                isFromScoringMode: true
            ),
            loopCount: 3,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("5 Loops - Various States") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [87, 91, 95, 88, 92],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )
        
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [87, 91],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Width Consistency Test") {
    VStack(spacing: AppTheme.Spacing.md) {
        // Short text, no scores
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(text: "Short.", category: GoalCategory.confidence.rawValue),
                isFromScoringMode: false
            ),
            onToggleFavorite: {}
        )
        
        // Long text, with scores
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(
                    text: "This is a much longer affirmation text that will wrap to multiple lines and test the consistency of card widths across different content lengths.",
                    category: GoalCategory.peace.rawValue
                ),
                loopScores: [87, 91, 95],
                isFromScoringMode: true
            ),
            loopCount: 3,
            onToggleFavorite: {}
        )
        
        // Medium text, single score
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(text: "Medium length affirmation.", category: GoalCategory.gratitude.rawValue),
                loopScores: [85],
                isFromScoringMode: true
            ),
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("5 Loops Mixed") {
    VStack(spacing: AppTheme.Spacing.md) {
        // All 5 scored
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [87, 91, 88, 90, 88],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )
        
        // Some skipped
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [91, 90, 88],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )
        
        // All skipped
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopScores: [],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
