//
//  ResonanceMeterView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - ResonanceMeterView

/// Real-time resonance score visualization during speech.
///
/// Features:
/// - Animated arc meter
/// - Color transitions based on score
/// - Numeric score display
/// - Quality level indicator
struct ResonanceMeterView: View {
    
    // MARK: - Properties
    
    /// Current score (0.0 - 1.0)
    let score: Float
    
    /// Whether the meter is actively measuring
    let isActive: Bool
    
    /// Size of the meter
    var size: CGFloat = 200
    
    // MARK: - State
    
    @State private var animatedScore: Float = 0
    @State private var pulseScale: CGFloat = 1.0
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(
                    AppColors.surfaceTertiary,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: size, height: size)
            
            // Progress arc
            Circle()
                .trim(from: 0.15, to: 0.15 + 0.7 * CGFloat(animatedScore))
                .stroke(
                    scoreGradient,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: size, height: size)
                .animation(AppTheme.Animation.standard, value: animatedScore)
            
            // Glow effect when active
            if isActive {
                Circle()
                    .trim(from: 0.15, to: 0.15 + 0.7 * CGFloat(animatedScore))
                    .stroke(
                        scoreColor.opacity(0.5),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: size, height: size)
                    .blur(radius: 8)
                    .scaleEffect(pulseScale)
            }
            
            // Center content
            VStack(spacing: AppTheme.Spacing.xs) {
                // Score number
                Text("\(Int(animatedScore * 100))")
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                
                // Label
                Text("Resonance")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                
                // Quality badge
                if animatedScore > 0 {
                    QualityBadge(quality: ResonanceQuality(score: animatedScore))
                        .padding(.top, AppTheme.Spacing.xs)
                }
            }
        }
        .onChange(of: score) { _, newScore in
            withAnimation(AppTheme.Animation.standard) {
                animatedScore = newScore
            }
        }
        .onAppear {
            if isActive {
                startPulseAnimation()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                startPulseAnimation()
            } else {
                pulseScale = 1.0
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Resonance score: \(Int(score * 100)) percent")
        .accessibilityValue(ResonanceQuality(score: score).rawValue)
    }
    
    // MARK: - Computed Properties
    
    private var scoreColor: Color {
        let quality = ResonanceQuality(score: animatedScore)
        switch quality {
        case .needsWork:
            return AppColors.resonanceNeedsWork
        case .good:
            return AppColors.resonanceGood
        case .excellent:
            return AppColors.resonanceExcellent
        }
    }
    
    private var scoreGradient: AngularGradient {
        AngularGradient(
            colors: [
                AppColors.resonanceNeedsWork,
                AppColors.resonanceGood,
                AppColors.resonanceExcellent
            ],
            center: .center,
            startAngle: .degrees(126),
            endAngle: .degrees(414)
        )
    }
    
    // MARK: - Animation
    
    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.05
        }
    }
}

// MARK: - QualityBadge

/// Badge showing the quality level
struct QualityBadge: View {
    
    let quality: ResonanceQuality
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: quality.iconName)
                .font(.system(size: 10, weight: .semibold))
            
            Text(quality.rawValue)
                .font(AppTypography.caption2.weight(.semibold))
        }
        .foregroundStyle(qualityColor)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 4)
        .background(qualityColor.opacity(0.2))
        .clipShape(Capsule())
    }
    
    private var qualityColor: Color {
        switch quality {
        case .needsWork:
            return AppColors.resonanceNeedsWork
        case .good:
            return AppColors.resonanceGood
        case .excellent:
            return AppColors.resonanceExcellent
        }
    }
}

// MARK: - MiniResonanceMeter

/// Compact inline resonance meter
struct MiniResonanceMeter: View {
    
    let score: Float
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.surfaceTertiary)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient.resonanceGradient)
                        .frame(width: geometry.size.width * CGFloat(score))
                }
            }
            .frame(height: 8)
            
            // Score
            Text("\(Int(score * 100))")
                .font(AppTypography.caption1.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - AudioWaveform

/// Animated waveform visualization for audio input
struct AudioWaveform: View {
    
    /// Audio level (0.0 - 1.0)
    let level: Float
    
    /// Number of bars
    let barCount: Int
    
    /// Whether waveform is active
    let isActive: Bool
    
    @State private var heights: [CGFloat]
    
    init(level: Float, barCount: Int = 5, isActive: Bool = true) {
        self.level = level
        self.barCount = barCount
        self.isActive = isActive
        self._heights = State(initialValue: Array(repeating: 0.2, count: barCount))
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.accentSecondary)
                    .frame(width: 4)
                    .frame(height: 8 + 24 * heights[index])
            }
        }
        .frame(height: 32)
        .onChange(of: level) { _, newLevel in
            if isActive {
                updateHeights(for: newLevel)
            }
        }
        .onAppear {
            if isActive {
                startIdleAnimation()
            }
        }
    }
    
    private func updateHeights(for level: Float) {
        withAnimation(.easeOut(duration: 0.1)) {
            for i in 0..<barCount {
                // Add some variation
                let variation = Float.random(in: 0.8...1.2)
                heights[i] = CGFloat(level * variation)
            }
        }
    }
    
    private func startIdleAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
            guard isActive else {
                timer.invalidate()
                return
            }
            
            if level < 0.05 {
                // Idle state - subtle movement
                withAnimation(.easeInOut(duration: 0.15)) {
                    for i in 0..<barCount {
                        heights[i] = CGFloat.random(in: 0.1...0.3)
                    }
                }
            }
        }
    }
}

// MARK: - ResonanceHistoryChart

/// Chart showing resonance score history for an affirmation
struct ResonanceHistoryChart: View {
    
    let scores: [ResonanceRecord]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Header
            HStack {
                Text("History")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if let best = scores.map(\.overallScore).max() {
                    Text("Best: \(Int(best * 100))")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            
            // Chart
            if scores.isEmpty {
                Text("No history yet")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(scores.suffix(10)) { record in
                        ScoreBar(score: record.overallScore)
                    }
                }
                .frame(height: 60)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
}

// MARK: - ScoreBar

/// Single bar in the history chart
struct ScoreBar: View {
    
    let score: Float
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor)
            .frame(width: 8)
            .frame(height: max(4, 60 * CGFloat(score)))
    }
    
    private var barColor: Color {
        let quality = ResonanceQuality(score: score)
        switch quality {
        case .needsWork:
            return AppColors.resonanceNeedsWork
        case .good:
            return AppColors.resonanceGood
        case .excellent:
            return AppColors.resonanceExcellent
        }
    }
}

// MARK: - Previews

#Preview("Resonance Meter - Active") {
    VStack(spacing: 40) {
        ResonanceMeterView(score: 0.75, isActive: true)
        ResonanceMeterView(score: 0.45, isActive: true, size: 150)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Resonance Meter - Scores") {
    HStack(spacing: 30) {
        ResonanceMeterView(score: 0.35, isActive: false, size: 100)
        ResonanceMeterView(score: 0.65, isActive: false, size: 100)
        ResonanceMeterView(score: 0.90, isActive: false, size: 100)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Mini Resonance Meter") {
    VStack(spacing: 20) {
        MiniResonanceMeter(score: 0.35)
        MiniResonanceMeter(score: 0.65)
        MiniResonanceMeter(score: 0.92)
    }
    .padding()
    .frame(width: 200)
    .background(AppColors.backgroundPrimary)
}

#Preview("Audio Waveform") {
    VStack(spacing: 30) {
        AudioWaveform(level: 0.2, isActive: true)
        AudioWaveform(level: 0.5, isActive: true)
        AudioWaveform(level: 0.8, isActive: true)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Quality Badges") {
    HStack(spacing: 16) {
        QualityBadge(quality: .needsWork)
        QualityBadge(quality: .good)
        QualityBadge(quality: .excellent)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
