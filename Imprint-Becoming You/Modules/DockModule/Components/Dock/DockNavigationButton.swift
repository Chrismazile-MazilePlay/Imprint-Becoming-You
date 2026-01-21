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
/// Features a circular background with a prominent chevron icon.
/// The button is sized to provide a comfortable tap target while
/// maintaining visual balance with other dock elements.
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
    
    // MARK: - Constants
    
    /// Size of the circular button background
    static let buttonSize: CGFloat = 48
    
    /// Size of the chevron icon
    private let iconSize: CGFloat = 20
    
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
            Circle()
                .fill(tokens.backgroundTertiary.opacity(isEnabled ? 1.0 : 0.5))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .overlay {
                    Image(systemName: direction.iconName)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(isEnabled ? tokens.textPrimary : tokens.textTertiary)
                }
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
            DockNavigationButton(direction: .next, isEnabled: true, action: {})
        }
    }
}

#Preview("Navigation Buttons - Disabled") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 40) {
            DockNavigationButton(direction: .previous, isEnabled: false, action: {})
            DockNavigationButton(direction: .next, isEnabled: false, action: {})
        }
    }
}
