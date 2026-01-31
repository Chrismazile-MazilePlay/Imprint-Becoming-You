//
//  CategoryGradient.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import SwiftUI

// MARK: - CategoryGradient

/// Gradient color pairs for each goal category group.
///
/// Each goal category belongs to a group, and each group has a unique
/// gradient palette. Colors are designed for the dark/minimalist aesthetic.
///
/// ## Design System Integration
/// Part of the Core/Design system alongside:
/// - `Colors.swift` - App-wide color tokens
/// - `Theme.swift` - Spacing, corner radius, animation tokens
/// - `Typography.swift` - Font definitions
///
/// ## Accessibility
///
/// Category gradients are decorative backgrounds and should be hidden
/// from VoiceOver. Use the `asDecorativeBackground()` modifier or
/// apply `.accessibilityHidden(true)` when using gradients as backgrounds.
///
/// ## Usage
/// ```swift
/// let gradient = CategoryGradient.forCategory(.confidence)
/// LinearGradient(
///     colors: [gradient.primary.opacity(0.3), gradient.secondary],
///     startPoint: .top,
///     endPoint: .bottom
/// )
/// .accessibilityHidden(true) // Decorative only
/// ```
struct CategoryGradient: Sendable, Equatable {
    
    // MARK: - Properties
    
    /// Primary accent color (used for highlights and overlays)
    let primary: Color
    
    /// Secondary color (used for background base)
    let secondary: Color
    
    // MARK: - Default Gradient
    
    /// Default gradient (warm amber) - used when category is nil
    static let `default` = CategoryGradient(
        primary: Color(red: 0.85, green: 0.75, blue: 0.55),
        secondary: Color(red: 0.08, green: 0.08, blue: 0.10)
    )
    
    // MARK: - Factory Methods
    
    /// Returns gradient for a specific category
    /// - Parameter category: The goal category (nil returns default)
    /// - Returns: Gradient colors for the category's group
    static func forCategory(_ category: GoalCategory?) -> CategoryGradient {
        guard let category = category else { return .default }
        return forGroup(category.group)
    }
    
    /// Returns gradient for a category group
    /// - Parameter group: The goal group
    /// - Returns: Gradient colors for the group
    static func forGroup(_ group: GoalGroup) -> CategoryGradient {
        switch group {
        case .coreIdentity:
            return CategoryGradient(
                primary: Color(red: 0.85, green: 0.65, blue: 0.35),    // Warm amber
                secondary: Color(red: 0.12, green: 0.10, blue: 0.08)
            )
            
        case .performanceAndImpact:
            return CategoryGradient(
                primary: Color(red: 0.75, green: 0.55, blue: 0.30),    // Bronze
                secondary: Color(red: 0.10, green: 0.08, blue: 0.06)
            )
            
        case .wellBeing:
            return CategoryGradient(
                primary: Color(red: 0.45, green: 0.65, blue: 0.75),    // Soft teal
                secondary: Color(red: 0.06, green: 0.10, blue: 0.14)
            )
            
        case .faithBased:
            return CategoryGradient(
                primary: Color(red: 0.70, green: 0.55, blue: 0.75),    // Soft purple
                secondary: Color(red: 0.10, green: 0.08, blue: 0.14)
            )
            
        case .connection:
            return CategoryGradient(
                primary: Color(red: 0.75, green: 0.50, blue: 0.55),    // Dusty rose
                secondary: Color(red: 0.12, green: 0.08, blue: 0.10)
            )
        }
    }
}

// MARK: - Convenience Extensions

extension CategoryGradient {
    
    /// Creates a vertical linear gradient suitable for full-screen backgrounds
    /// - Parameter primaryOpacity: Opacity for the primary color (default 0.3)
    /// - Returns: A LinearGradient from top to bottom
    func asLinearGradient(primaryOpacity: Double = 0.3) -> LinearGradient {
        LinearGradient(
            colors: [primary.opacity(primaryOpacity), secondary],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Creates a radial gradient overlay for ambient lighting effect
    /// - Parameter primaryOpacity: Opacity for the primary color (default 0.12)
    /// - Returns: A RadialGradient centered with fade to clear
    func asRadialOverlay(primaryOpacity: Double = 0.12) -> RadialGradient {
        RadialGradient(
            colors: [primary.opacity(primaryOpacity), Color.clear],
            center: .center,
            startRadius: 50,
            endRadius: 400
        )
    }
}

// MARK: - Accessibility Extensions

extension CategoryGradient {
    
    /// Creates a decorative linear gradient background with accessibility hidden.
    ///
    /// Use this when the gradient is purely decorative and should not be
    /// announced by VoiceOver.
    ///
    /// - Parameter primaryOpacity: Opacity for the primary color (default 0.3)
    /// - Returns: A View with the gradient applied and accessibility hidden
    @ViewBuilder
    func asDecorativeBackground(primaryOpacity: Double = 0.3) -> some View {
        asLinearGradient(primaryOpacity: primaryOpacity)
            .accessibilityHidden(true)
    }
    
    /// Creates a decorative radial overlay with accessibility hidden.
    ///
    /// Use this when the overlay is purely decorative and should not be
    /// announced by VoiceOver.
    ///
    /// - Parameter primaryOpacity: Opacity for the primary color (default 0.12)
    /// - Returns: A View with the overlay applied and accessibility hidden
    @ViewBuilder
    func asDecorativeOverlay(primaryOpacity: Double = 0.12) -> some View {
        asRadialOverlay(primaryOpacity: primaryOpacity)
            .accessibilityHidden(true)
    }
}

// MARK: - View Modifier for Decorative Gradients

/// A view modifier that applies a category gradient as a decorative background.
///
/// The gradient is automatically hidden from VoiceOver.
struct DecorativeGradientBackground: ViewModifier {
    let gradient: CategoryGradient
    let primaryOpacity: Double
    
    init(gradient: CategoryGradient, primaryOpacity: Double = 0.3) {
        self.gradient = gradient
        self.primaryOpacity = primaryOpacity
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                gradient.asLinearGradient(primaryOpacity: primaryOpacity)
                    .accessibilityHidden(true)
            )
    }
}

extension View {
    
    /// Applies a category gradient as a decorative background.
    ///
    /// The gradient is automatically hidden from VoiceOver since it's
    /// purely decorative.
    ///
    /// - Parameters:
    ///   - category: The goal category (nil uses default gradient)
    ///   - primaryOpacity: Opacity for the primary color (default 0.3)
    /// - Returns: A view with the gradient background applied
    func decorativeGradientBackground(
        for category: GoalCategory?,
        primaryOpacity: Double = 0.3
    ) -> some View {
        modifier(DecorativeGradientBackground(
            gradient: CategoryGradient.forCategory(category),
            primaryOpacity: primaryOpacity
        ))
    }
    
    /// Applies a category group gradient as a decorative background.
    ///
    /// The gradient is automatically hidden from VoiceOver since it's
    /// purely decorative.
    ///
    /// - Parameters:
    ///   - group: The goal group
    ///   - primaryOpacity: Opacity for the primary color (default 0.3)
    /// - Returns: A view with the gradient background applied
    func decorativeGradientBackground(
        for group: GoalGroup,
        primaryOpacity: Double = 0.3
    ) -> some View {
        modifier(DecorativeGradientBackground(
            gradient: CategoryGradient.forGroup(group),
            primaryOpacity: primaryOpacity
        ))
    }
}
