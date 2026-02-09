//
//  DockLoopButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockLoopButton

/// A circular button for cycling through loop count options.
///
/// Shows `repeat.1` icon for count of 1, plain number for 3 and 5.
///
/// ## Visual Design
/// ```
/// Count = 1:      Count = 3:      Count = 5:
/// ┌────────┐     ┌────────┐     ┌────────┐
/// │  ↺ 1   │     │   3    │     │   5    │
/// └────────┘     └────────┘     └────────┘
/// ```
///
/// ## Accessibility
///
/// - **Label:** Descriptive based on count ("Single play", "Loop twice", etc.)
/// - **Hint:** Explains cycling behavior
/// - **Value:** Current loop state
///
/// ## Usage
///
/// ```swift
/// DockLoopButton(count: adapter.loopCount) {
///     adapter.cycleLoopCount()
/// }
/// ```
public struct DockLoopButton: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let count: Int
    public let action: () -> Void
    
    private var isActive: Bool { count > 1 }
    
    // MARK: - Accessibility
    
    /// Descriptive label based on loop count.
    private var accessibilityLabelText: String {
        switch count {
        case 1: return "Single play"
        case 2: return "Loop twice"
        case 3: return "Loop three times"
        case 5: return "Loop five times"
        default: return "Loop \(count) times"
        }
    }
    
    /// Value describing current state.
    private var accessibilityValueText: String {
        count > 1 ? "Looping \(count) times" : "Not looping"
    }
    
    // MARK: - Initialization
    
    public init(count: Int, action: @escaping () -> Void) {
        self.count = count
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.selectionFeedback()
            action()
        } label: {
            Group {
                if count == 1 {
                    // Default: show repeat.1 icon
                    Image(systemName: "repeat.1")
                        .font(.system(size: 17, weight: .semibold))
                } else {
                    // Active (3 or 5): show just the number
                    Text("\(count)")
                        .font(.system(size: 19, weight: .bold))
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(width: tokens.chipHeight, height: tokens.chipHeight)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .contentTransition(.identity)
        }
        // MARK: Accessibility
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Double tap to cycle through loop options: 1, 3, or 5 times")
        .accessibilityValue(accessibilityValueText)
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

#Preview("Loop Button - All States") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 12) {
            DockLoopButton(count: 1, action: {})
            DockLoopButton(count: 3, action: {})
            DockLoopButton(count: 5, action: {})
        }
    }
}

#Preview("Loop Button - Size Comparison with Shuffle") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 12) {
            DockLoopButton(count: 3, action: {})
            DockShuffleButton(isEnabled: true, action: {})
        }
    }
}
