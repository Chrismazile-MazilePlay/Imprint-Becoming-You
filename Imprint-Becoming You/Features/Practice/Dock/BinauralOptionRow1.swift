//
//  BinauralOptionRow.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - BinauralOptionRow

/// A single row in the binaural selector showing one preset option.
///
/// Displays the preset icon, name, description (for active presets),
/// and selection state.
///
/// ## Stable Layout
/// This component uses fixed dimensions to prevent layout shifts when
/// selection state changes. All elements have fixed sizes and no
/// implicit animations that could cause bouncing.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 🧠  Focus                              ✓   │
/// │     Beta waves (14 Hz) for concentration   │
/// └─────────────────────────────────────────────┘
/// ```
struct BinauralOptionRow1: View {
    
    // MARK: - Properties
    
    /// The binaural preset this row represents
    let preset: BinauralPreset
    
    /// Whether this preset is currently selected
    let isSelected: Bool
    
    /// Action when row is tapped
    let onTap: () -> Void
    
    // MARK: - Constants
    
    /// Fixed height for rows with descriptions
    private let rowHeightWithDescription: CGFloat = 56
    
    /// Fixed height for "Off" row (no description)
    private let rowHeightOffOnly: CGFloat = 44
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Preset icon - fixed width
                Image(systemName: preset.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accentSecondary : AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                
                // Text content - fixed layout
                textContent
                
                // Selection indicator - always present, opacity controlled
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.accentSecondary)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: preset == .off ? rowHeightOffOnly : rowHeightWithDescription)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AppColors.accentSecondary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        // Disable all implicit animations on this view
        .animation(nil, value: isSelected)
        .accessibilityLabel("\(preset.displayName): \(preset.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    // MARK: - Text Content
    
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preset.displayName)
                .font(AppTypography.headline)
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            
            // Description for active presets - single line
            if preset != .off {
                Text(preset.description)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Binaural Option - Selected") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack {
            BinauralOptionRow1(
                preset: .focus,
                isSelected: true,
                onTap: {}
            )
        }
        .padding()
    }
}

#Preview("Binaural Option - Off") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack {
            BinauralOptionRow1(
                preset: .off,
                isSelected: false,
                onTap: {}
            )
        }
        .padding()
    }
}

#Preview("All Binaural Options") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(BinauralPreset.allCases) { preset in
                BinauralOptionRow1(
                    preset: preset,
                    isSelected: preset == .focus,
                    onTap: {}
                )
            }
        }
        .padding()
    }
}

#Preview("Selection Change - No Bounce") {
    struct PreviewWrapper: View {
        @State private var selected: BinauralPreset = .off
        
        var body: some View {
            ZStack {
                AppColors.backgroundSecondary.ignoresSafeArea()
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(BinauralPreset.allCases) { preset in
                        BinauralOptionRow1(
                            preset: preset,
                            isSelected: preset == selected,
                            onTap: { selected = preset }
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    return PreviewWrapper()
}
