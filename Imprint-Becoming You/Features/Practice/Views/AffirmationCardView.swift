//
//  AffirmationCardView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - AffirmationCardView

/// Full-screen affirmation display for standalone use.
///
/// Note: In the main practice flow, `PracticePageView` renders content
/// directly within `VerticalPager` for proper dual-content transitions.
/// This view is retained for backwards compatibility and simpler use
/// cases (detail sheets, previews, etc.).
struct AffirmationCardView: View {
    
    // MARK: - Properties
    
    let affirmation: Affirmation
    let phase: AffirmationPhase
    let realtimeScore: Float
    let resonanceRecord: ResonanceRecord?
    let isSpeaking: Bool
    let isListening: Bool
    let recognizedText: String
    
    var onFavoriteTap: (() -> Void)?
    var onShareTap: (() -> Void)?
    
    // MARK: - State
    
    @State private var textOpacity: Double = 0
    @State private var textScale: CGFloat = 0.95
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AffirmationBackgroundView(category: affirmation.goalCategory)
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    if let category = affirmation.goalCategory {
                        CategoryBadge(category: category)
                            .padding(.bottom, AppTheme.Spacing.lg)
                    }
                    
                    Text(affirmation.text)
                        .font(AppTypography.affirmation)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .opacity(textOpacity)
                        .scaleEffect(textScale)
                    
                    Spacer()
                    
                    if phase == .listening && !recognizedText.isEmpty {
                        RecognizedTextView(text: recognizedText)
                            .padding(.bottom, AppTheme.Spacing.xxl)
                    }
                    
                    if onFavoriteTap != nil || onShareTap != nil {
                        actionButtons
                            .padding(.bottom, AppTheme.Spacing.xxl)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxl)
            }
        }
        .onAppear { animateIn() }
        .onChange(of: affirmation.id) { _, _ in animateTransition() }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            if let favoriteTap = onFavoriteTap {
                Button {
                    favoriteTap()
                } label: {
                    Image(systemName: affirmation.isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(affirmation.isFavorited ? AppColors.accent : AppColors.textSecondary)
                        .frame(width: Constants.Layout.minimumTouchTarget, height: Constants.Layout.minimumTouchTarget)
                }
                .accessibilityLabel(affirmation.isFavorited ? "Remove from favorites" : "Add to favorites")
            }
            
            if let shareTap = onShareTap {
                Button {
                    shareTap()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: Constants.Layout.minimumTouchTarget, height: Constants.Layout.minimumTouchTarget)
                }
                .accessibilityLabel("Share affirmation")
            }
        }
    }
    
    // MARK: - Animations
    
    private func animateIn() {
        withAnimation(AppTheme.Animation.slow) {
            textOpacity = 1
            textScale = 1
        }
    }
    
    private func animateTransition() {
        textOpacity = 0
        textScale = 0.95
        
        withAnimation(AppTheme.Animation.standard.delay(0.1)) {
            textOpacity = 1
            textScale = 1
        }
    }
}

// MARK: - CategoryBadge

struct CategoryBadge: View {
    
    let category: GoalCategory
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: category.iconName)
                .font(.system(size: 12, weight: .semibold))
            
            Text(category.rawValue)
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Category: \(category.rawValue)")
    }
    
    private var badgeColor: Color {
        CategoryGradient.forGroup(category.group).primary
    }
}

// MARK: - RecognizedTextView

struct RecognizedTextView: View {
    
    let text: String
    
    var body: some View {
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppColors.backgroundSecondary.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .padding(.horizontal, AppTheme.Spacing.lg)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - Previews

#Preview("Affirmation Card") {
    AffirmationCardView(
        affirmation: .sample,
        phase: .displaying,
        realtimeScore: 0,
        resonanceRecord: nil,
        isSpeaking: false,
        isListening: false,
        recognizedText: ""
    )
}

#Preview("Card with Actions") {
    AffirmationCardView(
        affirmation: .sample,
        phase: .displaying,
        realtimeScore: 0,
        resonanceRecord: nil,
        isSpeaking: false,
        isListening: false,
        recognizedText: "",
        onFavoriteTap: {},
        onShareTap: {}
    )
}
