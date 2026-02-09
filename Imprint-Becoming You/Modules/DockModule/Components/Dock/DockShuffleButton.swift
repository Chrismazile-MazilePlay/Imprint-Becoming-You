//
//  DockShuffleButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockShuffleButton

/// A chip-style toggle button for enabling/disabling shuffle.
///
/// ## Accessibility
///
/// - **Label:** "Shuffle enabled" or "Shuffle disabled"
/// - **Hint:** Describes toggle action
/// - **Traits:** `.isSelected` when enabled
///
/// ## Usage
///
/// ```swift
/// DockShuffleButton(isEnabled: adapter.isShuffleEnabled) {
///     adapter.toggleShuffle()
/// }
/// ```
public struct DockShuffleButton: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let isEnabled: Bool
    public let action: () -> Void
    
    // MARK: - Initialization
    
    public init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.selectionFeedback()
            action()
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? tokens.accent : tokens.textSecondary)
                .frame(width: tokens.chipHeight, height: tokens.chipHeight)
                .background(
                    Capsule()
                        .fill(isEnabled ? tokens.accent.opacity(0.15) : tokens.backgroundTertiary)
                )
        }
        // MARK: Accessibility
        .accessibilityLabel(isEnabled ? "Shuffle enabled" : "Shuffle disabled")
        .accessibilityHint("Double tap to toggle shuffle mode")
        .accessibilityAddTraits(isEnabled ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Shuffle Button") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 12) {
            DockShuffleButton(isEnabled: false, action: {})
            DockShuffleButton(isEnabled: true, action: {})
        }
    }
}
