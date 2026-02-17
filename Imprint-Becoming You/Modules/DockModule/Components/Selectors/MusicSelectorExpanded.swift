//
//  MusicSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import SwiftUI

// MARK: - MusicSelectorExpanded

/// An expanded panel showing all background music categories with
/// integrated volume and transport controls.
///
/// Displays 10 items (Off + 9 music categories) in a scrollable list.
/// When a non-Off category is selected, the controls section (volume
/// slider + transport buttons) animates into view below the category list.
///
/// ## Non-Dismissing Behavior
///
/// Unlike mode selectors, this menu does NOT auto-dismiss on selection.
/// It stays open so users can adjust volume and transport controls.
/// It only closes via:
/// 1. Tap outside the view (host view's tap-to-dismiss)
/// 2. Second tap on the music button (toggle logic)
///
/// ## Usage
///
/// ```swift
/// MusicSelectorExpanded(
///     selectedCategory: adapter.musicCategory,
///     playbackMode: adapter.musicPlaybackMode,
///     volume: adapter.musicVolume,
///     onSelect: { category in adapter.selectMusic(category) },
///     onVolumeChange: { volume in adapter.setMusicVolume(volume) },
///     onSkipBackward: { adapter.skipMusicBackward() },
///     onSkipForward: { adapter.skipMusicForward() },
///     onSelectPlaybackMode: { mode in adapter.selectMusicPlaybackMode(mode) }
/// )
/// ```
public struct MusicSelectorExpanded: View {

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens

    // MARK: - Properties

    /// The currently selected music category.
    public let selectedCategory: DockMusicCategory

    /// The current playback mode (repeat or shuffle).
    public let playbackMode: DockMusicPlaybackMode

    /// The current volume level (0.0–1.0).
    public let volume: Float

    /// Called when the user taps a category row.
    public let onSelect: (DockMusicCategory) -> Void

    /// Called continuously as the user adjusts the volume slider.
    public let onVolumeChange: (Float) -> Void

    /// Called when the user taps the skip-backward button.
    public let onSkipBackward: () -> Void

    /// Called when the user taps the skip-forward button.
    public let onSkipForward: () -> Void

    /// Called when the user taps the repeat or shuffle button to select that mode.
    public let onSelectPlaybackMode: (DockMusicPlaybackMode) -> Void

    // MARK: - Initialization

    public init(
        selectedCategory: DockMusicCategory,
        playbackMode: DockMusicPlaybackMode,
        volume: Float,
        onSelect: @escaping (DockMusicCategory) -> Void,
        onVolumeChange: @escaping (Float) -> Void,
        onSkipBackward: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSelectPlaybackMode: @escaping (DockMusicPlaybackMode) -> Void
    ) {
        self.selectedCategory = selectedCategory
        self.playbackMode = playbackMode
        self.volume = volume
        self.onSelect = onSelect
        self.onVolumeChange = onVolumeChange
        self.onSkipBackward = onSkipBackward
        self.onSkipForward = onSkipForward
        self.onSelectPlaybackMode = onSelectPlaybackMode
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Category list
            categoryList

            // Controls section — always visible below category list
            Divider()
                .background(tokens.textTertiary.opacity(0.2))

            controlsSection
        }
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

    // MARK: - Category List

    /// Scrollable list of all music categories.
    private var categoryList: some View {
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
        .frame(height: 275)
    }

    // MARK: - Controls Section

    /// Volume slider and transport controls.
    ///
    /// Rendered below the category list when a non-Off category is selected.
    /// Uses `showsBackground: false` on the volume slider since the parent
    /// `MusicSelectorExpanded` provides the shared background.
    private var controlsSection: some View {
        VStack(spacing: tokens.spacingSM) {
            MusicVolumeSlider(
                volume: volume,
                showsBackground: false,
                onVolumeChange: onVolumeChange
            )

            MusicTransportControls(
                playbackMode: playbackMode,
                onSkipBackward: onSkipBackward,
                onSkipForward: onSkipForward,
                onSelectPlaybackMode: onSelectPlaybackMode
            )
        }
        .padding(.horizontal, tokens.spacingSM)
        .padding(.vertical, tokens.spacingSM)
    }
}

// MARK: - Previews

#Preview("Music Selector - No Selection") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MusicSelectorExpanded(
                selectedCategory: .off,
                playbackMode: .repeatTrack,
                volume: 0.15,
                onSelect: { _ in },
                onVolumeChange: { _ in },
                onSkipBackward: {},
                onSkipForward: {},
                onSelectPlaybackMode: { _ in }
            )
            .padding()
        }
    }
}

#Preview("Music Selector - Focus Selected") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MusicSelectorExpanded(
                selectedCategory: .focus,
                playbackMode: .repeatTrack,
                volume: 0.15,
                onSelect: { _ in },
                onVolumeChange: { _ in },
                onSkipBackward: {},
                onSkipForward: {},
                onSelectPlaybackMode: { _ in }
            )
            .padding()
        }
    }
}

#Preview("Music Selector - Shuffle Mode") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            MusicSelectorExpanded(
                selectedCategory: .nature,
                playbackMode: .shuffle,
                volume: 0.5,
                onSelect: { _ in },
                onVolumeChange: { _ in },
                onSkipBackward: {},
                onSkipForward: {},
                onSelectPlaybackMode: { _ in }
            )
            .padding()
        }
    }
}
