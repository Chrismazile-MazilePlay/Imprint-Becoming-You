//
//  MusicTransportControls.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/16/26.
//

import SwiftUI

// MARK: - MusicTransportControls

/// Transport control buttons for background music navigation and playback mode.
///
/// Displays a horizontal row of four buttons:
/// - **Skip backward** (`backward.fill`) — previous track
/// - **Skip forward** (`forward.fill`) — next track
/// - **Repeat** (`repeat`) — single-track loop mode
/// - **Shuffle** (`shuffle`) — random track mode
///
/// Only one of repeat/shuffle can be active at a time. Tapping a mode
/// button selects that mode; tapping the already-active mode does nothing.
///
/// ## Haptics
/// - Skip buttons use `lightImpact()` — suited for rapid taps.
/// - Mode buttons use `selectionFeedback()` — only fires when mode actually changes.
///
/// ## Usage
///
/// ```swift
/// MusicTransportControls(
///     playbackMode: .repeatTrack,
///     onSkipBackward: { adapter.skipMusicBackward() },
///     onSkipForward: { adapter.skipMusicForward() },
///     onSelectPlaybackMode: { mode in adapter.selectMusicPlaybackMode(mode) }
/// )
/// ```
public struct MusicTransportControls: View {

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics

    // MARK: - Properties

    /// The current playback mode (determines which mode button is highlighted).
    public let playbackMode: DockMusicPlaybackMode

    /// Called when the user taps the skip-backward button.
    public let onSkipBackward: () -> Void

    /// Called when the user taps the skip-forward button.
    public let onSkipForward: () -> Void

    /// Called when the user taps the repeat or shuffle button to select that mode.
    public let onSelectPlaybackMode: (DockMusicPlaybackMode) -> Void

    // MARK: - Initialization

    public init(
        playbackMode: DockMusicPlaybackMode,
        onSkipBackward: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSelectPlaybackMode: @escaping (DockMusicPlaybackMode) -> Void
    ) {
        self.playbackMode = playbackMode
        self.onSkipBackward = onSkipBackward
        self.onSkipForward = onSkipForward
        self.onSelectPlaybackMode = onSelectPlaybackMode
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: tokens.spacingLG) {
            // Skip backward
            transportButton(
                icon: "backward.fill",
                label: "Previous track"
            ) {
                haptics.lightImpact()
                onSkipBackward()
            }

            // Skip forward
            transportButton(
                icon: "forward.fill",
                label: "Next track"
            ) {
                haptics.lightImpact()
                onSkipForward()
            }

            // Repeat
            modeButton(
                icon: "repeat",
                label: "Repeat",
                mode: .repeatTrack
            )

            // Shuffle
            modeButton(
                icon: "shuffle",
                label: "Shuffle",
                mode: .shuffle
            )
        }
    }

    // MARK: - Private Views

    /// A transport button (skip forward/backward) with no state highlight.
    private func transportButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tokens.textSecondary)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A playback mode selection button with active/inactive state.
    ///
    /// Tapping the already-active mode does nothing. Tapping the inactive
    /// mode selects it and fires a haptic.
    private func modeButton(
        icon: String,
        label: String,
        mode: DockMusicPlaybackMode
    ) -> some View {
        let isActive = playbackMode == mode
        return Button {
            guard !isActive else { return }
            haptics.selectionFeedback()
            onSelectPlaybackMode(mode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isActive ? tokens.accent : tokens.textSecondary)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
    }
}

// MARK: - Previews

#Preview("Transport Controls - Repeat") {
    ZStack {
        Color.black.ignoresSafeArea()
        MusicTransportControls(
            playbackMode: .repeatTrack,
            onSkipBackward: {},
            onSkipForward: {},
            onSelectPlaybackMode: { _ in }
        )
    }
}

#Preview("Transport Controls - Shuffle") {
    ZStack {
        Color.black.ignoresSafeArea()
        MusicTransportControls(
            playbackMode: .shuffle,
            onSkipBackward: {},
            onSkipForward: {},
            onSelectPlaybackMode: { _ in }
        )
    }
}
