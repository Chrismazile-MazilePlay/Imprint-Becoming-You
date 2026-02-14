//
//  MusicSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import SwiftUI

// MARK: - MusicSelectorExpanded

/// An expanded panel showing all background music categories.
///
/// Displays 10 items (Off + 9 music categories) in a scrollable list.
/// Each row shows an icon, name, description, and checkmark for the selected item.
///
/// ## Usage
///
/// ```swift
/// MusicSelectorExpanded(
///     selectedCategory: adapter.musicCategory
/// ) { category in
///     adapter.selectMusic(category)
/// }
/// ```
public struct MusicSelectorExpanded: View {

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens

    // MARK: - Properties

    public let selectedCategory: DockMusicCategory
    public let onSelect: (DockMusicCategory) -> Void

    // MARK: - Initialization

    public init(
        selectedCategory: DockMusicCategory,
        onSelect: @escaping (DockMusicCategory) -> Void
    ) {
        self.selectedCategory = selectedCategory
        self.onSelect = onSelect
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(DockMusicCategory.allCases.enumerated()), id: \.element.id) { index, category in
                    MusicOptionRow(
                        category: category,
                        isSelected: category == selectedCategory
                    ) {
                        onSelect(category)
                    }

                    if index < DockMusicCategory.allCases.count - 1 {
                        Divider()
                            .background(tokens.textTertiary.opacity(0.2))
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .frame(maxHeight: 380)
        .background(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .fill(tokens.backgroundSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .stroke(tokens.textTertiary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge))
    }
}

// MARK: - Previews

#Preview("Music Selector Expanded") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MusicSelectorExpanded(selectedCategory: .focus) { _ in }
                .padding()
        }
    }
}
