//
//  Colors.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - App Colors

/// Centralized color definitions for the Imprint design system.
///
/// The color palette is designed for a dark-mode-primary, minimalist aesthetic
/// that evokes calm, focus, and personal transformation.
///
/// ## Color Philosophy
/// - **Primary Accent (Amber/Gold)**: Represents transformation, wisdom, and achievement
/// - **Secondary Accent (Sage)**: Represents calm, growth, and natural balance
/// - **Backgrounds**: Deep blacks and charcoals for immersive, focused experience
/// - **Text**: High-contrast whites and muted grays for readability
enum AppColors {
    
    // MARK: - Brand Colors
    
    /// Primary accent color - Warm Amber/Gold
    /// Hex: #D4A574
    static let accent = Color("accent")
    
    /// Secondary accent color - Soft Sage
    /// Hex: #8BA888
    static let accentSecondary = Color("accentSecondary")
    
    /// Tertiary accent for subtle highlights
    /// Hex: #6B7280
    static let accentTertiary = Color("accentTertiary")
    
    // MARK: - Background Colors
    
    /// Primary background - True Black
    /// Hex: #000000
    static let backgroundPrimary = Color("backgroundPrimary")
    
    /// Secondary background - Charcoal
    /// Hex: #1C1C1E
    static let backgroundSecondary = Color("backgroundSecondary")
    
    /// Tertiary background - Dark Gray
    /// Hex: #2C2C2E
    static let backgroundTertiary = Color("backgroundTertiary")
    
    /// Elevated surface background
    /// Hex: #3A3A3C
    static let backgroundElevated = Color("backgroundElevated")
    
    // MARK: - Text Colors
    
    /// Primary text - Off White
    /// Hex: #F5F5F7
    static let textPrimary = Color("textPrimary")
    
    /// Secondary text - Light Gray
    /// Hex: #A1A1A6
    static let textSecondary = Color("textSecondary")
    
    /// Tertiary/muted text - Medium Gray
    /// Hex: #6E6E73
    static let textTertiary = Color("textTertiary")
    
    /// Inverted text for light backgrounds
    /// Hex: #1C1C1E
    static let textInverted = Color("textInverted")
    
    // MARK: - Semantic Colors
    
    /// Success state
    /// Hex: #34C759
    static let success = Color("success")
    
    /// Warning state
    /// Hex: #FF9500
    static let warning = Color("warning")
    
    /// Error state
    /// Hex: #FF3B30
    static let error = Color("error")
    
    /// Info state
    /// Hex: #5AC8FA
    static let info = Color("info")
    
    // MARK: - Resonance Score Colors
    
    /// Needs work - Below threshold
    /// Hex: #FF6B6B
    static let resonanceNeedsWork = Color("resonanceNeedsWork")
    
    /// Good - Meets threshold
    /// Hex: #FFE66D
    static let resonanceGood = Color("resonanceGood")
    
    /// Excellent - Exceeds threshold
    /// Hex: #4ECDC4
    static let resonanceExcellent = Color("resonanceExcellent")
    
    // MARK: - UI Element Colors
    
    /// Surface color for secondary UI elements (cards, sheets)
    /// Hex: #2C2C2E (same as backgroundTertiary)
    static let surfaceSecondary = Color("backgroundTertiary")
    
    /// Surface color for tertiary UI elements
    /// Hex: #48484A
    static let surfaceTertiary = Color("surfaceTertiary")
    
    /// Separator/divider lines
    /// Hex: #38383A
    static let separator = Color("separator")
    
    /// Card borders
    /// Hex: #48484A
    static let border = Color("border")
    
    /// Overlay background (for modals)
    static let overlay = Color.black.opacity(0.6)
    
    /// Disabled state
    static let disabled = Color("textTertiary").opacity(0.5)
}

// MARK: - Color Extensions

extension Color {
    
    // MARK: - Convenience Accessors
    
    /// Primary accent color
    static var appAccent: Color { AppColors.accent }
    
    /// Secondary accent color
    static var appAccentSecondary: Color { AppColors.accentSecondary }
    
    /// Primary background
    static var appBackground: Color { AppColors.backgroundPrimary }
    
    /// Primary text color
    static var appText: Color { AppColors.textPrimary }
    
    /// Secondary text color
    static var appTextSecondary: Color { AppColors.textSecondary }
}

// MARK: - Gradient Definitions

extension LinearGradient {
    
    /// Primary accent gradient (vertical)
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.accent,
                AppColors.accent.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Background gradient for main screens
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.backgroundSecondary,
                AppColors.backgroundPrimary
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Subtle card gradient
    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.backgroundTertiary,
                AppColors.backgroundSecondary
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Resonance meter gradient
    static var resonanceGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.resonanceNeedsWork,
                AppColors.resonanceGood,
                AppColors.resonanceExcellent
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Radial Gradients

extension RadialGradient {
    
    /// Glow effect for accent elements
    static var accentGlow: RadialGradient {
        RadialGradient(
            colors: [
                AppColors.accent.opacity(0.3),
                AppColors.accent.opacity(0)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 100
        )
    }
    
    /// Subtle ambient glow for backgrounds
    static var ambientGlow: RadialGradient {
        RadialGradient(
            colors: [
                AppColors.accentSecondary.opacity(0.1),
                Color.clear
            ],
            center: .center,
            startRadius: 50,
            endRadius: 300
        )
    }
}

// MARK: - Preview Provider

#Preview("App Colors") {
    ScrollView {
        VStack(spacing: 24) {
            // Brand Colors
            colorSection(title: "Brand Colors") {
                colorSwatch("Accent", color: AppColors.accent)
                colorSwatch("Accent Secondary", color: AppColors.accentSecondary)
                colorSwatch("Accent Tertiary", color: AppColors.accentTertiary)
            }
            
            // Backgrounds
            colorSection(title: "Backgrounds") {
                colorSwatch("Primary", color: AppColors.backgroundPrimary)
                colorSwatch("Secondary", color: AppColors.backgroundSecondary)
                colorSwatch("Tertiary", color: AppColors.backgroundTertiary)
                colorSwatch("Elevated", color: AppColors.backgroundElevated)
            }
            
            // Surfaces
            colorSection(title: "Surfaces") {
                colorSwatch("Surface Secondary", color: AppColors.surfaceSecondary)
                colorSwatch("Surface Tertiary", color: AppColors.surfaceTertiary)
            }
            
            // Text
            colorSection(title: "Text Colors") {
                colorSwatch("Primary", color: AppColors.textPrimary)
                colorSwatch("Secondary", color: AppColors.textSecondary)
                colorSwatch("Tertiary", color: AppColors.textTertiary)
            }
            
            // Semantic
            colorSection(title: "Semantic Colors") {
                colorSwatch("Success", color: AppColors.success)
                colorSwatch("Warning", color: AppColors.warning)
                colorSwatch("Error", color: AppColors.error)
                colorSwatch("Info", color: AppColors.info)
            }
            
            // Resonance
            colorSection(title: "Resonance Colors") {
                colorSwatch("Needs Work", color: AppColors.resonanceNeedsWork)
                colorSwatch("Good", color: AppColors.resonanceGood)
                colorSwatch("Excellent", color: AppColors.resonanceExcellent)
            }
        }
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}

// MARK: - Preview Helpers

@ViewBuilder
private func colorSection(
    title: String,
    @ViewBuilder content: () -> some View
) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.headline)
            .foregroundStyle(AppColors.textPrimary)
        
        content()
    }
}

@ViewBuilder
private func colorSwatch(_ name: String, color: Color) -> some View {
    HStack(spacing: 16) {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        
        Text(name)
            .font(.subheadline)
            .foregroundStyle(AppColors.textSecondary)
        
        Spacer()
    }
}
