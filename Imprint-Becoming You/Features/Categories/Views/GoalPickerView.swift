//
//  GoalPickerView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - GoalPickerView

/// Reusable goal picker component with expandable groups.
///
/// This is a pure UI component that can be embedded in any context.
/// The parent view provides the binding and handles persistence.
///
/// ## Usage
/// ```swift
/// @State private var selectedGoals: Set<GoalCategory> = []
///
/// GoalPickerView(
///     selectedGoals: $selectedGoals,
///     maxSelections: 5
/// )
/// ```
struct GoalPickerView: View {
    
    // MARK: - Properties
    
    /// Binding to selected goals
    @Binding var selectedGoals: Set<GoalCategory>
    
    /// Maximum number of selections allowed
    let maxSelections: Int
    
    /// Whether to show the selection counter
    var showCounter: Bool = true
    
    // MARK: - State
    
    @State private var expandedGroup: GoalGroup? = .coreIdentity
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Selection counter
            if showCounter {
                GoalSelectionCounter(
                    selected: selectedGoals.count,
                    max: maxSelections
                )
                .padding(.vertical, AppTheme.Spacing.md)
            }
            
            // Goal categories
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.md) {
                    ForEach(GoalGroup.allCases) { group in
                        GoalPickerGroupSection(
                            group: group,
                            selectedGoals: $selectedGoals,
                            maxSelections: maxSelections,
                            isExpanded: expandedGroup == group
                        ) {
                            withAnimation(AppTheme.Animation.standard) {
                                expandedGroup = expandedGroup == group ? nil : group
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }
}

// MARK: - GoalSelectionCounter

/// Shows selected/max count with visual indicator
struct GoalSelectionCounter: View {
    
    let selected: Int
    let max: Int
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(0..<max, id: \.self) { index in
                Circle()
                    .fill(index < selected ? AppColors.accent : AppColors.surfaceTertiary)
                    .frame(width: 10, height: 10)
                    .animation(AppTheme.Animation.quick, value: selected)
            }
            
            Text("\(selected)/\(max) selected")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.leading, AppTheme.Spacing.xs)
        }
        .accessibilityElement()
        .accessibilityLabel("\(selected) of \(max) goals selected")
    }
}

// MARK: - GoalPickerGroupSection

/// Expandable section for a goal group
struct GoalPickerGroupSection: View {
    
    let group: GoalGroup
    @Binding var selectedGoals: Set<GoalCategory>
    let maxSelections: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    
    /// Number of selected goals in this group
    private var selectedInGroup: Int {
        selectedGoals.filter { $0.group == group }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(group.rawValue)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text(group.description)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Selection badge
                    if selectedInGroup > 0 {
                        Text("\(selectedInGroup)")
                            .font(AppTypography.caption1.weight(.semibold))
                            .foregroundStyle(AppColors.backgroundPrimary)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(AppColors.accent, in: Capsule())
                    }
                    
                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
            
            // Expanded content
            if isExpanded {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
                    ],
                    spacing: AppTheme.Spacing.sm
                ) {
                    ForEach(group.categories) { category in
                        GoalPickerChip(
                            category: category,
                            isSelected: selectedGoals.contains(category),
                            isDisabled: !selectedGoals.contains(category) &&
                                       selectedGoals.count >= maxSelections
                        ) {
                            toggleGoal(category)
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.horizontal, AppTheme.Spacing.xs)
            }
        }
    }
    
    private func toggleGoal(_ category: GoalCategory) {
        if selectedGoals.contains(category) {
            selectedGoals.remove(category)
        } else if selectedGoals.count < maxSelections {
            selectedGoals.insert(category)
        }
        HapticFeedback.selection()
    }
}

// MARK: - GoalPickerChip

/// Individual selectable goal chip
struct GoalPickerChip: View {
    
    let category: GoalCategory
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: category.iconName)
                    .font(.system(size: 14))
                
                Text(category.rawValue)
                    .font(AppTypography.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .animation(AppTheme.Animation.quick, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(category.rawValue), \(category.group.rawValue)")
    }
    
    private var foregroundColor: Color {
        isSelected ? AppColors.accent : AppColors.textSecondary
    }
    
    private var backgroundColor: Color {
        isSelected ? AppColors.accent.opacity(0.15) : AppColors.surfaceTertiary.opacity(0.5)
    }
    
    private var borderColor: Color {
        isSelected ? AppColors.accent : AppColors.surfaceTertiary
    }
}

// MARK: - Previews

#Preview("Goal Picker") {
    struct PreviewWrapper: View {
        @State private var selected: Set<GoalCategory> = [.confidence, .faith]
        
        var body: some View {
            GoalPickerView(
                selectedGoals: $selected,
                maxSelections: 5
            )
            .background(AppColors.backgroundPrimary)
        }
    }
    return PreviewWrapper()
}

#Preview("Goal Picker Chip - States") {
    VStack(spacing: 16) {
        GoalPickerChip(
            category: .confidence,
            isSelected: false,
            isDisabled: false
        ) {}
        
        GoalPickerChip(
            category: .confidence,
            isSelected: true,
            isDisabled: false
        ) {}
        
        GoalPickerChip(
            category: .confidence,
            isSelected: false,
            isDisabled: true
        ) {}
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Goal Selection Counter") {
    VStack(spacing: 20) {
        GoalSelectionCounter(selected: 0, max: 5)
        GoalSelectionCounter(selected: 2, max: 5)
        GoalSelectionCounter(selected: 5, max: 5)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
