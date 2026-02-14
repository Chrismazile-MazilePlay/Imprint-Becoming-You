//
//  DockMenuSelectorButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/20/26.
//

import SwiftUI

// MARK: - DockMenuSelectorButton

/// A reusable chip-style button for menu selection (mode, music, settings).
///
/// Displays icon + optional label + chevron. When `label` is empty, shows only
/// icon + chevron (used for the gear/settings button). Supports active state
/// highlighting for options like music categories.
///
/// ## Accessibility
///
/// - **Label:** "[Label] selector" (e.g., "Read Aloud selector")
/// - **Value:** "Expanded" or "Collapsed"
/// - **Hint:** Describes toggle action
/// - **Traits:** `.isSelected` when expanded
///
/// ## Usage
///
/// ```swift
/// // Mode selector
/// DockMenuSelectorButton(
///     icon: adapter.currentMode.iconName,
///     label: adapter.currentMode.displayName,
///     isExpanded: adapter.isModeSelectorExpanded,
///     isActive: false,
///     action: { toggleModeSelector() }
/// )
///
/// // Music selector (with active highlighting)
/// DockMenuSelectorButton(
///     icon: adapter.musicCategory.iconName,
///     label: adapter.musicCategory.displayName,
///     isExpanded: adapter.isMusicSelectorExpanded,
///     isActive: adapter.musicCategory.isActive,
///     action: { toggleMusicSelector() }
/// )
/// ```
public struct DockMenuSelectorButton: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    /// SF Symbol name for the icon
    public let icon: String
    
    /// Display label for the button
    public let label: String
    
    /// Whether the associated menu is expanded (affects chevron direction)
    public let isExpanded: Bool
    
    /// Whether the button should show active/highlighted state
    public let isActive: Bool
    
    /// Action to perform on tap
    public let action: () -> Void
    
    // MARK: - Initialization
    
    public init(
        icon: String,
        label: String,
        isExpanded: Bool,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isExpanded = isExpanded
        self.isActive = isActive
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.lightImpact()
            action()
        } label: {
            HStack(spacing: tokens.spacingXS) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))

                if !label.isEmpty {
                    Text(label)
                        .font(tokens.caption1.weight(.medium))
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, tokens.spacingSM)
            .frame(height: tokens.chipHeight)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
        }
        // MARK: Accessibility
        .accessibilityLabel(label.isEmpty ? "Settings selector" : "\(label) selector")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") options")
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
    }
    
    // MARK: - Computed Properties
    
    private var foregroundColor: Color {
        isActive ? tokens.accent : tokens.textSecondary
    }
    
    private var backgroundColor: Color {
        isActive ? tokens.accent.opacity(0.15) : tokens.backgroundTertiary
    }
}

// MARK: - Previews

#Preview("Menu Selector - Mode (Inactive)") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 12) {
            DockMenuSelectorButton(
                icon: "book.fill",
                label: "Read Only",
                isExpanded: false,
                isActive: false,
                action: {}
            )
            DockMenuSelectorButton(
                icon: "speaker.wave.2.fill",
                label: "Read Aloud",
                isExpanded: true,
                isActive: false,
                action: {}
            )
        }
    }
}

#Preview("Menu Selector - Music (Active)") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 12) {
            DockMenuSelectorButton(
                icon: "moon.zzz.fill",
                label: "Off",
                isExpanded: false,
                isActive: false,
                action: {}
            )
            DockMenuSelectorButton(
                icon: "brain.head.profile",
                label: "Focus",
                isExpanded: false,
                isActive: true,
                action: {}
            )
        }
    }
}

#Preview("Menu Selector - All States") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                DockMenuSelectorButton(
                    icon: "waveform",
                    label: "Speak Only",
                    isExpanded: false,
                    isActive: false,
                    action: {}
                )
                DockMenuSelectorButton(
                    icon: "ear",
                    label: "Calm",
                    isExpanded: false,
                    isActive: true,
                    action: {}
                )
            }
            HStack(spacing: 12) {
                DockMenuSelectorButton(
                    icon: "book.fill",
                    label: "Read Only",
                    isExpanded: true,
                    isActive: false,
                    action: {}
                )
                DockMenuSelectorButton(
                    icon: "moon.zzz.fill",
                    label: "Off",
                    isExpanded: true,
                    isActive: false,
                    action: {}
                )
            }
        }
    }
}
