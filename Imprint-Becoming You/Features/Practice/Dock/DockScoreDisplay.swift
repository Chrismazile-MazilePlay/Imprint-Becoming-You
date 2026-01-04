//
//  DockScoreDisplay.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI

// MARK: - DockScoreDisplay

/// Displays the resonance score with a count-up animation.
///
/// The score counts from 0 to the final value over ~1 second,
/// creating an engaging reveal effect.
///
/// ## Usage
/// ```swift
/// DockScoreDisplay(score: 78)
/// ```
struct DockScoreDisplay: View {
    
    // MARK: - Properties
    
    /// Final score value (0-100)
    let score: Int
    
    /// Duration of count-up animation
    var animationDuration: Double = 1.0
    
    // MARK: - State
    
    @State private var displayedScore: Int = 0
    @State private var hasAnimated: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        Text("\(displayedScore)")
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .foregroundStyle(scoreColor)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
            .onAppear {
                if !hasAnimated {
                    animateScore()
                }
            }
            .onChange(of: score) { _, newScore in
                // Re-animate if score changes
                displayedScore = 0
                animateScore()
            }
            .accessibilityLabel("Resonance score: \(score)")
    }
    
    // MARK: - Computed Properties
    
    /// Color based on score value
    private var scoreColor: Color {
        switch score {
        case 80...:
            return AppColors.success
        case 60..<80:
            return AppColors.accent
        default:
            return AppColors.warning
        }
    }
    
    // MARK: - Animation
    
    private func animateScore() {
        hasAnimated = true
        
        // Calculate steps for smooth animation
        let steps = min(score, 60) // Max 60 steps for performance
        let stepDuration = animationDuration / Double(steps)
        let increment = max(1, score / steps)
        
        // Animate count-up
        for i in 0...steps {
            let delay = stepDuration * Double(i)
            let targetValue = min(i * increment, score)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedScore = targetValue
                }
            }
        }
        
        // Ensure final value is exact
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            withAnimation(.easeOut(duration: 0.1)) {
                displayedScore = score
            }
        }
    }
}

// MARK: - DockScoreDisplayCompact

/// A more compact version of the score display for tight spaces.
struct DockScoreDisplayCompact: View {
    
    let score: Int
    
    @State private var displayedScore: Int = 0
    @State private var hasAnimated: Bool = false
    
    var body: some View {
        Text("\(displayedScore)")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(scoreColor)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
            .onAppear {
                if !hasAnimated {
                    animateScore()
                }
            }
    }
    
    private var scoreColor: Color {
        switch score {
        case 80...:
            return AppColors.success
        case 60..<80:
            return AppColors.accent
        default:
            return AppColors.warning
        }
    }
    
    private func animateScore() {
        hasAnimated = true
        let steps = min(score, 50)
        let stepDuration = 0.8 / Double(steps)
        let increment = max(1, score / steps)
        
        for i in 0...steps {
            let delay = stepDuration * Double(i)
            let targetValue = min(i * increment, score)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedScore = targetValue
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.1)) {
                displayedScore = score
            }
        }
    }
}

// MARK: - Previews

#Preview("Score Display - Count Up") {
    ZStack {
        AppColors.backgroundSecondary
        DockScoreDisplay(score: 78)
    }
    .frame(height: 80)
    .padding()
}

#Preview("Score Display - Various Scores") {
    VStack(spacing: 30) {
        DockScoreDisplay(score: 95)
        DockScoreDisplay(score: 72)
        DockScoreDisplay(score: 45)
    }
    .padding()
    .background(AppColors.backgroundSecondary)
}

#Preview("Score Display - Compact") {
    ZStack {
        AppColors.backgroundSecondary
        DockScoreDisplayCompact(score: 85)
    }
    .frame(height: 60)
    .padding()
}

#Preview("Score - In Dock Context") {
    VStack {
        Spacer()
        
        VStack(spacing: AppTheme.Spacing.md) {
            // Progress bars
            DockProgressBars(current: 2, total: 5, progress: 1.0)
            
            // Score between chevrons
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                
                Spacer()
                
                DockScoreDisplay(score: 78)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            
            // Mode buttons
            HStack {
                Text("Read & Speak")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppColors.accent.opacity(0.15))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text("Sleep")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.accentSecondary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppColors.accentSecondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge))
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}
