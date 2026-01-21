//
//  DockMode.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import Foundation

// MARK: - DockMode

/// Mode representation for the dock.
///
/// This is the dock module's own type for practice modes. It contains only
/// display properties — no app-specific logic. The host app's adapter maps
/// between its internal mode type (e.g., `SessionMode`) and this type.
///
/// ## Raw Values
///
/// Raw values match the host app's `SessionMode` for easy mapping:
///
/// ```swift
/// // In host adapter
/// var currentMode: DockMode {
///     DockMode(rawValue: sessionMode.rawValue) ?? .readOnly
/// }
/// ```
///
/// ## Display Properties
///
/// | Mode          | Icon                         | Display Name    |
/// |---------------|------------------------------|-----------------|
/// | `readOnly`    | book.fill                    | Read Only       |
/// | `readAloud`   | speaker.wave.2.fill          | Read Aloud      |
/// | `readAndSpeak`| mic.and.signal.meter.fill    | Read & Speak    |
/// | `speakOnly`   | mic.fill                     | Speak Only      |
///
/// ## Usage in Dock
///
/// The dock uses this type to display mode information in buttons and selectors:
///
/// ```swift
/// DockModeButton(mode: adapter.currentMode, isExpanded: binding) {
///     adapter.selectMode(mode)
/// }
/// ```
public enum DockMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    
    /// Silent browsing without audio or speech.
    case readOnly = "readOnly"
    
    /// TTS reads affirmations, user listens.
    case readAloud = "readAloud"
    
    /// TTS reads, then user repeats aloud.
    case readAndSpeak = "readThenSpeak"
    
    /// User speaks affirmations without TTS prompt.
    case speakOnly = "speakOnly"
    
    // MARK: - Identifiable
    
    public var id: String { rawValue }
    
    // MARK: - Display Properties
    
    /// Human-readable name for UI display.
    ///
    /// Used in mode selector buttons and expanded menu options.
    public var displayName: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .readAloud:
            return "Read Aloud"
        case .readAndSpeak:
            return "Read & Speak"
        case .speakOnly:
            return "Speak Only"
        }
    }
    
    /// SF Symbol icon name for this mode.
    ///
    /// Used in mode selector buttons and expanded menu options.
    public var iconName: String {
        switch self {
        case .readOnly:
            return "book.fill"
        case .readAloud:
            return "speaker.wave.2.fill"
        case .readAndSpeak:
            return "mic.and.signal.meter.fill"
        case .speakOnly:
            return "mic.fill"
        }
    }
    
    /// Detailed description for mode selector menu.
    ///
    /// Provides additional context when the user is choosing a mode.
    public var description: String {
        switch self {
        case .readOnly:
            return "Swipe through affirmations at your own pace"
        case .readAloud:
            return "Listen as affirmations are spoken to you"
        case .readAndSpeak:
            return "Hear the affirmation, then repeat it aloud"
        case .speakOnly:
            return "Read each affirmation aloud yourself"
        }
    }
}

// MARK: - Accessibility

public extension DockMode {
    
    /// Accessibility label for the mode button.
    ///
    /// Provides a clear description for VoiceOver users.
    var accessibilityLabel: String {
        "\(displayName) mode"
    }
    
    /// Accessibility hint for the mode button.
    ///
    /// Describes what happens when the mode is selected.
    var accessibilityHint: String {
        description
    }
}
