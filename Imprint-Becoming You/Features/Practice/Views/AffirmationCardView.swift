//
//  AffirmationCardView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - AffirmationCardView

/// Full-screen TikTok-style affirmation card.
///
/// Features:
/// - Centered affirmation text with elegant typography
/// - Category badge
/// - Subtle background gradient
/// - Animated transitions between cards
///
/// Note: All phase indicators (waveform, mic, score) are now in the dock/HUD layer.
struct AffirmationCardView: View {
    
    // MARK: - Properties
    
    /// The affirmation to display
    let affirmation: Affirmation
    
    /// Current phase of the affirmation
    let phase: AffirmationPhase
    
    /// Real-time score during listening (unused here, kept for API compatibility)
    let realtimeScore: Float
    
    /// Last resonance record (unused here, kept for API compatibility)
    let resonanceRecord: ResonanceRecord?
    
    /// Whether TTS is speaking (unused here, kept for API compatibility)
    let isSpeaking: Bool
    
    /// Whether listening to user (unused here, kept for API compatibility)
    let isListening: Bool
    
    /// Recognized text during listening
    let recognizedText: String
    
    // MARK: - State
    
    @State private var textOpacity: Double = 0
    @State private var textScale: CGFloat = 0.95
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                backgroundView
                
                // Main content
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Category badge
                    if let category = affirmation.goalCategory {
                        CategoryBadge(category: category)
                            .padding(.bottom, AppTheme.Spacing.lg)
                    }
                    
                    // Affirmation text
                    Text(affirmation.text)
                        .font(AppTypography.affirmation)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .opacity(textOpacity)
                        .scaleEffect(textScale)
                    
                    Spacer()
                    
                    // Recognized text (during listening) - optional feedback
                    if phase == .listening && !recognizedText.isEmpty {
                        RecognizedTextView(text: recognizedText)
                            .padding(.bottom, AppTheme.Spacing.xxl)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxl)
            }
        }
        .onAppear {
            animateIn()
        }
        .onChange(of: affirmation.id) { _, _ in
            animateTransition()
        }
    }
    
    // MARK: - Subviews
    
    private var backgroundView: some View {
        ZStack {
            // Base gradient
            LinearGradient.backgroundGradient
            
            // Subtle ambient glow based on category
            if let category = affirmation.goalCategory {
                RadialGradient(
                    colors: [
                        categoryColor(for: category).opacity(0.15),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Helpers
    
    private func categoryColor(for category: GoalCategory) -> Color {
        switch category.group {
        case .coreIdentity:
            return AppColors.accent
        case .performanceAndImpact:
            return Color.orange
        case .wellBeing:
            return AppColors.accentSecondary
        case .faithBased:
            return Color.purple
        case .connection:
            return Color.pink
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
        // Reset
        textOpacity = 0
        textScale = 0.95
        
        // Animate in
        withAnimation(AppTheme.Animation.standard.delay(0.1)) {
            textOpacity = 1
            textScale = 1
        }
    }
}

// MARK: - CategoryBadge

/// Badge showing the affirmation category
struct CategoryBadge: View {
    
    let category: GoalCategory
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: category.iconName)
                .font(.system(size: 12, weight: .semibold))
            
            Text(category.rawValue)
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(AppColors.accent)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.accent.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Category: \(category.rawValue)")
    }
}

// MARK: - RecognizedTextView

/// Shows the recognized text during speech (optional visual feedback)
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

#Preview("Affirmation Card - Displaying") {
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

#Preview("Affirmation Card - Playing") {
    AffirmationCardView(
        affirmation: .sample,
        phase: .playing,
        realtimeScore: 0,
        resonanceRecord: nil,
        isSpeaking: true,
        isListening: false,
        recognizedText: ""
    )
}

#Preview("Affirmation Card - Listening") {
    AffirmationCardView(
        affirmation: .sample,
        phase: .listening,
        realtimeScore: 0.7,
        resonanceRecord: nil,
        isSpeaking: false,
        isListening: true,
        recognizedText: "I am confident and"
    )
}

#Preview("Affirmation Card - Score Phase") {
    let record = ResonanceRecord(
        overallScore: 0.85,
        textAccuracy: 0.95,
        vocalEnergy: 0.82,
        pitchStability: 0.78,
        duration: 3.5,
        sessionMode: .readThenSpeak
    )
    
    return AffirmationCardView(
        affirmation: .sample,
        phase: .showingScore,
        realtimeScore: 0,
        resonanceRecord: record,
        isSpeaking: false,
        isListening: false,
        recognizedText: ""
    )
}
