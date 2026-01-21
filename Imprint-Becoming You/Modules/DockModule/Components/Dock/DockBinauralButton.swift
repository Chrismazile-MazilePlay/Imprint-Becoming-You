//
//  DockBinauralButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//
/*
import SwiftUI

// MARK: - DockBinauralButton

/// A chip-style button for selecting binaural presets.
///
/// Displays the current preset with icon, name, and chevron indicator.
/// Visually highlights when a binaural preset is active (not "off").
///
/// ## Usage
///
/// ```swift
/// DockBinauralButton(
///     preset: adapter.binauralPreset,
///     isExpanded: adapter.isBinauralSelectorExpanded
/// ) {
///     adapter.isBinauralSelectorExpanded.toggle()
/// }
/// ```
public struct DockBinauralButton: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let preset: DockBinauralPreset
    public let isExpanded: Bool
    public let action: () -> Void
    
    // MARK: - Initialization
    
    public init(
        preset: DockBinauralPreset,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) {
        self.preset = preset
        self.isExpanded = isExpanded
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.lightImpact()
            action()
        } label: {
            HStack(spacing: tokens.spacingXS) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 14, weight: .medium))
                
                Text(preset.displayName)
                    .font(tokens.caption1.weight(.medium))
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(preset.isActive ? tokens.accent : tokens.textSecondary)
            .padding(.horizontal, tokens.spacingSM)
            .frame(height: tokens.chipHeight)
            .background(
                Capsule()
                    .fill(preset.isActive ? tokens.accent.opacity(0.15) : tokens.backgroundTertiary)
            )
        }
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityHint("Tap to \(isExpanded ? "close" : "open") binaural selector")
    }
}

// MARK: - Previews

#Preview("Binaural Button - Off") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockBinauralButton(preset: .off, isExpanded: false, action: {})
    }
}

#Preview("Binaural Button - Focus") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockBinauralButton(preset: .focus, isExpanded: false, action: {})
    }
}

#Preview("Binaural Button - All Presets") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 12) {
            ForEach(DockBinauralPreset.allCases) { preset in
                DockBinauralButton(preset: preset, isExpanded: false, action: {})
            }
        }
    }
}
*/
