//
//  DockModeButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - DockModeButton

/// Button displaying the current session mode with expansion indicator.
///
/// Appears in the dock's bottom row, allowing users to change
/// the practice mode (Read Only, Read Aloud, Read & Speak, Speak Only).
///
/// ## Layout
/// ```
/// ┌─────────────────────┐
/// │ 🔊 Read Aloud  ∧   │
/// └─────────────────────┘
/// ```
struct DockModeButton: View {
    
    // MARK: - Properties
    
    /// Current session mode to display
    let mode: SessionMode
    
    /// Whether the mode selector is expanded
    let isExpanded: Bool
    
    /// Whether to show the mode label text
    var showLabel: Bool = true
    
    /// Action when button is tapped
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .semibold))
                
                if showLabel {
                    Text(mode.displayName)
                        .font(AppTypography.caption1.weight(.medium))
                        .lineLimit(1)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.accent.opacity(0.15))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Session mode: \(mode.displayName)")
        .accessibilityHint("Double tap to change mode")
    }
}

// MARK: - Previews

#Preview("Mode Button - Read Only") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        DockModeButton(
            mode: .readOnly,
            isExpanded: false,
            onTap: {}
        )
    }
}

#Preview("Mode Button - Expanded") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        DockModeButton(
            mode: .readThenSpeak,
            isExpanded: true,
            onTap: {}
        )
    }
}

#Preview("Mode Button - No Label") {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        DockModeButton(
            mode: .speakOnly,
            isExpanded: false,
            showLabel: false,
            onTap: {}
        )
    }
}
