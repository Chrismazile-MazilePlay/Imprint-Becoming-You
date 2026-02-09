//
//  DockExpandedSelector.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/8/26.
//

import Foundation

// MARK: - DockExpandedSelector

/// Represents which selector menu is currently expanded in the dock.
///
/// Replaces three separate boolean properties (`isModeSelectorExpanded`,
/// `isBinauralSelectorExpanded`, `isConfigSelectorExpanded`) with a single
/// optional enum. This makes it structurally impossible to have multiple
/// selectors open simultaneously — enforced by the type system rather than
/// close-before-open logic.
///
/// ## Usage
///
/// ```swift
/// // Open a selector
/// adapter.expandedSelector = .mode
///
/// // Close all selectors
/// adapter.expandedSelector = nil
///
/// // Toggle a selector
/// adapter.expandedSelector = (adapter.expandedSelector == .mode) ? nil : .mode
///
/// // Check if a specific selector is open
/// if adapter.expandedSelector == .binaural { ... }
///
/// // Check if any selector is open
/// if adapter.expandedSelector != nil { ... }
/// ```
public enum DockExpandedSelector: Equatable, Sendable {
    /// The mode selector menu (e.g., Read Aloud, Read & Speak).
    case mode

    /// The binaural preset selector menu (e.g., Focus, Relax, Sleep).
    case binaural

    /// The config/settings selector menu (e.g., Loop Count, Shuffle).
    case config
}
