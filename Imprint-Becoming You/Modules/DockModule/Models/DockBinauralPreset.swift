//
//  DockBinauralPreset.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import Foundation

// MARK: - DockBinauralPreset

/// Binaural beat preset representation for the dock.
///
/// This is the dock module's own type for binaural presets. It contains only
/// display properties — no audio-specific logic. The host app's adapter maps
/// between its internal preset type (e.g., `BinauralPreset`) and this type.
///
/// ## Raw Values
///
/// Raw values match the host app's `BinauralPreset` for easy mapping:
///
/// ```swift
/// // In host adapter
/// var binauralPreset: DockBinauralPreset {
///     DockBinauralPreset(rawValue: preset.rawValue) ?? .off
/// }
/// ```
///
/// ## Display Properties
///
/// | Preset  | Icon                    | Display Name |
/// |---------|-------------------------|--------------|
/// | `off`   | speaker.slash.fill      | Off          |
/// | `focus` | brain.head.profile      | Focus        |
/// | `relax` | leaf.fill               | Relax        |
/// | `sleep` | moon.stars.fill         | Sleep        |
///
/// ## Usage in Dock
///
/// The dock uses this type to display binaural information in buttons and selectors:
///
/// ```swift
/// DockBinauralButton(preset: adapter.binauralPreset, isExpanded: binding) {
///     adapter.selectBinaural(preset)
/// }
/// ```
public enum DockBinauralPreset: String, CaseIterable, Identifiable, Equatable, Sendable {
    
    /// No binaural beats.
    case off = "off"
    
    /// Beta waves (14 Hz) for concentration.
    case focus = "focus"
    
    /// Alpha waves (10 Hz) for calm.
    case relax = "relax"
    
    /// Theta waves (6 Hz) for rest.
    case sleep = "sleep"
    
    // MARK: - Identifiable
    
    public var id: String { rawValue }
    
    // MARK: - Display Properties
    
    /// Human-readable name for UI display.
    ///
    /// Used in binaural selector buttons and expanded menu options.
    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .focus:
            return "Focus"
        case .relax:
            return "Relax"
        case .sleep:
            return "Sleep"
        }
    }
    
    /// SF Symbol icon name for this preset.
    ///
    /// Used in binaural selector buttons and expanded menu options.
    public var iconName: String {
        switch self {
        case .off:
            return "speaker.slash.fill"
        case .focus:
            return "brain.head.profile"
        case .relax:
            return "leaf.fill"
        case .sleep:
            return "moon.stars.fill"
        }
    }
    
    /// Detailed description for preset selector menu.
    ///
    /// Provides additional context about the brain wave effect.
    public var description: String {
        switch self {
        case .off:
            return "No binaural beats"
        case .focus:
            return "Beta waves (14 Hz) for concentration"
        case .relax:
            return "Alpha waves (10 Hz) for calm"
        case .sleep:
            return "Theta waves (6 Hz) for rest"
        }
    }
    
    /// Whether this preset produces audio.
    ///
    /// Returns `true` for all presets except `.off`.
    public var isActive: Bool {
        self != .off
    }
}

// MARK: - Accessibility

public extension DockBinauralPreset {
    
    /// Accessibility label for the preset button.
    ///
    /// Provides a clear description for VoiceOver users.
    var accessibilityLabel: String {
        isActive ? "Binaural beats: \(displayName)" : "Binaural beats off"
    }
    
    /// Accessibility hint for the preset button.
    ///
    /// Describes the effect of the preset.
    var accessibilityHint: String {
        description
    }
}
