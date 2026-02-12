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
/// - **Mode-Aware**: Shows completion status only for scoring modes (Read+Speak, Speak Only)
/// - **No Dynamic Width**: Internal elements never affect card width
///
/// ## Layout - Scoring Mode (Single Loop)
/// ```
/// +---------------------------------------------+
/// |  [Category Badge]                           |
/// |  "Affirmation text goes here..."            |
/// |                                             |
/// |    checkmark                           heart    |
/// |   Completed                                 |
/// +---------------------------------------------+
/// ```
///
/// ## Layout - Scoring Mode (Multiple Loops)
/// ```
/// +---------------------------------------------+
/// |  [Category Badge]                           |
/// |  "Affirmation text goes here..."            |
/// |                                             |
/// |   check  check  --  check  check       heart    |
/// |  Loop   Loop  Loop  Loop  Loop              |
/// |   1      2     3     4     5                |
/// +---------------------------------------------+
/// ```
///
/// ## Layout - Read Aloud Mode (No Status)
/// ```
/// +---------------------------------------------+
/// |  [Category Badge]                           |
/// |  "Affirmation text goes here..."            |
/// |                                        heart    |
/// +---------------------------------------------+
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

    /// Whether ALL loops were skipped (no completions at all) in a scoring mode
    private var allLoopsSkipped: Bool {
        result.isFromScoringMode && result.loopCompletions.isEmpty
    }

    /// Whether this is from a non-scoring mode (Read Aloud)
    private var isNonScoringMode: Bool {
        !result.isFromScoringMode
    }

    /// Whether to show the completion section
    private var shouldShowStatus: Bool {
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
                .padding(.top, shouldShowStatus ? AppTheme.Spacing.lg : AppTheme.Spacing.md)
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
        if shouldShowStatus {
            // Scoring mode: show completion status + favorite
            HStack(alignment: .center, spacing: 0) {
                statusDisplayArea
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

    // MARK: - Status Display Area

    @ViewBuilder
    private var statusDisplayArea: some View {
        if allLoopsSkipped {
            skippedDisplay
        } else if loopCount > 1 {
            multiLoopStatusDisplay
        } else {
            singleStatusDisplay
        }
    }

    // MARK: - Skipped Display

    private var skippedDisplay: some View {
        Text("Skipped")
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.textTertiary)
    }

    // MARK: - Single Status Display

    private var singleStatusDisplay: some View {
        VStack(alignment: .center, spacing: 2) {
            Image(systemName: result.wasCompleted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(result.wasCompleted ? AppColors.success : AppColors.textTertiary)

            Text(result.wasCompleted ? "Completed" : "Incomplete")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Multi-Loop Status Display

    private var multiLoopStatusDisplay: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            ForEach(1...loopCount, id: \.self) { loopNumber in
                loopStatusColumn(for: loopNumber)
            }
        }
    }

    /// A single column showing completion checkmark (or dash) and loop label.
    private func loopStatusColumn(for loopNumber: Int) -> some View {
        let completionForLoop = result.wasCompleted(forLoop: loopNumber)

        return VStack(alignment: .center, spacing: 4) {
            // Checkmark, X, or dash for not attempted
            if let completed = completionForLoop {
                Image(systemName: completed ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(completed ? AppColors.success : AppColors.textTertiary)
            } else {
                Text("\u{2014}")
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
}

// MARK: - Previews

#Preview("Completed") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: .sample,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Read Aloud - No Status") {
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

#Preview("Multiple Loops - All Completed") {
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
                loopCompletions: [true, true],
                isFromScoringMode: true
            ),
            loopCount: 3,
            onToggleFavorite: {}
        )

        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopCompletions: [true],
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
                loopCompletions: [true, true, true, true, true],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )

        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopCompletions: [true, true],
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
        // Short text, no status
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(text: "Short.", category: GoalCategory.confidence.rawValue),
                isFromScoringMode: false
            ),
            onToggleFavorite: {}
        )

        // Long text, with completions
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(
                    text: "This is a much longer affirmation text that will wrap to multiple lines and test the consistency of card widths across different content lengths.",
                    category: GoalCategory.peace.rawValue
                ),
                loopCompletions: [true, true, true],
                isFromScoringMode: true
            ),
            loopCount: 3,
            onToggleFavorite: {}
        )

        // Medium text, single completion
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: Affirmation(text: "Medium length affirmation.", category: GoalCategory.gratitude.rawValue),
                wasCompleted: true,
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
        // All 5 completed
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopCompletions: [true, true, true, true, true],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )

        // Some loops done
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopCompletions: [true, true, true],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )

        // All skipped
        SessionAffirmationCard(
            result: SessionAffirmationResult(
                affirmation: .sample,
                loopCompletions: [],
                isFromScoringMode: true
            ),
            loopCount: 5,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
