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
/// ## Stable Layout
/// Uses fixed dimensions and always-present (opacity-controlled) checkmark
/// to prevent any layout shifts when selection changes.
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
    
    // MARK: - Constants
    
    /// Minimum row height for consistent layout
    private let minRowHeight: CGFloat = 56
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Mode icon - fixed width
                Image(systemName: mode.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                
                // Text content - allows wrapping
                textContent
                
                // Selection indicator - always present, opacity controlled
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.accent)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(minHeight: minRowHeight)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AppColors.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
        // Disable implicit animations to prevent bounce
        .animation(nil, value: isSelected)
        .accessibilityLabel("\(mode.displayName): \(mode.description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    // MARK: - Text Content
    
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mode.displayName)
                .font(AppTypography.headline)
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            
            Text(mode.description)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview("Selection Change - No Bounce") {
    struct PreviewWrapper: View {
        @State private var selected: SessionMode = .readOnly
        
        var body: some View {
            ZStack {
                AppColors.backgroundSecondary.ignoresSafeArea()
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(SessionMode.allCases) { mode in
                        ModeOptionRow(
                            mode: mode,
                            isSelected: mode == selected,
                            onTap: { selected = mode }
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    return PreviewWrapper()
}
