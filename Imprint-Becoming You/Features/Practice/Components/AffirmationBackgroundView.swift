//
//  AffirmationBackgroundView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - AffirmationBackgroundView

/// Standalone background view with morphing gradient transitions.
///
/// Note: In `PracticePageView`, the background morphing is handled inline
/// within the `VerticalPager` for real-time drag progress interpolation.
/// This view is useful for standalone display (e.g., detail sheets).
struct AffirmationBackgroundView: View {
    
    // MARK: - Properties
    
    let category: GoalCategory?
    
    // MARK: - State
    
    @State private var primaryColor: Color = CategoryGradient.default.primary
    @State private var secondaryColor: Color = CategoryGradient.default.secondary
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [primaryColor.opacity(0.3), secondaryColor],
                startPoint: .top,
                endPoint: .bottom
            )
            
            RadialGradient(
                colors: [
                    primaryColor.opacity(0.15),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
        .onAppear {
            updateColors(animated: false)
        }
        .onChange(of: category) { _, _ in
            updateColors(animated: true)
        }
    }
    
    private func updateColors(animated: Bool) {
        let gradient = CategoryGradient.forCategory(category)
        
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                primaryColor = gradient.primary
                secondaryColor = gradient.secondary
            }
        } else {
            primaryColor = gradient.primary
            secondaryColor = gradient.secondary
        }
    }
}

// MARK: - CategoryGradient

/// Gradient color pairs for each category group.
struct CategoryGradient: Sendable {
    let primary: Color
    let secondary: Color
    
    /// Default gradient
    static let `default` = CategoryGradient(
        primary: Color(red: 0.85, green: 0.75, blue: 0.55),
        secondary: Color(red: 0.08, green: 0.08, blue: 0.10)
    )
    
    /// Returns gradient for a category
    static func forCategory(_ category: GoalCategory?) -> CategoryGradient {
        guard let category = category else { return .default }
        return forGroup(category.group)
    }
    
    /// Returns gradient for a category group
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

// MARK: - Previews

#Preview("Background - Core Identity") {
    AffirmationBackgroundView(category: .confidence)
}

#Preview("Background - Well-being") {
    AffirmationBackgroundView(category: .peace)
}

#Preview("Background - Faith") {
    AffirmationBackgroundView(category: .faith)
}
