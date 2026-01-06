//
//  FaithPreferenceView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/5/26.
//

import SwiftUI

// MARK: - FaithPreferenceView

/// Onboarding screen for selecting faith-based content preference.
///
/// Presents the user with a clear choice:
/// - Include Biblical scripture and faith-based affirmations
/// - Secular content only
///
/// Also displays a preview of the 15 faith-based categories so users
/// understand what they're opting into or declining.
///
/// ## Design Notes
/// - Category preview is non-interactive (display only)
/// - User must make a selection to proceed
/// - Choice is stored in UserProfile.includeFaithContent
///
/// - TODO: Phase 9 - Add Settings UI for changing this preference after onboarding
struct FaithPreferenceView: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Header
                    header
                    
                    // Selection options
                    selectionOptions
                    
                    // Category preview
                    categoryPreview
                    
                    // Settings note
                    settingsNote
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            
            // Footer with continue button
            footer
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Icon
            Image(systemName: "book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)
            
            // Title
            Text("Faith-Based Content")
                .font(AppTypography.title1)
                .foregroundStyle(AppColors.textPrimary)
            
            // Description
            Text("Imprint includes affirmations and scripture inspired by Biblical teachings.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Selection Options
    
    private var selectionOptions: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Include faith content option
            FaithOptionCard(
                icon: "cross.fill",
                title: "Yes, include faith-based content",
                subtitle: "Biblical scripture and spiritual affirmations",
                isSelected: viewModel.includeFaithContent == true
            ) {
                viewModel.setFaithPreference(true)
            }
            
            // Secular only option
            FaithOptionCard(
                icon: "star.fill",
                title: "No thanks, secular content only",
                subtitle: "Personal growth without religious content",
                isSelected: viewModel.includeFaithContent == false
            ) {
                viewModel.setFaithPreference(false)
            }
        }
    }
    
    // MARK: - Category Preview
    
    private var categoryPreview: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Section header
            Text("Categories included with faith-based content:")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
            
            // Category chips grid (non-interactive)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
                ],
                spacing: AppTheme.Spacing.sm
            ) {
                ForEach(viewModel.faithCategories) { category in
                    FaithCategoryPreviewChip(category: category)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.surfaceSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
    }
    
    // MARK: - Settings Note
    
    private var settingsNote: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "gear")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)
            
            // TODO: Phase 9 - Implement Settings screen with faith preference toggle
            Text("You can change this anytime in Settings.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Button {
                viewModel.nextStep()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(!viewModel.canProceedFromFaithPreference)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.lg)
        .background(
            AppColors.backgroundPrimary
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
        )
    }
}

// MARK: - FaithOptionCard

/// Selectable option card for faith preference choice.
struct FaithOptionCard: View {
    
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isSelected ? AppColors.accent.opacity(0.15) : AppColors.surfaceTertiary)
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text(subtitle)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppColors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                    .strokeBorder(
                        isSelected ? AppColors.accent : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(AppTheme.Animation.quick, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

// MARK: - FaithCategoryPreviewChip

/// Non-interactive chip displaying a faith category for preview purposes.
struct FaithCategoryPreviewChip: View {
    
    let category: GoalCategory
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: category.iconName)
                .font(.system(size: 10))
            
            Text(category.rawValue)
                .font(AppTypography.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .foregroundStyle(AppColors.textSecondary)
        .background(AppColors.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small))
        .accessibilityLabel(category.rawValue)
    }
}

// MARK: - Previews

#Preview("Faith Preference - No Selection") {
    FaithPreferenceView(viewModel: OnboardingViewModel())
        .background(AppColors.backgroundPrimary)
}

#Preview("Faith Preference - Include Selected") {
    let vm = OnboardingViewModel()
    vm.includeFaithContent = true
    
    return FaithPreferenceView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
}

#Preview("Faith Preference - Secular Selected") {
    let vm = OnboardingViewModel()
    vm.includeFaithContent = false
    
    return FaithPreferenceView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
}
