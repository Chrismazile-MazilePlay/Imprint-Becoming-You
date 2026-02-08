//
//  DockConfiguration.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import Foundation

// MARK: - DockConfiguration

/// Configuration determining which dock layout to render.
///
/// The dock uses a unified 3-button row across all compact layouts:
/// **Binaural (left) — Mode (center) — Settings/Gear (right)**
///
/// ## Visual Overview
///
/// ```
/// HOME/COMPACT:  [Binaural ▼]    [Mode ▼]    [⚙ Settings ▼]
///
/// SESSION:       [═══════════ Segments ═══════════════]
///                [◀]   [Center Content Slot]    [▶]
///                [Binaural ▼]    [Mode ▼]    [⚙ Settings ▼]
/// ```
///
/// ## Slot Visibility
///
/// | Slot               | Home | Session |
/// |--------------------|------|---------|
/// | Progress Segments  | ✗    | ✓       |
/// | Navigation Arrows  | ✗    | ✓       |
/// | Center Content     | ✗    | ✓       |
/// | Mode Selector      | ✓    | ✓       |
/// | Binaural Selector  | ✓    | ✓       |
/// | Config Selector    | ✓    | ✓*      |
///
/// *Config selector shows error bar during session instead of opening menu.
///
/// ## Usage
///
/// The adapter provides this value based on parent context:
///
/// ```swift
/// var configuration: DockConfiguration {
///     isSessionActive ? .session : .home
/// }
/// ```
public enum DockConfiguration: Equatable, Sendable {

    /// Compact mode — unified 3-button row with binaural, mode, and config selectors.
    ///
    /// Used when:
    /// - User is browsing affirmations (home)
    /// - Favorites, Saved Sessions, Results views
    /// - No active session in progress
    ///
    /// Height: ~68pt
    case home

    /// Active session mode — expanded with all session controls.
    ///
    /// Used when:
    /// - User is in an active practice session
    /// - PracticePageView during active session
    ///
    /// Shows: Progress segments, navigation arrows, center content slot,
    /// plus the unified 3-button row at the bottom.
    ///
    /// Height: ~155pt
    case session

    /// Configuration mode — compact with playback controls.
    ///
    /// - Important: Deprecated. Use `.home` instead. All compact layouts now use
    ///   the unified 3-button row. Play button has moved to `DockFloatingPlayButton`.
    @available(*, deprecated, message: "Use .home instead. Configuration mode is replaced by the unified dock layout.")
    case configuration
}

// MARK: - Convenience Properties

public extension DockConfiguration {
    
    /// Whether this configuration uses the compact layout.
    ///
    /// Both `.home` and `.configuration` are compact (~68pt).
    /// Only `.session` is expanded (~155pt).
    var isCompact: Bool {
        switch self {
        case .home, .configuration:
            return true
        case .session:
            return false
        }
    }

    /// Whether this configuration shows the binaural selector button.
    ///
    /// Always `true` — the unified 3-button row includes binaural on all layouts.
    var showsBinauralSelector: Bool {
        true
    }

    /// Whether tapping the config selector opens the settings menu.
    ///
    /// Returns `true` for `.home` and `.configuration` (gear opens menu).
    /// Returns `false` for `.session` (gear shows error bar instead).
    var showsConfigSelector: Bool {
        switch self {
        case .home, .configuration:
            return true
        case .session:
            return false
        }
    }

    /// Whether this configuration shows inline playback controls (loop, shuffle, play).
    ///
    /// Always `false` — playback controls have moved to the config selector menu
    /// and `DockFloatingPlayButton`. Retained for backward compatibility during migration.
    @available(*, deprecated, message: "Playback controls moved to config selector menu and DockFloatingPlayButton.")
    var showsPlaybackControls: Bool {
        self == .configuration
    }

    /// Whether this configuration shows progress segments.
    ///
    /// Progress segments only appear in `.session`.
    var showsProgressSegments: Bool {
        self == .session
    }

    /// Whether this configuration shows navigation arrows.
    ///
    /// Navigation arrows (previous/next) only appear in `.session`.
    var showsNavigationArrows: Bool {
        self == .session
    }

    /// Whether this configuration shows the center content slot.
    ///
    /// The center content slot (waveform/score) only appears in `.session`.
    var showsCenterContent: Bool {
        self == .session
    }
}
