//
//  DockModeButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//
/*
import SwiftUI

// MARK: - DockModeButton

/// A chip-style button for selecting practice modes.
///
/// Displays the current mode with icon and chevron indicator. Can optionally
/// show the mode name label for expanded views (configuration mode).
///
/// ## Usage
///
/// ```swift
/// DockModeButton(
///     mode: adapter.currentMode,
///     isExpanded: adapter.isModeSelectorExpanded,
///     showLabel: true
/// ) {
///     adapter.isModeSelectorExpanded.toggle()
/// }
/// ```
public struct DockModeButton: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let mode: DockMode
    public let isExpanded: Bool
    public let showLabel: Bool
    public let action: () -> Void
    
    // MARK: - Initialization
    
    public init(
        mode: DockMode,
        isExpanded: Bool,
        showLabel: Bool = false,
        action: @escaping () -> Void
    ) {
        self.mode = mode
        self.isExpanded = isExpanded
        self.showLabel = showLabel
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.lightImpact()
            action()
        } label: {
            HStack(spacing: tokens.spacingXS) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .medium))
                
                if showLabel {
                    Text(mode.displayName)
                        .font(tokens.caption1.weight(.medium))
                }
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tokens.textSecondary)
            .padding(.horizontal, tokens.spacingSM)
            .frame(height: tokens.chipHeight)
            .background(
                Capsule()
                    .fill(tokens.backgroundTertiary)
            )
        }
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityHint("Tap to \(isExpanded ? "close" : "open") mode selector")
    }
}

// MARK: - Previews

#Preview("Mode Button - Icon Only") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockModeButton(mode: .readAndSpeak, isExpanded: false, action: {})
    }
}

#Preview("Mode Button - With Label") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockModeButton(mode: .readAndSpeak, isExpanded: false, showLabel: true, action: {})
    }
}

#Preview("Mode Button - All Modes") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 12) {
            ForEach(DockMode.allCases) { mode in
                DockModeButton(mode: mode, isExpanded: false, showLabel: true, action: {})
            }
        }
    }
}
*/
