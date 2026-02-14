//
//  DockCircularButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/8/26.
//

import SwiftUI

// MARK: - DockCircularButton

/// A circular icon-only button for the dock selector row.
///
/// Used for Music (left) and Gear/Settings (right) buttons. Displays a single
/// SF Symbol icon in a circle, with active state highlighting. No label, no chevron.
///
/// ## Design Specifications
///
/// - **Shape:** Circle, diameter = `chipHeight` (44pt) to meet Apple HIG minimum tap target
/// - **Icon:** 17pt medium weight SF Symbol (proportionally scaled with 44pt container)
/// - **Colors (inactive):** `textSecondary` foreground, `backgroundTertiary` background
/// - **Colors (active):** `accent` foreground, `accent.opacity(0.15)` background
/// - **Haptics:** `lightImpact` on tap (matches chip button haptics)
///
/// ## Accessibility
///
/// - **Label:** Provided by caller (e.g., "Background music: Focus" or "Settings")
/// - **Value:** "Expanded" or "Collapsed"
/// - **Hint:** "Double tap to expand/collapse options"
/// - **Traits:** `.isSelected` when expanded
///
/// ## Usage
///
/// ```swift
/// // Music button
/// DockCircularButton(
///     icon: adapter.musicCategory.iconName,
///     isExpanded: adapter.isMusicSelectorExpanded,
///     isActive: adapter.musicCategory.isActive,
///     accessibilityLabel: adapter.musicCategory.accessibilityLabel,
///     action: { toggleMusicSelector() }
/// )
///
/// // Gear button
/// DockCircularButton(
///     icon: "gearshape.fill",
///     isExpanded: adapter.isConfigSelectorExpanded,
///     isActive: isConfigActive,
///     accessibilityLabel: "Settings",
///     action: { toggleConfigSelector() }
/// )
/// ```
public struct DockCircularButton: View {

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics

    // MARK: - Properties

    /// SF Symbol name for the icon.
    public let icon: String

    /// Whether the associated menu is currently expanded.
    public let isExpanded: Bool

    /// Whether the button should show active/highlighted state.
    public let isActive: Bool

    /// Accessibility label for VoiceOver.
    public let accessibilityLabel: String

    /// Action to perform on tap.
    public let action: () -> Void

    // MARK: - Initialization

    public init(
        icon: String,
        isExpanded: Bool,
        isActive: Bool = false,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isExpanded = isExpanded
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    // MARK: - Body

    public var body: some View {
        Button {
            haptics.lightImpact()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: tokens.chipHeight, height: tokens.chipHeight)
                .background(
                    Circle()
                        .fill(backgroundColor)
                )
        }
        // MARK: Accessibility
        .accessibilityLabel(accessibilityLabel)
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

#Preview("Circular Button - States") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                DockCircularButton(
                    icon: "speaker.slash.fill",
                    isExpanded: false,
                    isActive: false,
                    accessibilityLabel: "Background music off",
                    action: {}
                )
                DockCircularButton(
                    icon: "gearshape.fill",
                    isExpanded: false,
                    isActive: false,
                    accessibilityLabel: "Settings",
                    action: {}
                )
            }
            HStack(spacing: 16) {
                DockCircularButton(
                    icon: "brain.head.profile",
                    isExpanded: false,
                    isActive: true,
                    accessibilityLabel: "Background music: Focus",
                    action: {}
                )
                DockCircularButton(
                    icon: "gearshape.fill",
                    isExpanded: false,
                    isActive: true,
                    accessibilityLabel: "Settings",
                    action: {}
                )
            }
        }
    }
}
