//
//  DefaultDockDesignTokens.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DefaultDockDesignTokens

/// Default design token implementation matching the Imprint design system.
///
/// This provides sensible defaults when no custom design tokens are injected.
/// The values are derived from the Imprint app's `AppColors`, `AppTheme`,
/// and `AppTypography` definitions.
///
/// ## Color Philosophy
///
/// - **Primary Accent (Amber/Gold)**: Transformation, wisdom, achievement
/// - **Secondary Accent (Sage)**: Calm, growth, natural balance
/// - **Backgrounds**: Deep blacks and charcoals for immersive experience
/// - **Text**: High-contrast whites and muted grays for readability
///
/// ## Usage
///
/// The default tokens are automatically used if no custom tokens are injected:
///
/// ```swift
/// // These are equivalent:
/// AdaptiveBottomDock(adapter: adapter)
///
/// AdaptiveBottomDock(adapter: adapter)
///     .environment(\.dockDesignTokens, DefaultDockDesignTokens())
/// ```
///
/// ## Customization
///
/// To use custom colors, create your own conforming type:
///
/// ```swift
/// struct MyAppDockDesignTokens: DockDesignTokens {
///     var backgroundPrimary: Color { MyColors.background }
///     var accent: Color { MyColors.primary }
///     // ... etc
/// }
///
/// AdaptiveBottomDock(adapter: adapter)
///     .environment(\.dockDesignTokens, MyAppDockDesignTokens())
/// ```
public struct DefaultDockDesignTokens: DockDesignTokens {
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Colors
    
    /// Primary background - True Black
    /// Hex: #000000
    public var backgroundPrimary: Color {
        Color(red: 0, green: 0, blue: 0)
    }
    
    /// Secondary background - Charcoal
    /// Hex: #1C1C1E
    public var backgroundSecondary: Color {
        Color(red: 0.11, green: 0.11, blue: 0.118)
    }
    
    /// Tertiary background - Dark Gray
    /// Hex: #2C2C2E
    public var backgroundTertiary: Color {
        Color(red: 0.173, green: 0.173, blue: 0.18)
    }
    
    /// Surface tertiary - Medium Dark Gray
    /// Hex: #48484A
    public var surfaceTertiary: Color {
        Color(red: 0.282, green: 0.282, blue: 0.29)
    }
    
    /// Primary text - Off White
    /// Hex: #F5F5F7
    public var textPrimary: Color {
        Color(red: 0.96, green: 0.96, blue: 0.97)
    }
    
    /// Secondary text - Light Gray
    /// Hex: #A1A1A6
    public var textSecondary: Color {
        Color(red: 0.631, green: 0.631, blue: 0.651)
    }
    
    /// Tertiary text - Medium Gray
    /// Hex: #6E6E73
    public var textTertiary: Color {
        Color(red: 0.431, green: 0.431, blue: 0.451)
    }
    
    /// Primary accent - Warm Amber/Gold
    /// Hex: #D4A574
    public var accent: Color {
        Color(red: 0.831, green: 0.647, blue: 0.455)
    }
    
    /// Secondary accent - Soft Sage
    /// Hex: #8BA888
    public var accentSecondary: Color {
        Color(red: 0.545, green: 0.659, blue: 0.533)
    }
    
    /// Success state - Green
    /// Hex: #34C759
    public var success: Color {
        Color(red: 0.204, green: 0.78, blue: 0.349)
    }
    
    /// Warning state - Orange
    /// Hex: #FF9500
    public var warning: Color {
        Color(red: 1.0, green: 0.584, blue: 0)
    }
    
    // MARK: - Spacing
    
    /// Extra small spacing: 4pt
    public var spacingXS: CGFloat { 4 }
    
    /// Small spacing: 8pt
    public var spacingSM: CGFloat { 8 }
    
    /// Medium spacing: 16pt
    public var spacingMD: CGFloat { 16 }
    
    /// Large spacing: 24pt
    public var spacingLG: CGFloat { 24 }
    
    // MARK: - Corner Radius
    
    /// Medium corner radius: 12pt
    public var cornerRadiusMedium: CGFloat { 12 }
    
    /// Large corner radius: 16pt
    public var cornerRadiusLarge: CGFloat { 16 }
    
    /// Extra large corner radius: 24pt
    public var cornerRadiusExtraLarge: CGFloat { 24 }
    
    // MARK: - Layout
    
    /// Bottom padding for the dock: 24pt
    public var dockBottomPadding: CGFloat { 24 }
    
    /// Height for chip buttons: 44pt (Apple HIG minimum tap target)
    public var chipHeight: CGFloat { 44 }
    
    /// Size for the play button: 48pt
    public var playButtonSize: CGFloat { 48 }
    
    // MARK: - Animation
    
    /// Standard animation for dock transitions.
    ///
    /// Uses a spring animation with 0.3s duration and 0.2 bounce.
    public var standardAnimation: Animation {
        .spring(duration: 0.3, bounce: 0.2)
    }
    
    // MARK: - Typography
    
    /// Caption 1 font: 12pt regular
    public var caption1: Font {
        .system(size: 12, weight: .regular, design: .default)
    }
    
    /// Caption 2 font: 11pt regular
    public var caption2: Font {
        .system(size: 11, weight: .regular, design: .default)
    }
    
    /// Headline font: 17pt semibold
    public var headline: Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    
    /// Subheadline font: 15pt regular
    public var subheadline: Font {
        .system(size: 15, weight: .regular, design: .default)
    }
}

// MARK: - Preview

#Preview("Default Design Tokens") {
    let tokens = DefaultDockDesignTokens()
    
    return ScrollView {
        VStack(spacing: tokens.spacingLG) {
            // Colors
            VStack(alignment: .leading, spacing: tokens.spacingSM) {
                Text("Colors")
                    .font(tokens.headline)
                    .foregroundStyle(tokens.textPrimary)
                
                HStack(spacing: tokens.spacingSM) {
                    colorSwatch("Accent", color: tokens.accent)
                    colorSwatch("Accent 2", color: tokens.accentSecondary)
                    colorSwatch("Success", color: tokens.success)
                    colorSwatch("Warning", color: tokens.warning)
                }
                
                HStack(spacing: tokens.spacingSM) {
                    colorSwatch("BG 1", color: tokens.backgroundPrimary)
                    colorSwatch("BG 2", color: tokens.backgroundSecondary)
                    colorSwatch("BG 3", color: tokens.backgroundTertiary)
                    colorSwatch("Surface", color: tokens.surfaceTertiary)
                }
                
                HStack(spacing: tokens.spacingSM) {
                    textSwatch("Text 1", color: tokens.textPrimary, bg: tokens.backgroundPrimary)
                    textSwatch("Text 2", color: tokens.textSecondary, bg: tokens.backgroundPrimary)
                    textSwatch("Text 3", color: tokens.textTertiary, bg: tokens.backgroundPrimary)
                }
            }
            
            // Typography
            VStack(alignment: .leading, spacing: tokens.spacingSM) {
                Text("Typography")
                    .font(tokens.headline)
                    .foregroundStyle(tokens.textPrimary)
                
                Text("Headline (17pt semibold)")
                    .font(tokens.headline)
                    .foregroundStyle(tokens.textPrimary)
                
                Text("Subheadline (15pt regular)")
                    .font(tokens.subheadline)
                    .foregroundStyle(tokens.textSecondary)
                
                Text("Caption 1 (12pt regular)")
                    .font(tokens.caption1)
                    .foregroundStyle(tokens.textTertiary)
                
                Text("Caption 2 (11pt regular)")
                    .font(tokens.caption2)
                    .foregroundStyle(tokens.textTertiary)
            }
            
            // Spacing
            VStack(alignment: .leading, spacing: tokens.spacingSM) {
                Text("Spacing")
                    .font(tokens.headline)
                    .foregroundStyle(tokens.textPrimary)
                
                HStack(spacing: tokens.spacingSM) {
                    spacingSwatch("XS", size: tokens.spacingXS, tokens: tokens)
                    spacingSwatch("SM", size: tokens.spacingSM, tokens: tokens)
                    spacingSwatch("MD", size: tokens.spacingMD, tokens: tokens)
                    spacingSwatch("LG", size: tokens.spacingLG, tokens: tokens)
                }
            }
            
            // Corner Radius
            VStack(alignment: .leading, spacing: tokens.spacingSM) {
                Text("Corner Radius")
                    .font(tokens.headline)
                    .foregroundStyle(tokens.textPrimary)
                
                HStack(spacing: tokens.spacingSM) {
                    radiusSwatch("Medium", radius: tokens.cornerRadiusMedium, tokens: tokens)
                    radiusSwatch("Large", radius: tokens.cornerRadiusLarge, tokens: tokens)
                    radiusSwatch("XL", radius: tokens.cornerRadiusExtraLarge, tokens: tokens)
                }
            }
        }
        .padding(tokens.spacingLG)
    }
    .background(tokens.backgroundPrimary)
}

// MARK: - Preview Helpers

@ViewBuilder
private func colorSwatch(_ name: String, color: Color) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 60, height: 40)
        
        Text(name)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.7))
    }
}

@ViewBuilder
private func textSwatch(_ name: String, color: Color, bg: Color) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8)
            .fill(bg)
            .frame(width: 60, height: 40)
            .overlay(
                Text("Aa")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            )
        
        Text(name)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.7))
    }
}

@ViewBuilder
private func spacingSwatch(_ name: String, size: CGFloat, tokens: DefaultDockDesignTokens) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 4)
            .fill(tokens.accent)
            .frame(width: size, height: 40)
        
        Text("\(name) (\(Int(size)))")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.7))
    }
}

@ViewBuilder
private func radiusSwatch(_ name: String, radius: CGFloat, tokens: DefaultDockDesignTokens) -> some View {
    VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: radius)
            .fill(tokens.backgroundTertiary)
            .frame(width: 60, height: 40)
        
        Text("\(name) (\(Int(radius)))")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.7))
    }
}
