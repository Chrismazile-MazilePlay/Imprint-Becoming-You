//
//  Voice+SelectionUI.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Voice Display Group

/// Categories for organizing voices in the selection UI.
///
/// Groups voices by accent and gender for intuitive browsing.
/// This is separate from `VoiceCategory` which classifies by origin (preset, cloned, etc.)
///
/// ## Usage
/// Use `Voice.englishVoicesByDisplayGroup` to get grouped voices for UI display.
enum VoiceDisplayGroup: String, CaseIterable, Identifiable, Sendable {
    case americanFemale = "American Female"
    case americanMale = "American Male"
    case britishFemale = "British Female"
    case britishMale = "British Male"
    case system = "System"
    
    var id: String { rawValue }
    
    /// Display name for section headers
    var displayName: String { rawValue }
    
    /// Icon for the category
    var iconName: String {
        switch self {
        case .americanFemale, .britishFemale:
            return "person.fill"
        case .americanMale, .britishMale:
            return "person.fill"
        case .system:
            return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Voice Selection UI Extensions

extension Voice {
    
    // MARK: - Constants
    
    /// Preview phrase for voice selection UI
    static let previewPhrase = "I celebrate the good qualities in others and myself."
    
    /// System voice identifier for TTS routing
    static let systemVoiceIdentifier = "system"
    
    // MARK: - Display Group
    
    /// The display group for this voice based on accent and gender.
    ///
    /// Returns `nil` for non-English voices or voices without gender info.
    var displayGroup: VoiceDisplayGroup? {
        // System voices
        if provider == .system {
            return .system
        }
        
        // Only categorize English Kokoro voices
        guard provider == .kokoro else { return nil }
        
        let isAmerican = languageCode == "en-US"
        let isBritish = languageCode == "en-GB"
        
        switch (gender, isAmerican, isBritish) {
        case (.female, true, _): return .americanFemale
        case (.male, true, _): return .americanMale
        case (.female, _, true): return .britishFemale
        case (.male, _, true): return .britishMale
        default: return nil
        }
    }
    
    /// Whether this is the default voice
    var isDefaultVoice: Bool {
        id == Voice.defaultVoice.id
    }
    
    /// Display name with default indicator if applicable.
    var displayNameWithDefault: String {
        isDefaultVoice ? "\(name) (Default)" : name
    }
    
    // MARK: - System Voice for Selection
    
    /// System TTS voice for selection UI
    static let systemVoiceForSelection = Voice(
        id: systemVoiceIdentifier,
        name: "System Voice",
        provider: .system,
        category: .system,
        languageCode: "en-US",
        isPremiumOnly: false,
        systemVoiceId: nil
    )
    
    // MARK: - Voice Lookup
    
    /// Finds a voice by its full ID (e.g., "kokoro_af_heart" or "system").
    ///
    /// - Parameter id: The full voice ID stored in UserProfile
    /// - Returns: The matching Voice, or defaultVoice if not found
    static func voice(forId id: String?) -> Voice {
        guard let id = id, !id.isEmpty else { return defaultVoice }
        
        // Check for system voice
        if id == systemVoiceIdentifier {
            return systemVoiceForSelection
        }
        
        // Use VoiceCatalog for lookup
        if let voice = VoiceCatalog.findVoice(id: id) {
            return voice
        }
        
        // Fallback to default
        return defaultVoice
    }
    
    // MARK: - Voice ID Conversion
    
    /// Extracts the raw TTS voice ID for engine usage.
    ///
    /// - Returns: The kokoroVoiceId for Kokoro voices, "system" for system voice, or nil
    var ttsVoiceId: String? {
        if provider == .system || id == Voice.systemVoiceIdentifier {
            return Voice.systemVoiceIdentifier
        }
        return kokoroVoiceId
    }
    
    /// Converts a stored voice ID to the format needed by TTSService.
    ///
    /// - Parameter storedId: The full voice ID from UserProfile (e.g., "kokoro_af_heart")
    /// - Returns: The raw voice ID for TTS engine (e.g., "af_heart") or "system"
    static func ttsVoiceId(from storedId: String?) -> String? {
        guard let storedId = storedId, !storedId.isEmpty else { return nil }
        
        if storedId == systemVoiceIdentifier {
            return systemVoiceIdentifier
        }
        
        // Look up the voice and return its ttsVoiceId
        let voice = voice(forId: storedId)
        return voice.ttsVoiceId
    }
    
    // MARK: - Voice Collections for UI
    
    /// All English voices grouped by display group for UI.
    ///
    /// Includes all 28 English Kokoro voices plus system voice.
    /// Organized by accent and gender for intuitive browsing.
    static var englishVoicesByDisplayGroup: [(group: VoiceDisplayGroup, voices: [Voice])] {
        var result: [(VoiceDisplayGroup, [Voice])] = []
        
        // Get all English Kokoro voices + system
        let allSelectable = allEnglishKokoroVoices + [systemVoiceForSelection]
        
        // Group by display group (excluding system from main groups)
        for group in VoiceDisplayGroup.allCases {
            let voices = allSelectable.filter { $0.displayGroup == group }
            if !voices.isEmpty {
                result.append((group, voices))
            }
        }
        
        return result
    }
    
    /// All voices (free + premium) grouped by display group.
    ///
    /// Use for premium users who have access to all voices.
    static var allEnglishVoicesByDisplayGroup: [(group: VoiceDisplayGroup, voices: [Voice])] {
        // Same as englishVoicesByDisplayGroup since all English voices are now available
        englishVoicesByDisplayGroup
    }
}
