//
//  GoalSelectionView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - GoalSelectionView

/// Goal selection screen where users choose up to 5 focus areas.
///
/// Features:
/// - Grouped categories (Core Identity, Performance, etc.)
/// - Visual selection with haptic feedback
/// - Selection counter showing remaining slots
/// - Validation before proceeding
struct GoalSelectionView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - State
    
    @State private var expandedGroup: GoalGroup? = .coreIdentity
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("What matters to you?")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Choose up to \(viewModel.maxGoals) areas to focus your affirmations")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            
            // Selection counter
            SelectionCounter(
                selected: viewModel.selectedGoals.count,
                max: viewModel.maxGoals
            )
            .padding(.top, AppTheme.Spacing.md)
            
            // Goal categories
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.md) {
                    ForEach(GoalGroup.allCases) { group in
                        GoalGroupSection(
                            group: group,
                            viewModel: viewModel,
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
            
            // Footer
            VStack(spacing: AppTheme.Spacing.md) {
                Button {
                    viewModel.nextStep()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(!viewModel.canProceedFromGoals)
                
                if !viewModel.selectedGoals.isEmpty {
                    Button {
                        viewModel.clearGoals()
                    } label: {
                        Text("Clear Selection")
                    }
                    .buttonStyle(.ghost)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
    }
}

// MARK: - SelectionCounter

/// Shows selected/max count with visual indicator
struct SelectionCounter: View {
    
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

// MARK: - GoalGroupSection

/// Expandable section for a goal group
struct GoalGroupSection: View {
    
    let group: GoalGroup
    @Bindable var viewModel: OnboardingViewModel
    let isExpanded: Bool
    let onToggle: () -> Void
    
    /// Number of selected goals in this group
    private var selectedInGroup: Int {
        viewModel.selectedGoals.filter { $0.group == group }.count
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
                        GoalChip(
                            category: category,
                            isSelected: viewModel.isGoalSelected(category),
                            isDisabled: !viewModel.isGoalSelected(category) && 
                                       viewModel.selectedGoals.count >= viewModel.maxGoals
                        ) {
                            viewModel.toggleGoal(category)
                            HapticFeedback.selection()
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.horizontal, AppTheme.Spacing.xs)
            }
        }
    }
}

// MARK: - GoalChip

/// Individual selectable goal chip
struct GoalChip: View {
    
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

// MARK: - Haptic Feedback Helper

enum HapticFeedback {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}

// MARK: - Previews

#Preview("Goal Selection") {
    GoalSelectionView(viewModel: OnboardingViewModel())
        .background(AppColors.backgroundPrimary)
}

#Preview("Goal Chip - States") {
    VStack(spacing: 16) {
        GoalChip(
            category: .confidence,
            isSelected: false,
            isDisabled: false
        ) {}
        
        GoalChip(
            category: .confidence,
            isSelected: true,
            isDisabled: false
        ) {}
        
        GoalChip(
            category: .confidence,
            isSelected: false,
            isDisabled: true
        ) {}
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("Selection Counter") {
    VStack(spacing: 20) {
        SelectionCounter(selected: 0, max: 5)
        SelectionCounter(selected: 2, max: 5)
        SelectionCounter(selected: 5, max: 5)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
