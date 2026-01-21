//
//  ModeSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - ModeSelectorExpanded

/// Expanded panel showing available session modes for selection.
///
/// Appears above the dock when the mode button is tapped.
/// Can show all modes or only playable modes (excludes Read Only).
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 👁️  Read Only                              │  ← Only in practice mode
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
struct ModeSelectorExpanded1: View {
    
    // MARK: - Properties
    
    /// Currently selected session mode
    let selectedMode: SessionMode
    
    /// Whether to show only playable modes (excludes Read Only).
    /// Use `true` for configuration contexts (Results, Favorites, Saved Sessions).
    /// Use `false` for practice mode (Home, Active Session).
    var showOnlyPlayableModes: Bool = false
    
    /// Callback when a mode is selected
    let onSelect: (SessionMode) -> Void
    
    // MARK: - Computed Properties
    
    /// Modes to display based on `showOnlyPlayableModes` flag
    private var availableModes: [SessionMode] {
        showOnlyPlayableModes ? SessionMode.playableCases : SessionMode.allCases
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(availableModes) { mode in
                ModeOptionRow1(
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

#Preview("Mode Selector - All Modes") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            ModeSelectorExpanded1(
                selectedMode: .readThenSpeak,
                showOnlyPlayableModes: false,
                onSelect: { mode in
                    print("Selected: \(mode.displayName)")
                }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }
}

#Preview("Mode Selector - Playable Only") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        
        VStack {
            Spacer()
            
            ModeSelectorExpanded1(
                selectedMode: .readAloud,
                showOnlyPlayableModes: true,
                onSelect: { mode in
                    print("Selected: \(mode.displayName)")
                }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }
}
