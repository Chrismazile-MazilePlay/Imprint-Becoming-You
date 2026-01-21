//
//  DockNavigationButton.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockNavigationDirection

/// Direction for navigation buttons.
public enum DockNavigationDirection: Equatable, Sendable {
    case previous
    case next
    
    var iconName: String {
        switch self {
        case .previous: return "chevron.left"
        case .next: return "chevron.right"
        }
    }
    
    var label: String {
        switch self {
        case .previous: return "Previous"
        case .next: return "Next"
        }
    }
}

// MARK: - DockNavigationButton

/// A circular navigation button for moving between affirmations.
///
/// ## Usage
///
/// ```swift
/// DockNavigationButton(
///     direction: .previous,
///     isEnabled: adapter.canNavigatePrevious
/// ) {
///     adapter.navigatePrevious()
/// }
/// ```
public struct DockNavigationButton: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics
    
    // MARK: - Properties
    
    public let direction: DockNavigationDirection
    public let isEnabled: Bool
    public let action: () -> Void
    
    private let buttonSize: CGFloat = 44
    
    // MARK: - Initialization
    
    public init(
        direction: DockNavigationDirection,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) {
        self.direction = direction
        self.isEnabled = isEnabled
        self.action = action
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            haptics.lightImpact()
            action()
        } label: {
            Image(systemName: direction.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? tokens.textPrimary : tokens.textTertiary)
                .frame(width: buttonSize, height: buttonSize)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(direction.label)
    }
}

// MARK: - Previews

#Preview("Navigation Buttons") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 40) {
            DockNavigationButton(direction: .previous, isEnabled: true, action: {})
            DockNavigationButton(direction: .next, isEnabled: false, action: {})
        }
    }
}
