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
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 🧠  Focus                              ✓   │
/// │     Beta waves (14 Hz) for concentration   │
/// └─────────────────────────────────────────────┘
/// ```
struct BinauralOptionRow: View {
    
    // MARK: - Properties
    
    /// The binaural preset this row represents
    let preset: BinauralPreset
    
    /// Whether this preset is currently selected
    let isSelected: Bool
    
    /// Action when row is tapped
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Preset icon
                Image(systemName: preset.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accentSecondary : AppColors.textSecondary)
                    .frame(width: 24)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    
                    // Only show description for active presets
                    if preset != .off {
                        Text(preset.description)
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accentSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppColors.accentSecondary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.displayName): \(preset.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Binaural Option - Selected") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack {
            BinauralOptionRow(
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
            BinauralOptionRow(
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
                BinauralOptionRow(
                    preset: preset,
                    isSelected: preset == .focus,
                    onTap: {}
                )
            }
        }
        .padding()
    }
}
