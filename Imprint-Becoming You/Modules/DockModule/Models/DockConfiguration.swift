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
/// The dock morphs between three distinct layouts based on the parent context.
/// This enum drives that decision, telling the dock which slots to show.
///
/// ## Visual Overview
///
/// ```
/// HOME:          [Mode ▼]                    [Binaural ▼]
///
/// SESSION:       [═══════════ Segments ═══════════════]
///                [◀]   [Center Content Slot]    [▶]
///                [Mode ▼]                    [Binaural ▼]
///
/// CONFIGURATION: [Mode ▼]     [🔁 3] [🔀]         [▶]
/// ```
///
/// ## Slot Visibility
///
/// | Slot               | Home | Session | Configuration |
/// |--------------------|------|---------|---------------|
/// | Progress Segments  | ✗    | ✓       | ✗             |
/// | Navigation Arrows  | ✗    | ✓       | ✗             |
/// | Center Content     | ✗    | ✓       | ✗             |
/// | Mode Selector      | ✓    | ✓       | ✓             |
/// | Binaural Selector  | ✓    | ✓       | ✗             |
/// | Loop Button        | ✗    | ✗       | ✓             |
/// | Shuffle Button     | ✗    | ✗       | ✓             |
/// | Play Button        | ✗    | ✗       | ✓             |
/// | Label Below        | ✗    | ✗       | ✓ (optional)  |
///
/// ## Usage
///
/// The adapter provides this value based on parent context:
///
/// ```swift
/// var configuration: DockConfiguration {
///     switch parentContext {
///     case .practice:
///         return isSessionActive ? .session : .home
///     case .favorites, .savedSessions, .resultsSummary:
///         return .configuration
///     }
/// }
/// ```
public enum DockConfiguration: Equatable, Sendable {
    
    /// Home/browse mode — compact with mode + binaural selectors only.
    ///
    /// Used when:
    /// - User is browsing affirmations
    /// - No active session in progress
    /// - PracticePageView in non-session state
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
    /// mode selector, binaural selector.
    ///
    /// Height: ~155pt
    case session
    
    /// Configuration mode — compact with playback controls.
    ///
    /// Used when:
    /// - FavoritesFullListView (label: "Practice X affirmations")
    /// - SavedSessionsFullListView (no label)
    /// - ResultsSummaryView (label: "Repeat Session")
    ///
    /// Shows: Mode selector, loop button, shuffle button, play button.
    /// Optionally shows label below dock.
    ///
    /// Height: ~68pt (plus label if present)
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
    
    /// Whether this configuration shows the binaural selector.
    ///
    /// The binaural selector appears in `.home` and `.session` but not
    /// in `.configuration` (which uses play controls instead).
    var showsBinauralSelector: Bool {
        switch self {
        case .home, .session:
            return true
        case .configuration:
            return false
        }
    }
    
    /// Whether this configuration shows playback controls.
    ///
    /// Playback controls (loop, shuffle, play) only appear in `.configuration`.
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
