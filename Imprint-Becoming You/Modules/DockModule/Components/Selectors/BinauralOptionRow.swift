//
//  BinauralOptionRow.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - BinauralOptionRow

/// A single option row in the binaural selector menu.
///
/// ## Usage
///
/// ```swift
/// BinauralOptionRow(
///     preset: .focus,
///     isSelected: currentPreset == .focus
/// ) {
///     selectPreset(.focus)
/// }
/// ```
public struct BinauralOptionRow: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let preset: DockBinauralPreset
    public let isSelected: Bool
    public let action: () -> Void
    
    // MARK: - Initialization
    
    public init(
        preset: DockBinauralPreset,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.preset = preset
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
                Image(systemName: preset.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(tokens.headline)
                        .foregroundStyle(isSelected ? tokens.accent : tokens.textPrimary)
                    
                    Text(preset.description)
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
        .accessibilityLabel(preset.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    // MARK: - Icon Color
    
    private var iconColor: Color {
        if isSelected { return tokens.accent }
        
        switch preset {
        case .off: return tokens.textTertiary
        case .focus: return tokens.accentSecondary
        case .relax: return tokens.success
        case .sleep: return Color.purple.opacity(0.8)
        }
    }
}

// MARK: - Previews

#Preview("Binaural Option Row") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 0) {
            BinauralOptionRow(preset: .focus, isSelected: true, action: {})
            Divider().background(Color.white.opacity(0.1))
            BinauralOptionRow(preset: .relax, isSelected: false, action: {})
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
        .padding()
    }
}
