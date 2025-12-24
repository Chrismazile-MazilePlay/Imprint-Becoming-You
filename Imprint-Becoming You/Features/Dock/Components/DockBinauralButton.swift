//
//  DockBinauralButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - DockBinauralButton

/// Button displaying the current binaural preset with expansion indicator.
///
/// Appears in the dock's bottom row, allowing users to change
/// the binaural beat preset (Off, Focus, Relax, Sleep).
///
/// ## Layout
/// ```
/// ┌─────────────────────┐
/// │ 🧠 Focus  ∧        │
/// └─────────────────────┘
/// ```
struct DockBinauralButton: View {
    
    // MARK: - Properties
    
    /// Current binaural preset to display
    let preset: BinauralPreset
    
    /// Whether the binaural selector is expanded
    let isExpanded: Bool
    
    /// Action when button is tapped
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 14, weight: .semibold))
                
                if preset != .off {
                    Text(preset.displayName)
                        .font(AppTypography.caption1.weight(.medium))
                        .lineLimit(1)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(preset == .off ? AppColors.textSecondary : AppColors.accentSecondary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                preset == .off
                    ? AppColors.surfaceTertiary
                    : AppColors.accentSecondary.opacity(0.15)
            )
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Binaural beats: \(preset.displayName)")
        .accessibilityHint("Double tap to change binaural preset")
    }
}

// MARK: - Previews

#Preview("Binaural Button - Off") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        DockBinauralButton(
            preset: .off,
            isExpanded: false,
            onTap: {}
        )
    }
}

#Preview("Binaural Button - Focus") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        DockBinauralButton(
            preset: .focus,
            isExpanded: false,
            onTap: {}
        )
    }
}

#Preview("Binaural Button - Expanded") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        DockBinauralButton(
            preset: .relax,
            isExpanded: true,
            onTap: {}
        )
    }
}
