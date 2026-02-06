//
//  DockErrorBar.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/4/26.
//

import SwiftUI

// MARK: - DockErrorBar

/// An expandable error bar displayed above the dock, matching the visual style
/// of `ModeSelectorExpanded` and `BinauralSelectorExpanded`.
///
/// ## Behavior
/// - Appears with the same expand/collapse transition as other dock menus
/// - Auto-dismisses after 3 seconds
/// - Immediately dismissed by mode or binaural button taps
///
/// ## Visual Design
/// Matches the dock menu panel style — rounded rectangle with the same
/// background opacity and border treatment. Text is centered and uses
/// the dock's secondary text color for a non-alarming, informational tone.
///
/// ## Usage
///
/// Rendered by `AdaptiveDockContainer` in the expanded menus area when
/// `adapter.isErrorBarVisible` is `true`.
///
/// ```swift
/// DockErrorBar(message: adapter.errorBarMessage)
/// ```
public struct DockErrorBar: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    /// The error message to display.
    public let message: String
    
    // MARK: - Initialization
    
    public init(message: String) {
        self.message = message
    }
    
    // MARK: - Body
    
    public var body: some View {
        Text(message)
            .font(tokens.caption1.weight(.medium))
            .foregroundStyle(tokens.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, tokens.spacingLG)
            .padding(.vertical, tokens.spacingMD)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                    .fill(tokens.backgroundSecondary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                    .stroke(tokens.textTertiary.opacity(0.1), lineWidth: 1)
            )
            .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - Previews

#Preview("Error Bar") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            DockErrorBar(message: "The microphone is being used by another app")
                .padding(.horizontal)
            Spacer()
        }
    }
}
