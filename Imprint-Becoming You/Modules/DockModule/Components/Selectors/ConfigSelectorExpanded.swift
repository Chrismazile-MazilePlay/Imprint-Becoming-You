//
//  ConfigSelectorExpanded.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/8/26.
//

import SwiftUI

// MARK: - ConfigSelectorExpanded

/// An expanded panel showing loop count and shuffle options.
///
/// The config menu uses the same visual shell as `ModeSelectorExpanded` and
/// `BinauralSelectorExpanded`: rounded rectangle with secondary background,
/// subtle border, and spring transitions.
///
/// ## Layout
///
/// ```
/// ┌──────────────────────────────────────────┐
/// │  ↺  Loop              (1)  (3)  (5)     │  ← label + 3 circular buttons
/// │ ──────────────────────────────────────── │  ← divider (only if shuffle visible)
/// │  🔀  Shuffle                    On       │  ← label + On/Off state text
/// └──────────────────────────────────────────┘
/// ```
///
/// ## Behavior
///
/// Unlike mode and binaural selectors, this menu does NOT auto-dismiss on
/// selection. It only closes via:
/// 1. Tap outside the view (host view's tap-to-dismiss)
/// 2. Second tap on gear button (toggle logic)
///
/// ## Usage
///
/// ```swift
/// ConfigSelectorExpanded(
///     loopCount: adapter.loopCount,
///     isShuffleEnabled: adapter.isShuffleEnabled,
///     showsShuffleOption: adapter.showsShuffleOption,
///     onSelectLoopCount: { adapter.selectLoopCount($0) },
///     onToggleShuffle: { adapter.toggleShuffle() }
/// )
/// ```
public struct ConfigSelectorExpanded: View {

    // MARK: - Environment

    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockHapticsProvider) private var haptics

    // MARK: - Properties

    /// The currently selected loop count (1, 3, or 5).
    public let loopCount: Int

    /// Whether shuffle is currently enabled.
    public let isShuffleEnabled: Bool

    /// Whether the shuffle row appears in the menu.
    ///
    /// `false` on the home screen (no predefined set to shuffle).
    /// `true` on Favorites, Saved Sessions, and Results views.
    public let showsShuffleOption: Bool

    /// Called when the user selects a loop count.
    public let onSelectLoopCount: (Int) -> Void

    /// Called when the user toggles shuffle.
    public let onToggleShuffle: () -> Void

    // MARK: - Constants

    private static let loopCounts = [1, 3, 5]

    // MARK: - Initialization

    public init(
        loopCount: Int,
        isShuffleEnabled: Bool,
        showsShuffleOption: Bool,
        onSelectLoopCount: @escaping (Int) -> Void,
        onToggleShuffle: @escaping () -> Void
    ) {
        self.loopCount = loopCount
        self.isShuffleEnabled = isShuffleEnabled
        self.showsShuffleOption = showsShuffleOption
        self.onSelectLoopCount = onSelectLoopCount
        self.onToggleShuffle = onToggleShuffle
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Row 1: Loop
            loopRow

            // Divider + Row 2: Shuffle (conditional)
            if showsShuffleOption {
                Divider()
                    .background(tokens.textTertiary.opacity(0.2))
                    .padding(.leading, 48)

                shuffleRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .fill(tokens.backgroundSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: tokens.cornerRadiusLarge)
                .stroke(tokens.textTertiary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Loop Row

    /// Row with repeat icon, "Loop" label, and three circular count buttons.
    private var loopRow: some View {
        HStack(spacing: tokens.spacingSM) {
            // Icon
            Image(systemName: "repeat")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(loopCount > 1 ? tokens.accent : tokens.textSecondary)
                .frame(width: 24)

            // Label
            VStack(alignment: .leading, spacing: 2) {
                Text("Loop")
                    .font(tokens.headline)
                    .foregroundStyle(loopCount > 1 ? tokens.accent : tokens.textPrimary)
                Text("Repeat affirmations")
                    .font(tokens.caption1)
                    .foregroundStyle(tokens.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Circular count buttons
            HStack(spacing: tokens.spacingXS) {
                ForEach(Self.loopCounts, id: \.self) { count in
                    loopCountButton(count)
                }
            }
        }
        .padding(.horizontal, tokens.spacingMD)
        .padding(.vertical, tokens.spacingSM)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loop count")
        .accessibilityValue(loopCount == 1 ? "Single play" : "Loop \(loopCount) times")
        .accessibilityHint("Select 1, 3, or 5 loops")
    }

    // MARK: - Loop Count Button

    /// A circular button for a specific loop count.
    ///
    /// Selected count uses accent highlight. Unselected uses tertiary background.
    /// Matches the visual style of `DockLoopButton`.
    private func loopCountButton(_ count: Int) -> some View {
        let isSelected = count == loopCount

        return Button {
            haptics.selectionFeedback()
            onSelectLoopCount(count)
        } label: {
            Group {
                if count == 1 {
                    Image(systemName: "repeat.1")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text("\(count)")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? tokens.accent : tokens.textSecondary)
            .frame(width: tokens.chipHeight, height: tokens.chipHeight)
            .background(
                Circle()
                    .fill(isSelected ? tokens.accent.opacity(0.15) : tokens.backgroundTertiary)
            )
            .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count == 1 ? "Single play" : "Loop \(count) times")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Shuffle Row

    /// Row with shuffle icon, "Shuffle" label, and On/Off state text.
    ///
    /// Tapping the entire row toggles shuffle.
    private var shuffleRow: some View {
        Button {
            haptics.selectionFeedback()
            onToggleShuffle()
        } label: {
            HStack(spacing: tokens.spacingSM) {
                // Icon
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isShuffleEnabled ? tokens.accent : tokens.textSecondary)
                    .frame(width: 24)

                // Label
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shuffle")
                        .font(tokens.headline)
                        .foregroundStyle(isShuffleEnabled ? tokens.accent : tokens.textPrimary)
                    Text("Randomize order")
                        .font(tokens.caption1)
                        .foregroundStyle(tokens.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // State text
                Text(isShuffleEnabled ? "On" : "Off")
                    .font(tokens.headline)
                    .foregroundStyle(isShuffleEnabled ? tokens.accent : tokens.textTertiary)
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.vertical, tokens.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shuffle")
        .accessibilityValue(isShuffleEnabled ? "On" : "Off")
        .accessibilityHint("Double tap to toggle shuffle")
        .accessibilityAddTraits(isShuffleEnabled ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Config Selector - Loop Only (Home)") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ConfigSelectorExpanded(
                loopCount: 1,
                isShuffleEnabled: false,
                showsShuffleOption: false,
                onSelectLoopCount: { _ in },
                onToggleShuffle: { }
            )
            .padding()
        }
    }
}

#Preview("Config Selector - Full (List View)") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ConfigSelectorExpanded(
                loopCount: 3,
                isShuffleEnabled: true,
                showsShuffleOption: true,
                onSelectLoopCount: { _ in },
                onToggleShuffle: { }
            )
            .padding()
        }
    }
}

#Preview("Config Selector - Shuffle Off") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ConfigSelectorExpanded(
                loopCount: 5,
                isShuffleEnabled: false,
                showsShuffleOption: true,
                onSelectLoopCount: { _ in },
                onToggleShuffle: { }
            )
            .padding()
        }
    }
}
