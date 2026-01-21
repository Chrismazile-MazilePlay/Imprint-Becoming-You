//
//  ModeOptionRow.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - ModeOptionRow

/// A single option row in the mode selector menu.
///
/// ## Usage
///
/// ```swift
/// ModeOptionRow(
///     mode: .readAndSpeak,
///     isSelected: currentMode == .readAndSpeak
/// ) {
///     selectMode(.readAndSpeak)
/// }
/// ```
public struct ModeOptionRow: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let mode: DockMode
    public let isSelected: Bool
    public let action: () -> Void
    
    // MARK: - Initialization
    
    public init(
        mode: DockMode,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.mode = mode
        self.isSelected = isSelected
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.selectionFeedback()
            action()
        } label: {
            HStack(spacing: tokens.spacingSM) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? tokens.accent : tokens.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(tokens.headline)
                        .foregroundStyle(isSelected ? tokens.accent : tokens.textPrimary)
                    
                    Text(mode.description)
                        .font(tokens.caption1)
                        .foregroundStyle(tokens.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                }
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.vertical, tokens.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Mode Option Row") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 0) {
            ModeOptionRow(mode: .readAndSpeak, isSelected: true, action: {})
            Divider().background(Color.white.opacity(0.1))
            ModeOptionRow(mode: .readAloud, isSelected: false, action: {})
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
        .padding()
    }
}
