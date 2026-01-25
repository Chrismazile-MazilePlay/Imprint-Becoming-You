//
//  VoiceCatalog.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation

// MARK: - Voice Catalog

/// Helper for looking up voices by ID across all voice catalogs.
///
/// Searches free Kokoro voices, premium Kokoro voices, and Qwen preset voices.
/// Also handles system voice ID format.
///
/// ## Usage
/// ```swift
/// if let voice = VoiceCatalog.findVoice(id: "kokoro_af_heart") {
///     // Use voice
/// }
/// ```
enum VoiceCatalog {
    
    /// Finds a voice by its ID across all catalogs.
    ///
    /// - Parameter id: The voice ID to search for
    /// - Returns: The matching `Voice`, or `nil` if not found
    static func findVoice(id: String) -> Voice? {
        // Check free Kokoro voices
        if let voice = Voice.freeKokoroVoices.first(where: { $0.id == id }) {
            return voice
        }
        
        // Check premium Kokoro voices
        if let voice = Voice.premiumKokoroVoices.first(where: { $0.id == id }) {
            return voice
        }
        
        // Check Qwen preset voices
        if let voice = Voice.qwenPresetVoices.first(where: { $0.id == id }) {
            return voice
        }
        
        // Handle system voices (format: "system_<identifier>")
        if id.hasPrefix("system_") {
            let systemId = String(id.dropFirst(7))
            return Voice.systemVoice(identifier: systemId, name: "System", languageCode: "en-US")
        }
        
        return nil
    }
    
    /// Returns all available voices (free + premium + cloud).
    static var allVoices: [Voice] {
        Voice.freeKokoroVoices + Voice.premiumKokoroVoices + Voice.qwenPresetVoices
    }
    
    /// Returns all free voices.
    static var freeVoices: [Voice] {
        Voice.freeKokoroVoices
    }
    
    /// Returns all premium voices.
    static var premiumVoices: [Voice] {
        Voice.premiumKokoroVoices + Voice.qwenPresetVoices
    }
    
    /// Returns voices filtered by language code.
    ///
    /// - Parameter languageCode: Language code (e.g., "en-US", "en-GB", "fr-FR")
    /// - Returns: Array of voices matching the language
    static func voices(forLanguage languageCode: String) -> [Voice] {
        allVoices.filter { $0.languageCode == languageCode }
    }
    
    /// Returns voices filtered by gender.
    ///
    /// - Parameter gender: The gender to filter by
    /// - Returns: Array of voices matching the gender
    static func voices(forGender gender: VoiceGender) -> [Voice] {
        allVoices.filter { $0.gender == gender }
    }
}
