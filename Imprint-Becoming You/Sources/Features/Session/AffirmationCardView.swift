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
/// - Resonance score overlay when applicable
struct AffirmationCardView: View {
    
    // MARK: - Properties
    
    /// The affirmation to display
    let affirmation: Affirmation
    
    /// Current phase of the affirmation
    let phase: AffirmationPhase
    
    /// Real-time score during listening
    let realtimeScore: Float
    
    /// Last resonance record (for showing score)
    let resonanceRecord: ResonanceRecord?
    
    /// Whether TTS is speaking
    let isSpeaking: Bool
    
    /// Whether listening to user
    let isListening: Bool
    
    /// Recognized text during listening
    let recognizedText: String
    
    // MARK: - State
    
    @State private var textOpacity: Double = 0
    @State private var textScale: CGFloat = 0.95
    @State private var showScoreCard: Bool = false
    
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
                    
                    // Phase indicator
                    phaseIndicator
                        .padding(.top, AppTheme.Spacing.xl)
                    
                    Spacer()
                    
                    // Recognized text (during listening)
                    if phase == .listening && !recognizedText.isEmpty {
                        RecognizedTextView(text: recognizedText)
                            .padding(.bottom, AppTheme.Spacing.xl)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxl)
                
                // Score overlay
                if phase == .showingScore, let record = resonanceRecord {
                    ScoreOverlay(record: record, isVisible: $showScoreCard)
                }
            }
        }
        .onAppear {
            animateIn()
        }
        .onChange(of: affirmation.id) { _, _ in
            animateTransition()
        }
        .onChange(of: phase) { oldPhase, newPhase in
            if newPhase == .showingScore {
                withAnimation(AppTheme.Animation.standard.delay(0.3)) {
                    showScoreCard = true
                }
            } else {
                showScoreCard = false
            }
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
    
    @ViewBuilder
    private var phaseIndicator: some View {
        switch phase {
        case .displaying:
            EmptyView()
            
        case .speaking:
            SpeakingIndicator()
            
        case .listening:
            ListeningIndicator(audioLevel: realtimeScore)
            
        case .showingScore:
            EmptyView()
        }
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
        showScoreCard = false
        
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

// MARK: - SpeakingIndicator

/// Animated indicator shown when TTS is speaking
struct SpeakingIndicator: View {
    
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: 4, height: animating ? 20 : 8)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: 24)
        .onAppear {
            animating = true
        }
        .accessibilityLabel("Speaking")
    }
}

// MARK: - ListeningIndicator

/// Animated indicator shown when listening to user speech
struct ListeningIndicator: View {
    
    let audioLevel: Float
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Outer pulse
            Circle()
                .stroke(AppColors.accentSecondary.opacity(0.3), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(pulseScale)
            
            // Audio level ring
            Circle()
                .fill(AppColors.accentSecondary.opacity(0.2))
                .frame(width: 44, height: 44)
                .scaleEffect(1.0 + CGFloat(audioLevel) * 0.3)
            
            // Mic icon
            Circle()
                .fill(AppColors.accentSecondary)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.backgroundPrimary)
                )
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.2
            }
        }
        .accessibilityLabel("Listening, speak now")
    }
}

// MARK: - RecognizedTextView

/// Shows the recognized text during speech
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

// MARK: - ScoreOverlay

/// Overlay showing the resonance score after speaking
struct ScoreOverlay: View {
    
    let record: ResonanceRecord
    @Binding var isVisible: Bool
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(isVisible ? 0.6 : 0)
                .ignoresSafeArea()
            
            // Score card
            if isVisible {
                ScoreCard(record: record)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(AppTheme.Animation.standard, value: isVisible)
    }
}

// MARK: - ScoreCard

/// Card displaying the resonance score breakdown
struct ScoreCard: View {
    
    let record: ResonanceRecord
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Quality indicator
            Text(record.qualityLevel.rawValue)
                .font(AppTypography.caption1.weight(.semibold))
                .foregroundStyle(qualityColor)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(qualityColor.opacity(0.2))
                .clipShape(Capsule())
            
            // Overall score
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("\(Int(record.overallScore * 100))")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Resonance Score")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            // Component breakdown
            VStack(spacing: AppTheme.Spacing.sm) {
                ScoreComponentRow(
                    label: "Vocal Energy",
                    value: record.vocalEnergy,
                    weight: "60%"
                )
                
                ScoreComponentRow(
                    label: "Pitch Stability",
                    value: record.pitchStability,
                    weight: "30%"
                )
                
                ScoreComponentRow(
                    label: "Text Accuracy",
                    value: record.textAccuracy,
                    weight: "10%"
                )
            }
            .padding(.top, AppTheme.Spacing.sm)
        }
        .padding(AppTheme.Spacing.xl)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, AppTheme.Spacing.xl)
    }
    
    private var qualityColor: Color {
        switch record.qualityLevel {
        case .needsWork:
            return AppColors.resonanceNeedsWork
        case .good:
            return AppColors.resonanceGood
        case .excellent:
            return AppColors.resonanceExcellent
        }
    }
}

// MARK: - ScoreComponentRow

/// Row showing a single score component
struct ScoreComponentRow: View {
    
    let label: String
    let value: Float
    let weight: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
            
            Text("\(Int(value * 100))%")
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Text("(\(weight))")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
        }
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

#Preview("Affirmation Card - Speaking") {
    AffirmationCardView(
        affirmation: .sample,
        phase: .speaking,
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

#Preview("Affirmation Card - Score") {
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

#Preview("Score Card") {
    let record = ResonanceRecord(
        overallScore: 0.75,
        textAccuracy: 0.90,
        vocalEnergy: 0.70,
        pitchStability: 0.65,
        duration: 4.0,
        sessionMode: .speakOnly
    )
    
    return ScoreCard(record: record)
        .padding()
        .background(AppColors.backgroundPrimary)
}
