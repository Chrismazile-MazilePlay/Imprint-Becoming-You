//
//  ModeOptionRow.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - ModeOptionRow

/// A single row in the mode selector showing one session mode option.
///
/// Displays the mode icon, name, description, and selection state.
///
/// ## Layout
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ 🎤  Speak Only                         ✓   │
/// │     Speak affirmations yourself            │
/// └─────────────────────────────────────────────┘
/// ```
struct ModeOptionRow: View {
    
    // MARK: - Properties
    
    /// The session mode this row represents
    let mode: SessionMode
    
    /// Whether this mode is currently selected
    let isSelected: Bool
    
    /// Action when row is tapped
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Mode icon
                Image(systemName: mode.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 24)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    
                    Text(mode.description)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppColors.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.displayName): \(mode.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Mode Option - Selected") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack {
            ModeOptionRow(
                mode: .readThenSpeak,
                isSelected: true,
                onTap: {}
            )
        }
        .padding()
    }
}

#Preview("Mode Option - Not Selected") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack {
            ModeOptionRow(
                mode: .speakOnly,
                isSelected: false,
                onTap: {}
            )
        }
        .padding()
    }
}

#Preview("All Mode Options") {
    ZStack {
        AppColors.backgroundSecondary.ignoresSafeArea()
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(SessionMode.allCases) { mode in
                ModeOptionRow(
                    mode: mode,
                    isSelected: mode == .readThenSpeak,
                    onTap: {}
                )
            }
        }
        .padding()
    }
}
