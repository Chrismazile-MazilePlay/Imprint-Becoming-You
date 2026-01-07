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
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │  [Category Badge]                           │
/// │                                             │
/// │  "Affirmation text goes here and can       │
/// │   wrap to multiple lines..."               │
/// │                                             │
/// │  87                              [♡]        │
/// │  Score                        Favorite     │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Design
/// - Rounded corners, subtle background
/// - Category badge at top
/// - Full affirmation text
/// - Score (numeric) and favorite button at bottom
struct SessionAffirmationCard: View {
    
    // MARK: - Properties
    
    /// The affirmation result to display
    let result: SessionAffirmationResult
    
    /// Callback when favorite is toggled
    let onToggleFavorite: () -> Void
    
    // MARK: - Local State
    
    /// Local favorite state for immediate UI feedback
    @State private var isFavorited: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Category badge
            if let category = result.goalCategory {
                CategoryBadge(category: category)
            }
            
            // Affirmation text
            Text(result.text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Bottom row: Score and Favorite
            HStack(alignment: .bottom) {
                // Score display area
                // - Has score: show score number
                // - No score + scoring mode: show "Skipped"
                // - No score + non-scoring mode (Read Aloud): blank space
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    if let score = result.score {
                        // Show score
                        Text("\(score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor(for: score))
                        
                        Text("Score")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    } else if result.isFromScoringMode {
                        // Skipped in a scoring mode
                        Text("Skipped")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    // else: Read Aloud mode - show nothing (blank space)
                }
                .frame(minWidth: 80, alignment: .leading) // Ensure consistent spacing
                
                Spacer()
                
                // Favorite button (minimal animation style)
                Button {
                    isFavorited.toggle()
                    onToggleFavorite()
                } label: {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textSecondary)
                            .frame(width: 44, height: 44)
                            .animation(AppTheme.Animation.bouncy, value: isFavorited)
                        
                        Text("Favorite")
                            .font(AppTypography.caption2)
                            .foregroundStyle(isFavorited ? AppColors.accent : AppColors.textSecondary)
                    }
                }
                .accessibilityLabel(isFavorited ? "Remove from favorites" : "Add to favorites")
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .fill(AppColors.backgroundSecondary)
        )
        .onAppear {
            isFavorited = result.isFavorited
        }
    }
    
    // MARK: - Helpers
    
    /// Color for the score based on value
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

#Preview("Session Affirmation Card - Scored") {
    VStack(spacing: AppTheme.Spacing.md) {
        SessionAffirmationCard(
            result: .sample,
            onToggleFavorite: {}
        )
        
        SessionAffirmationCard(
            result: .sampleSkipped,
            onToggleFavorite: {}
        )
        
        SessionAffirmationCard(
            result: .sampleReadAloud,
            onToggleFavorite: {}
        )
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
