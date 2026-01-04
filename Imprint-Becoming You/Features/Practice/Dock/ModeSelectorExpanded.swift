//
//  ModeSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - ModeSelectorExpanded

/// Expanded panel showing all available session modes for selection.
///
/// Appears above the dock when the mode button is tapped.
/// Lists all four session modes with descriptions.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 👁️  Read Only                              │
/// │     Browse affirmations silently           │
/// ├─────────────────────────────────────────────┤
/// │ 🔊  Read Aloud                        ✓    │
/// │     Listen to affirmations read aloud      │
/// ├─────────────────────────────────────────────┤
/// │ 🎙️  Read & Speak                           │
/// │     Listen, then repeat aloud              │
/// ├─────────────────────────────────────────────┤
/// │ 🎤  Speak Only                             │
/// │     Speak affirmations yourself            │
/// └─────────────────────────────────────────────┘
/// ```
struct ModeSelectorExpanded: View {
    
    // MARK: - Properties
    
    /// Currently selected session mode
    let selectedMode: SessionMode
    
    /// Callback when a mode is selected
    let onSelect: (SessionMode) -> Void
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(SessionMode.allCases) { mode in
                ModeOptionRow(
                    mode: mode,
                    isSelected: mode == selectedMode
                ) {
                    onSelect(mode)
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

#Preview("Mode Selector Expanded") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            ModeSelectorExpanded(
                selectedMode: .readThenSpeak,
                onSelect: { mode in
                    print("Selected: \(mode.displayName)")
                }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }
}
