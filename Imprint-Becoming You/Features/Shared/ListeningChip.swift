//
//  ListeningChip.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI

// MARK: - ListeningChip

/// A non-interactive indicator chip showing when the app is listening.
///
/// Displayed centered at the top of the screen during listening phases.
/// This is an **indicator only**, not a tappable button.
///
/// ## Usage
/// ```swift
/// ListeningChip(isVisible: isListening)
/// ```
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
                    .font(AppTypography.caption1.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.surfaceTertiary.opacity(0.9))
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .onAppear {
                startPulseAnimation()
            }
            .onDisappear {
                isPulsing = false
            }
            .allowsHitTesting(false) // Not tappable - indicator only
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
                .font(AppTypography.caption1.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
            
            Text("•")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
            
            Text(qualityLabel)
                .font(AppTypography.caption1.weight(.semibold))
                .foregroundStyle(qualityColor)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppColors.surfaceTertiary.opacity(0.9))
        .clipShape(Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .allowsHitTesting(false) // Not tappable - indicator only
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
                .font(AppTypography.caption1.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
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
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            ListeningChip(isVisible: true)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("Resonance Chip - Excellent") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            ResonanceChip(score: 0.85)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("Resonance Chip - Good") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            ResonanceChip(score: 0.72)
            Spacer()
        }
        .padding(.top, 60)
    }
}

#Preview("Resonance Chip - Needs Work") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
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

#Preview("Chips - In Context") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            // Top bar simulation
            HStack {
                // Exit button
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Exit")
                        .font(AppTypography.caption1.weight(.medium))
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppColors.surfaceTertiary.opacity(0.8))
                .clipShape(Capsule())
                
                Spacer()
                
                // Centered resonance chip
                ResonanceChip(score: 0.78)
                
                Spacer()
                
                // Invisible spacer for centering
                Color.clear
                    .frame(width: 70)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.md)
            
            Spacer()
            
            // Affirmation text placeholder
            Text("I am confident and capable of achieving my goals.")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xl)
            
            Spacer()
            
            // Dock placeholder
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
                .fill(AppColors.backgroundSecondary)
                .frame(height: 120)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}
