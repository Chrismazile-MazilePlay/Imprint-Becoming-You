//
//  BinauralSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - BinauralSelectorExpanded

/// Expanded panel showing all available binaural presets for selection.
///
/// Appears above the dock when the binaural button is tapped.
/// Lists all four presets with descriptions.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 🔇  Off                                    │
/// ├─────────────────────────────────────────────┤
/// │ 🧠  Focus                              ✓   │
/// │     Beta waves (14 Hz) for concentration   │
/// ├─────────────────────────────────────────────┤
/// │ 🍃  Relax                                  │
/// │     Alpha waves (10 Hz) for calm           │
/// ├─────────────────────────────────────────────┤
/// │ 🌙  Sleep                                  │
/// │     Theta waves (6 Hz) for rest            │
/// └─────────────────────────────────────────────┘
/// ```
struct BinauralSelectorExpanded: View {
    
    // MARK: - Properties
    
    /// Currently selected binaural preset
    let selectedPreset: BinauralPreset
    
    /// Callback when a preset is selected
    let onSelect: (BinauralPreset) -> Void
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(BinauralPreset.allCases) { preset in
                BinauralOptionRow(
                    preset: preset,
                    isSelected: preset == selectedPreset
                ) {
                    onSelect(preset)
                    HapticFeedback.selection()
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        // No horizontal padding - inherits from parent to match dock width
    }
}

// MARK: - Previews

#Preview("Binaural Selector Expanded") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            BinauralSelectorExpanded(
                selectedPreset: .focus,
                onSelect: { preset in
                    print("Selected: \(preset.displayName)")
                }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }
}
