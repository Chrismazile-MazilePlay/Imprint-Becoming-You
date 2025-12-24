//
//  Theme.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - App Theme

/// Central theme configuration for the Imprint app.
///
/// Provides consistent styling, spacing, and animation configurations
/// throughout the application.
enum AppTheme {
    
    // MARK: - Spacing
    
    /// Spacing scale for consistent layouts
    enum Spacing {
        /// Extra small spacing: 4pt
        static let xs: CGFloat = 4
        /// Small spacing: 8pt
        static let sm: CGFloat = 8
        /// Medium spacing: 16pt
        static let md: CGFloat = 16
        /// Large spacing: 24pt
        static let lg: CGFloat = 24
        /// Extra large spacing: 32pt
        static let xl: CGFloat = 32
        /// Extra extra large spacing: 48pt
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    
    /// Corner radius scale for consistent rounding
    enum CornerRadius {
        /// Small radius: 8pt
        static let small: CGFloat = 8
        /// Medium radius: 12pt
        static let medium: CGFloat = 12
        /// Large radius: 16pt
        static let large: CGFloat = 16
        /// Extra large radius: 24pt
        static let extraLarge: CGFloat = 24
        /// Full/pill radius: 9999pt
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    
    /// Shadow configurations
    enum Shadow {
        /// Subtle shadow for cards
        static let subtle = ShadowStyle(
            color: .black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )
        
        /// Medium shadow for elevated elements
        static let medium = ShadowStyle(
            color: .black.opacity(0.25),
            radius: 16,
            x: 0,
            y: 8
        )
        
        /// Strong shadow for modals
        static let strong = ShadowStyle(
            color: .black.opacity(0.35),
            radius: 24,
            x: 0,
            y: 12
        )
        
        /// Glow effect for accent elements
        static let glow = ShadowStyle(
            color: AppColors.accent.opacity(0.4),
            radius: 12,
            x: 0,
            y: 0
        )
    }
    
    // MARK: - Animation
    
    /// Animation configurations
    enum Animation {
        /// Standard spring animation
        static let standard = SwiftUI.Animation.spring(duration: 0.3, bounce: 0.2)
        
        /// Quick animation for micro-interactions
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
        
        /// Slow animation for deliberate transitions
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        
        /// Bouncy animation for playful feedback
        static let bouncy = SwiftUI.Animation.spring(duration: 0.4, bounce: 0.4)
        
        /// Smooth animation for page transitions
        static let pageTransition = SwiftUI.Animation.easeInOut(duration: 0.4)
    }
    
    // MARK: - Haptics
    
    /// Haptic feedback configurations
    enum Haptics {
        /// Light impact for subtle feedback
        static func light() {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        
        /// Medium impact for standard actions
        static func medium() {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        
        /// Success feedback
        static func success() {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        
        /// Error feedback
        static func error() {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        /// Selection changed feedback
        static func selection() {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        }
    }
}

// MARK: - Shadow Style

/// Configuration for shadow effects
struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Modifiers

/// Card styling modifier
struct CardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let hasBorder: Bool
    
    init(cornerRadius: CGFloat = AppTheme.CornerRadius.large, hasBorder: Bool = true) {
        self.cornerRadius = cornerRadius
        self.hasBorder = hasBorder
    }
    
    func body(content: Content) -> some View {
        content
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(hasBorder ? AppColors.border : .clear, lineWidth: 1)
            )
    }
}

/// Elevated card styling modifier with shadow
struct ElevatedCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let shadow: ShadowStyle
    
    init(
        cornerRadius: CGFloat = AppTheme.CornerRadius.large,
        shadow: ShadowStyle = AppTheme.Shadow.subtle
    ) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
    
    func body(content: Content) -> some View {
        content
            .background(AppColors.backgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }
}

/// Glow effect modifier for accent elements
struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    init(color: Color = AppColors.accent, radius: CGFloat = 12) {
        self.color = color
        self.radius = radius
    }
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.4), radius: radius)
            .shadow(color: color.opacity(0.2), radius: radius * 2)
    }
}

/// Press effect modifier for buttons
struct PressEffect: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(AppTheme.Animation.quick, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - View Extensions

extension View {
    
    /// Applies card styling
    func cardStyle(cornerRadius: CGFloat = AppTheme.CornerRadius.large, hasBorder: Bool = true) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, hasBorder: hasBorder))
    }
    
    /// Applies elevated card styling with shadow
    func elevatedCardStyle(
        cornerRadius: CGFloat = AppTheme.CornerRadius.large,
        shadow: ShadowStyle = AppTheme.Shadow.subtle
    ) -> some View {
        modifier(ElevatedCardStyle(cornerRadius: cornerRadius, shadow: shadow))
    }
    
    /// Applies glow effect
    func glowEffect(color: Color = AppColors.accent, radius: CGFloat = 12) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
    
    /// Applies press animation effect
    func pressEffect() -> some View {
        modifier(PressEffect())
    }
    
    /// Applies standard horizontal padding
    func horizontalPadding() -> some View {
        padding(.horizontal, Constants.Layout.horizontalPadding)
    }
    
    /// Applies safe area aware background
    func appBackground() -> some View {
        self
            .background(AppColors.backgroundPrimary)
            .ignoresSafeArea()
    }
    
    /// Applies gradient background
    func gradientBackground() -> some View {
        self
            .background(LinearGradient.backgroundGradient)
            .ignoresSafeArea()
    }
}

// MARK: - Button Styles

/// Primary button style with accent color
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.buttonPrimary)
            .foregroundStyle(AppColors.textInverted)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                isEnabled
                    ? AppColors.accent
                    : AppColors.disabled
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
    }
}

/// Secondary button style with outline
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.buttonPrimary)
            .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .stroke(isEnabled ? AppColors.border : AppColors.disabled, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
    }
}

/// Ghost/text button style
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.buttonSecondary)
            .foregroundStyle(AppColors.accent)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(AppTheme.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Preview

#Preview("Theme Components") {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.xl) {
            // Cards
            VStack(spacing: AppTheme.Spacing.md) {
                Text("Cards")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Standard Card")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .cardStyle()
                
                Text("Elevated Card")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .elevatedCardStyle()
            }
            
            // Buttons
            VStack(spacing: AppTheme.Spacing.md) {
                Text("Buttons")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Button("Primary Button") {}
                    .buttonStyle(.primary)
                
                Button("Secondary Button") {}
                    .buttonStyle(.secondary)
                
                Button("Ghost Button") {}
                    .buttonStyle(.ghost)
            }
            
            // Glow Effect
            VStack(spacing: AppTheme.Spacing.md) {
                Text("Effects")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 60, height: 60)
                    .glowEffect()
            }
        }
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}
