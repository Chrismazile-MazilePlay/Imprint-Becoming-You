//
//  DockPlayButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockPlayButton

/// A circular play button for starting practice sessions.
///
/// ## Usage
///
/// ```swift
/// DockPlayButton(isEnabled: adapter.isPlayEnabled) {
///     adapter.play()
/// }
/// ```
public struct DockPlayButton: View {
    
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
            haptics.mediumImpact()
            action()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? tokens.textPrimary : tokens.textTertiary)
                .frame(width: tokens.playButtonSize, height: tokens.playButtonSize)
                .background(
                    Circle()
                        .fill(isEnabled ? tokens.accent : tokens.backgroundTertiary)
                )
        }
        .disabled(!isEnabled)
        .accessibilityLabel("Play")
        .accessibilityHint(isEnabled ? "Start practice session" : "No items to practice")
    }
}

// MARK: - Previews

#Preview("Play Button") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 24) {
            DockPlayButton(isEnabled: true, action: {})
            DockPlayButton(isEnabled: false, action: {})
        }
    }
}
