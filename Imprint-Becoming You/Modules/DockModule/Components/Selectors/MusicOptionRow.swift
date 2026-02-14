//
//  MusicOptionRow.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import SwiftUI

// MARK: - MusicOptionRow

/// A single option row in the background music selector menu.
///
/// ## Usage
///
/// ```swift
/// MusicOptionRow(
///     category: .focus,
///     isSelected: currentCategory == .focus
/// ) {
///     selectCategory(.focus)
/// }
/// ```
public struct MusicOptionRow: View {

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics

    // MARK: - Properties

    public let category: DockMusicCategory
    public let isSelected: Bool
    public let action: () -> Void

    // MARK: - Initialization

    public init(
        category: DockMusicCategory,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.category = category
        self.isSelected = isSelected
        self.action = action
    }

    // MARK: - Body

    public var body: some View {
        Button {
            haptics.selectionFeedback()
            action()
        } label: {
            HStack(spacing: tokens.spacingSM) {
                Image(systemName: category.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(tokens.headline)
                        .foregroundStyle(isSelected ? tokens.accent : tokens.textPrimary)

                    Text(category.description)
                        .font(tokens.caption1)
                        .foregroundStyle(tokens.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                }
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.vertical, tokens.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Icon Color

    private var iconColor: Color {
        if isSelected { return tokens.accent }

        switch category {
        case .off:        return tokens.textTertiary
        case .coffee:     return Color.brown.opacity(0.8)
        case .driving:    return tokens.accentSecondary
        case .exercise:   return Color.orange.opacity(0.8)
        case .focus:      return tokens.accentSecondary
        case .meditation: return Color.purple.opacity(0.8)
        case .morning:    return Color.yellow.opacity(0.8)
        case .nature:     return tokens.success
        case .piano:      return tokens.textSecondary
        case .sleep:      return Color.purple.opacity(0.8)
        }
    }
}

// MARK: - Previews

#Preview("Music Option Row") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 0) {
            MusicOptionRow(category: .focus, isSelected: true, action: {})
            Divider().background(Color.white.opacity(0.1))
            MusicOptionRow(category: .nature, isSelected: false, action: {})
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
        .padding()
    }
}
