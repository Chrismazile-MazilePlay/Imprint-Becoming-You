//
//  CategoryBadge.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/4/26.
//

import SwiftUI

// MARK: - CategoryBadge

/// A pill-shaped badge displaying the goal category with icon.
///
/// Used throughout the app to indicate which category an affirmation belongs to.
/// Color is derived from the category's group gradient.
///
/// ## Usage
/// ```swift
/// if let category = affirmation.goalCategory {
///     CategoryBadge(category: category)
/// }
/// ```
struct CategoryBadge: View {
    
    // MARK: - Properties
    
    let category: GoalCategory
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: category.iconName)
                .font(.system(size: 12, weight: .semibold))
            
            Text(category.rawValue)
                .font(AppTypography.caption1.weight(.medium))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Category: \(category.rawValue)")
    }
    
    // MARK: - Private
    
    private var badgeColor: Color {
        CategoryGradient.forGroup(category.group).primary
    }
}

// MARK: - Previews

#Preview("Category Badge - All Categories") {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(GoalCategory.allCases, id: \.self) { category in
                CategoryBadge(category: category)
            }
        }
        .padding()
    }
    .background(AppColors.backgroundPrimary)
}

#Preview("Category Badge - Single") {
    CategoryBadge(category: .confidence)
        .padding()
        .background(AppColors.backgroundPrimary)
}
