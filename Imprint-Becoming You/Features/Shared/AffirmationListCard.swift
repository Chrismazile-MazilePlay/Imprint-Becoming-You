//
//  AffirmationListCard.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - AffirmationListCard

/// A unified card component for displaying affirmations in list contexts.
///
/// Used across Results Summary and Favorites views with context-appropriate
/// content while maintaining consistent styling.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │  [Category Chip]                                                │
/// │                                                                 │
/// │  "I am confident and capable of achieving my goals..."         │
/// │                                                                 │
/// │  Score: 87%  (Results)  OR  Saved 2 days ago  (Favorites)      │
/// │                                                           ♡    │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Contexts
/// - **Results**: Shows resonance score (if scored) or "Skipped" indicator
/// - **Favorites**: Shows "Saved X ago" timestamp
struct AffirmationListCard: View {
    
    // MARK: - Card Context
    
    /// The context in which the card is displayed
    enum Context {
        /// Results summary view - shows score or skipped status
        case results(score: Int?, loopCount: Int, wasSkipped: Bool)
        
        /// Favorites view - shows saved date
        case favorites(savedAt: Date?)
        
        /// Saved session info sheet - category chip only, no metadata
        case savedSessionInfo
    }
    
    // MARK: - Properties
    
    /// The affirmation text to display
    let text: String
    
    /// Optional category for the category chip
    let category: GoalCategory?
    
    /// The display context determining secondary content
    let context: Context
    
    /// Whether this affirmation is favorited
    let isFavorited: Bool
    
    /// Callback when favorite button is tapped
    let onToggleFavorite: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Category chip (if available)
            if let category = category {
                CategoryBadge(category: category)
            }
            
            // Affirmation text
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding(.top, AppTheme.Spacing.xs)
            
            // Bottom row: Context-specific content + Favorite button (same row)
            // Hidden for savedSessionInfo context
            if case .savedSessionInfo = context {
                // No bottom row for saved session info
            } else {
                HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                    contextContent
                    
                    Spacer(minLength: 0)
                    
                    // Favorite button
                    Button {
                        onToggleFavorite()
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppColors.backgroundSecondary)
        )
    }
    
    // MARK: - Context Content
    
    @ViewBuilder
    private var contextContent: some View {
        switch context {
        case .results(let score, let loopCount, let wasSkipped):
            resultsContent(score: score, loopCount: loopCount, wasSkipped: wasSkipped)
            
        case .favorites(let savedAt):
            favoritesContent(savedAt: savedAt)
            
        case .savedSessionInfo:
            // No metadata shown - just category chip and text
            EmptyView()
        }
    }
    
    // MARK: - Results Content
    
    @ViewBuilder
    private func resultsContent(score: Int?, loopCount: Int, wasSkipped: Bool) -> some View {
        if wasSkipped {
            // Skipped indicator
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("Skipped")
                    .font(AppTypography.caption1.weight(.medium))
            }
            .foregroundStyle(AppColors.textTertiary)
        } else if let score = score {
            // Score display
            HStack(spacing: AppTheme.Spacing.sm) {
                // Score badge
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(score)%")
                        .font(AppTypography.caption1.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(scoreColor(for: score))
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(
                    Capsule()
                        .fill(scoreColor(for: score).opacity(0.15))
                )
                
                // Loop indicator (if multiple loops)
                if loopCount > 1 {
                    Text("×\(loopCount)")
                        .font(AppTypography.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        } else {
            // No score (Read Aloud mode)
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("Completed")
                    .font(AppTypography.caption1.weight(.medium))
            }
            .foregroundStyle(AppColors.success)
        }
    }
    
    // MARK: - Favorites Content
    
    @ViewBuilder
    private func favoritesContent(savedAt: Date?) -> some View {
        if let date = savedAt {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                Text("Saved \(date.formatted(.relative(presentation: .named)))")
                    .font(AppTypography.caption1)
            }
            .foregroundStyle(AppColors.textTertiary)
        }
    }
    
    // MARK: - Helpers
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...: return AppColors.success
        case 60..<80: return AppColors.warning
        default: return AppColors.textSecondary
        }
    }
}

// MARK: - Previews

#Preview("Results Card - Scored") {
    VStack(spacing: AppTheme.Spacing.md) {
        AffirmationListCard(
            text: "I am confident and capable of achieving my goals in every area of my life.",
            category: .confidence,
            context: .results(score: 92, loopCount: 1, wasSkipped: false),
            isFavorited: true,
            onToggleFavorite: {}
        )
        
        AffirmationListCard(
            text: "I embrace challenges as opportunities for growth and learning.",
            category: .growth,
            context: .results(score: 67, loopCount: 3, wasSkipped: false),
            isFavorited: false,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Results Card - Skipped") {
    AffirmationListCard(
        text: "My relationships are built on trust, respect, and genuine connection.",
        category: .relationships,
        context: .results(score: nil, loopCount: 1, wasSkipped: true),
        isFavorited: false,
        onToggleFavorite: {}
    )
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Results Card - Read Aloud (No Score)") {
    AffirmationListCard(
        text: "I am grateful for the abundance in my life.",
        category: .gratitude,
        context: .results(score: nil, loopCount: 1, wasSkipped: false),
        isFavorited: true,
        onToggleFavorite: {}
    )
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Favorites Card") {
    VStack(spacing: AppTheme.Spacing.md) {
        AffirmationListCard(
            text: "I am worthy of love, success, and happiness.",
            category: .confidence,
            context: .favorites(savedAt: Date().addingTimeInterval(-86400 * 2)),
            isFavorited: true,
            onToggleFavorite: {}
        )
        
        AffirmationListCard(
            text: "I trust in my ability to overcome any obstacle.",
            category: .resilience,
            context: .favorites(savedAt: Date().addingTimeInterval(-3600)),
            isFavorited: true,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Saved Session Info Card") {
    VStack(spacing: AppTheme.Spacing.md) {
        AffirmationListCard(
            text: "I am confident and capable of achieving my goals.",
            category: .confidence,
            context: .savedSessionInfo,
            isFavorited: false,
            onToggleFavorite: {}
        )
        
        AffirmationListCard(
            text: "I embrace challenges as opportunities for growth.",
            category: .growth,
            context: .savedSessionInfo,
            isFavorited: false,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
