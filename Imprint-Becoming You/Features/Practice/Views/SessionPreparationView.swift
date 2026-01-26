//
//  SessionPreparationView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import SwiftUI

// MARK: - Session Preparation View

/// Loading screen shown while pre-synthesizing session affirmations.
///
/// This view displays:
/// - A breathing animation (similar to the preparing-to-listen state)
/// - Progress indicator showing preparation status
/// - Cancel button to abort session start
///
/// ## Usage
/// ```swift
/// if store.isPreparingSession {
///     SessionPreparationView(
///         progress: store.sessionPreparationProgress,
///         preparedCount: store.sessionPreparedCount,
///         totalCount: store.sessionPreparationTarget,
///         onCancel: { store.send(.cancelSessionPreparation) }
///     )
/// }
/// ```
struct SessionPreparationView: View {
    
    // MARK: - Properties
    
    /// Preparation progress (0.0 - 1.0)
    let progress: Float
    
    /// Number of affirmations prepared
    let preparedCount: Int
    
    /// Total number to prepare before starting
    let totalCount: Int
    
    /// Called when user taps cancel
    let onCancel: () -> Void
    
    // MARK: - State
    
    /// Animation phase for breathing effect
    @State private var breathingPhase: CGFloat = 0
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xl) {
                Spacer()
                
                // Breathing animation
                breathingIndicator
                
                // Status text
                VStack(spacing: AppTheme.Spacing.sm) {
                    Text("Preparing Session")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(preparedCount) of \(totalCount)")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }
                
                // Progress bar
                progressBar
                    .padding(.horizontal, AppTheme.Spacing.xxl)
                
                Spacer()
                
                // Cancel button
                cancelButton
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            startBreathingAnimation()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing session, \(preparedCount) of \(totalCount) affirmations ready")
    }
    
    // MARK: - Subviews
    
    private var breathingIndicator: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(AppColors.accent.opacity(0.15))
                .frame(width: 120 + breathingPhase * 20, height: 120 + breathingPhase * 20)
            
            // Middle ring
            Circle()
                .fill(AppColors.accent.opacity(0.25))
                .frame(width: 80 + breathingPhase * 15, height: 80 + breathingPhase * 15)
            
            // Inner circle
            Circle()
                .fill(AppColors.accent.opacity(0.4))
                .frame(width: 50 + breathingPhase * 10, height: 50 + breathingPhase * 10)
            
            // Center dot
            Circle()
                .fill(AppColors.accent)
                .frame(width: 16, height: 16)
        }
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: breathingPhase)
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(AppColors.surfaceTertiary)
                    .frame(height: 6)
                
                // Progress fill
                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
    }
    
    private var cancelButton: some View {
        Button {
            HapticFeedback.impact(.light)
            onCancel()
        } label: {
            Text("Cancel")
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppColors.surfaceTertiary.opacity(0.8))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Cancel session preparation")
    }
    
    // MARK: - Animation
    
    private func startBreathingAnimation() {
        breathingPhase = 1
    }
}

// MARK: - Previews

#Preview("Preparing - 0/5") {
    SessionPreparationView(
        progress: 0,
        preparedCount: 0,
        totalCount: 5,
        onCancel: {}
    )
}

#Preview("Preparing - 2/5") {
    SessionPreparationView(
        progress: 0.4,
        preparedCount: 2,
        totalCount: 5,
        onCancel: {}
    )
}

#Preview("Preparing - 4/5") {
    SessionPreparationView(
        progress: 0.8,
        preparedCount: 4,
        totalCount: 5,
        onCancel: {}
    )
}
