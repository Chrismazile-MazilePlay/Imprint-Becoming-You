//
//  ListeningChip.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI

// MARK: - Chip Constants

/// Shared dimensions for HUD chips to ensure perfect symmetry
private enum ChipConstants {
    /// Standard height for all HUD chips (matches Exit button)
    static let height: CGFloat = 36
    
    /// Font for chip text (matches Exit button text)
    static let font = AppTypography.caption1.weight(.medium)
}

// MARK: - ListeningChip

/// A non-interactive indicator chip showing when the app is listening.
///
/// Displayed centered at the top of the screen during listening phases.
/// This is an **indicator only**, not a tappable button.
///
/// Height matches the Exit button (36pt) for visual symmetry.
struct ListeningChip: View {
    
    // MARK: - Properties
    
    /// Whether the chip is visible
    let isVisible: Bool
    
    // MARK: - State
    
    @State private var isPulsing: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        if isVisible {
            HStack(spacing: AppTheme.Spacing.xs) {
                // Pulsing dot indicator
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .opacity(isPulsing ? 1.0 : 0.6)
                
                Text("Listening")
                    .font(ChipConstants.font)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: ChipConstants.height)
            .background(AppColors.surfaceTertiary.opacity(0.9))
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .onAppear {
                startPulseAnimation()
            }
            .onDisappear {
                isPulsing = false
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Listening indicator")
            .accessibilityAddTraits(.isStaticText)
        }
    }
    
    // MARK: - Animation
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

// MARK: - ResonanceChip

/// A non-interactive indicator chip showing the resonance score result.
///
/// Displayed centered at the top of the screen when score is shown.
/// Shows "Resonance • Good" (or Excellent/Needs Work based on score).
///
/// Height matches the Exit button (36pt) for visual symmetry.
struct ResonanceChip: View {
    
    // MARK: - Properties
    
    /// The score value (0.0 - 1.0)
    let score: Double
    
    // MARK: - Computed
    
    private var qualityLabel: String {
        switch score {
        case 0.8...:
            return "Excellent"
        case 0.6..<0.8:
            return "Good"
        default:
            return "Keep Practicing"
        }
    }
    
    private var qualityColor: Color {
        switch score {
        case 0.8...:
            return AppColors.success
        case 0.6..<0.8:
            return AppColors.accent
        default:
            return AppColors.warning
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text("Resonance")
                .font(ChipConstants.font)
                .foregroundStyle(AppColors.textSecondary)
            
            Text("•")
                .font(ChipConstants.font)
                .foregroundStyle(AppColors.textTertiary)
            
            Text(qualityLabel)
                .font(AppTypography.caption1.weight(.semibold))
                .foregroundStyle(qualityColor)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: ChipConstants.height)
        .background(AppColors.surfaceTertiary.opacity(0.9))
        .clipShape(Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .allowsHitTesting(false)
        .accessibilityLabel("Resonance score: \(qualityLabel)")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - StatusChip (Generic)

/// Generic status chip for various states (can be reused for other indicators).
struct StatusChip: View {
    
    let text: String
    let icon: String?
    let color: Color
    let isAnimated: Bool
    
    @State private var isPulsing: Bool = false
    
    init(
        text: String,
        icon: String? = nil,
        color: Color = AppColors.textSecondary,
        isAnimated: Bool = false
    ) {
        self.text = text
        self.icon = icon
        self.color = color
        self.isAnimated = isAnimated
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .scaleEffect(isAnimated && isPulsing ? 1.2 : 1.0)
            }
            
            Text(text)
                .font(ChipConstants.font)
                .foregroundStyle(color)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(height: ChipConstants.height)
        .background(AppColors.surfaceTertiary.opacity(0.9))
        .clipShape(Capsule())
        .onAppear {
            if isAnimated {
                startPulseAnimation()
            }
        }
        .allowsHitTesting(false)
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

// MARK: - Previews

#Preview("Listening Chip") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        VStack {
            ListeningChip(isVisible: true)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("Resonance Chip - Excellent") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        VStack {
            ResonanceChip(score: 0.85)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("Resonance Chip - Good") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        VStack {
            ResonanceChip(score: 0.72)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("Resonance Chip - Needs Work") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        VStack {
            ResonanceChip(score: 0.45)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("All Chips") {
    VStack(spacing: 20) {
        ListeningChip(isVisible: true)
        ResonanceChip(score: 0.92)
        ResonanceChip(score: 0.75)
        ResonanceChip(score: 0.50)
        StatusChip(text: "Analyzing", icon: "waveform", color: AppColors.accent, isAnimated: true)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Chips - Height Comparison") {
    VStack(spacing: 20) {
        // Exit button reference
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
            Text("Exit")
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(AppColors.textSecondary)
        .frame(width: 78, height: 36)
        .background(AppColors.surfaceTertiary.opacity(0.8))
        .clipShape(Capsule())
        
        // Listening chip
        ListeningChip(isVisible: true)
        
        // Resonance chip
        ResonanceChip(score: 0.85)
        
        // Loop chip reference
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "repeat")
                .font(.system(size: 14, weight: .semibold))
            Text("1 of 3")
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(AppColors.textSecondary)
        .frame(width: 78, height: 36)
        .background(AppColors.surfaceTertiary.opacity(0.8))
        .clipShape(Capsule())
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
