//
//  DockMusicCategory.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import Foundation

// MARK: - DockMusicCategory

/// Background music category representation for the dock.
///
/// This is the dock module's own type for music categories. It contains only
/// display properties — no audio-specific logic. The host app's adapter maps
/// between its internal type (`MusicCategory?`) and this type.
///
/// ## Module Boundary
///
/// The domain layer uses `MusicCategory?` where `nil` = Off.
/// This dock type includes an explicit `.off` case for the selector UI,
/// making the "no music" option selectable alongside music categories.
///
/// ## Raw Values
///
/// Raw values match the host app's `MusicCategory` for easy mapping:
///
/// ```swift
/// // In host adapter
/// var musicCategory: DockMusicCategory {
///     guard let category = store.backgroundMusicCategory else { return .off }
///     return DockMusicCategory(rawValue: category.rawValue) ?? .off
/// }
/// ```
///
/// ## Display Properties
///
/// | Category     | Icon                      | Display Name     |
/// |--------------|---------------------------|------------------|
/// | `off`        | speaker.slash.fill        | Off              |
/// | `coffee`     | cup.and.saucer.fill       | Coffee & Cozy    |
/// | `driving`    | car.fill                  | Driving          |
/// | `exercise`   | figure.run                | Exercise         |
/// | `focus`      | brain.head.profile        | Deep Focus       |
/// | `meditation` | figure.mind.and.body      | Meditation       |
/// | `morning`    | sun.horizon.fill          | Morning          |
/// | `nature`     | leaf.fill                 | Nature           |
/// | `piano`      | pianokeys                 | Gentle Piano     |
/// | `sleep`      | moon.stars.fill           | Sleep            |
///
/// ## Usage in Dock
///
/// ```swift
/// DockCircularButton(
///     icon: adapter.musicCategory.iconName,
///     isExpanded: adapter.expandedSelector == .music,
///     isActive: adapter.musicCategory.isActive,
///     accessibilityLabel: adapter.musicCategory.accessibilityLabel
/// ) {
///     toggleSelector(.music)
/// }
/// ```
public enum DockMusicCategory: String, CaseIterable, Identifiable, Equatable, Sendable {

    /// No background music.
    case off = "off"

    /// Lo-fi / cozy coffee shop vibes.
    case coffee = "coffee"

    /// Retrowave / driving energy.
    case driving = "driving"

    /// Gym / workout motivation.
    case exercise = "exercise"

    /// Ambient / minimal focus music.
    case focus = "focus"

    /// Calm stillness for meditation.
    case meditation = "meditation"

    /// Uplifting morning energy.
    case morning = "morning"

    /// Nature sounds — ocean, forest, birds.
    case nature = "nature"

    /// Gentle inspirational piano.
    case piano = "piano"

    /// Healing drones and shimmer for sleep.
    case sleep = "sleep"

    // MARK: - Identifiable

    public var id: String { rawValue }

    // MARK: - Display Properties

    /// Human-readable name for UI display.
    ///
    /// Used in music selector buttons and expanded menu options.
    public var displayName: String {
        switch self {
        case .off:        return "Off"
        case .coffee:     return "Coffee & Cozy"
        case .driving:    return "Driving"
        case .exercise:   return "Exercise"
        case .focus:      return "Deep Focus"
        case .meditation: return "Meditation"
        case .morning:    return "Morning"
        case .nature:     return "Nature"
        case .piano:      return "Gentle Piano"
        case .sleep:      return "Sleep"
        }
    }

    /// SF Symbol icon name for this category.
    ///
    /// Used in music selector buttons and expanded menu options.
    public var iconName: String {
        switch self {
        case .off:        return "speaker.slash.fill"
        case .coffee:     return "cup.and.saucer.fill"
        case .driving:    return "car.fill"
        case .exercise:   return "figure.run"
        case .focus:      return "brain.head.profile"
        case .meditation: return "figure.mind.and.body"
        case .morning:    return "sun.horizon.fill"
        case .nature:     return "leaf.fill"
        case .piano:      return "pianokeys"
        case .sleep:      return "moon.stars.fill"
        }
    }

    /// Brief description for the selector menu.
    ///
    /// Provides additional context about the mood or style.
    public var description: String {
        switch self {
        case .off:        return "No background music"
        case .coffee:     return "Lo-fi chill & cozy vibes"
        case .driving:    return "Retrowave & cruising energy"
        case .exercise:   return "Gym & workout motivation"
        case .focus:      return "Ambient & minimal focus"
        case .meditation: return "Calm stillness"
        case .morning:    return "Uplifting morning energy"
        case .nature:     return "Ocean, forest & birds"
        case .piano:      return "Gentle inspirational piano"
        case .sleep:      return "Healing drones & shimmer"
        }
    }

    /// Whether this category produces audio.
    ///
    /// Returns `true` for all categories except `.off`.
    public var isActive: Bool {
        self != .off
    }
}

// MARK: - Accessibility

public extension DockMusicCategory {

    /// Accessibility label for the music button.
    ///
    /// Provides a clear description for VoiceOver users.
    var accessibilityLabel: String {
        isActive ? "Background music: \(displayName)" : "Background music off"
    }

    /// Accessibility hint for the music button.
    ///
    /// Describes the category style.
    var accessibilityHint: String {
        description
    }
}
