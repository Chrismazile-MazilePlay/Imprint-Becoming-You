//
//  VoiceSettings.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/2/26.
//

import Foundation

// MARK: - Voice Settings

/// Settings for customizing voice TTS parameters.
///
/// Stores speed, pitch shift, and pitch range settings for each voice.
/// Settings are persisted per-voice using `VoiceSettingsManager`.
///
/// ## Properties
/// - `speed`: Playback speed (0.5x to 2.0x, default 1.0x)
/// - `pitchShiftSemitones`: Pitch shift in semitones (-12 to +12, default 0)
/// - `pitchRangeScale`: Expressiveness/variation (0.5 to 1.5, default 1.0)
///
/// ## Usage
/// ```swift
/// // Load settings for a voice
/// let settings = VoiceSettingsManager.shared.settings(for: "kokoro_af_heart")
///
/// // Modify and save
/// var modified = settings
/// modified.speed = 0.9
/// modified.pitchShiftSemitones = 2
/// VoiceSettingsManager.shared.save(modified, for: "kokoro_af_heart")
/// ```
struct VoiceSettings: Codable, Equatable {
    
    // MARK: - Properties
    
    /// Playback speed multiplier (0.5 to 2.0)
    var speed: Float
    
    /// Pitch shift in semitones (-12 to +12)
    var pitchShiftSemitones: Int
    
    /// Pitch variation/expressiveness scale (0.5 to 1.5)
    var pitchRangeScale: Float
    
    // MARK: - Defaults
    
    /// Default voice settings (no modifications)
    static let `default` = VoiceSettings(
        speed: 1.0,
        pitchShiftSemitones: 0,
        pitchRangeScale: 1.0
    )
    
    // MARK: - Computed Properties
    
    /// Pitch shift as Float (for TTS API compatibility)
    var pitchShiftFloat: Float {
        Float(pitchShiftSemitones)
    }
    
    /// Whether these settings differ from defaults
    var isModified: Bool {
        self != .default
    }
    
    // MARK: - Initialization
    
    init(speed: Float = 1.0, pitchShiftSemitones: Int = 0, pitchRangeScale: Float = 1.0) {
        self.speed = Self.clampSpeed(speed)
        self.pitchShiftSemitones = Self.clampPitchShift(pitchShiftSemitones)
        self.pitchRangeScale = Self.clampPitchRange(pitchRangeScale)
    }
    
    // MARK: - Validation
    
    /// Clamps speed to valid range (0.5 - 2.0)
    static func clampSpeed(_ value: Float) -> Float {
        max(0.5, min(2.0, value))
    }
    
    /// Clamps pitch shift to valid range (-12 to +12)
    static func clampPitchShift(_ value: Int) -> Int {
        max(-12, min(12, value))
    }
    
    /// Clamps pitch range to valid range (0.5 - 1.5)
    static func clampPitchRange(_ value: Float) -> Float {
        max(0.5, min(1.5, value))
    }
    
    // MARK: - Display Helpers
    
    /// Formatted speed string (e.g., "1.0x", "0.9x")
    var speedDisplayString: String {
        String(format: "%.1fx", speed)
    }
    
    /// Formatted pitch shift string (e.g., "+2", "-3", "0")
    var pitchShiftDisplayString: String {
        if pitchShiftSemitones > 0 {
            return "+\(pitchShiftSemitones)"
        } else if pitchShiftSemitones < 0 {
            return "\(pitchShiftSemitones)"
        } else {
            return "0"
        }
    }
    
    /// Formatted pitch range string (e.g., "1.0", "1.2")
    var pitchRangeDisplayString: String {
        String(format: "%.1f", pitchRangeScale)
    }
}

// MARK: - Voice Settings Manager

/// Manages persistence of per-voice settings.
///
/// Settings are stored in UserDefaults as a JSON dictionary keyed by voice ID.
/// Uses the full Voice.id format (e.g., "kokoro_af_heart") as keys.
///
/// ## Thread Safety
/// Access should be performed on the main actor for consistency with UI state.
///
/// ## Storage Format
/// ```json
/// {
///   "kokoro_af_heart": {"speed": 0.9, "pitchShiftSemitones": 2, "pitchRangeScale": 1.2},
///   "kokoro_am_adam": {"speed": 1.1, "pitchShiftSemitones": -1, "pitchRangeScale": 0.8}
/// }
/// ```
@MainActor
final class VoiceSettingsManager {
    
    // MARK: - Singleton
    
    static let shared = VoiceSettingsManager()
    
    // MARK: - Constants
    
    private let userDefaultsKey = "com.imprint.voiceSettings"
    
    // MARK: - Properties
    
    /// Cached settings dictionary (loaded once from UserDefaults)
    private var cachedSettings: [String: VoiceSettings]?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Retrieves settings for a voice.
    ///
    /// - Parameter voiceId: Full voice ID (e.g., "kokoro_af_heart")
    /// - Returns: Voice settings, or default if none saved
    func settings(for voiceId: String) -> VoiceSettings {
        loadIfNeeded()
        return cachedSettings?[voiceId] ?? .default
    }
    
    /// Saves settings for a voice.
    ///
    /// - Parameters:
    ///   - settings: Settings to save
    ///   - voiceId: Full voice ID (e.g., "kokoro_af_heart")
    func save(_ settings: VoiceSettings, for voiceId: String) {
        loadIfNeeded()
        
        // If settings are default, remove from storage to save space
        if settings == .default {
            cachedSettings?.removeValue(forKey: voiceId)
        } else {
            cachedSettings?[voiceId] = settings
        }
        
        persist()
        
        #if DEBUG
        print("VoiceSettingsManager: Saved settings for \(voiceId): \(settings)")
        #endif
    }
    
    /// Removes settings for a voice (resets to default).
    ///
    /// - Parameter voiceId: Full voice ID (e.g., "kokoro_af_heart")
    func remove(for voiceId: String) {
        loadIfNeeded()
        cachedSettings?.removeValue(forKey: voiceId)
        persist()
        
        #if DEBUG
        print("VoiceSettingsManager: Removed settings for \(voiceId)")
        #endif
    }
    
    /// Checks if a voice has custom settings.
    ///
    /// - Parameter voiceId: Full voice ID (e.g., "kokoro_af_heart")
    /// - Returns: True if custom settings exist
    func hasCustomSettings(for voiceId: String) -> Bool {
        loadIfNeeded()
        return cachedSettings?[voiceId] != nil
    }
    
    /// Gets all voice IDs that have custom settings.
    ///
    /// - Returns: Set of voice IDs with custom settings
    func voiceIdsWithCustomSettings() -> Set<String> {
        loadIfNeeded()
        guard let settings = cachedSettings else { return Set() }
        return Set(settings.keys)
    }
    
    /// Clears all custom settings.
    func clearAll() {
        cachedSettings = [:]
        persist()
        
        #if DEBUG
        print("VoiceSettingsManager: Cleared all settings")
        #endif
    }
    
    // MARK: - Private Methods
    
    private func loadIfNeeded() {
        guard cachedSettings == nil else { return }
        
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            cachedSettings = [:]
            return
        }
        
        do {
            let decoder = JSONDecoder()
            cachedSettings = try decoder.decode([String: VoiceSettings].self, from: data)
            
            #if DEBUG
            print("VoiceSettingsManager: Loaded \(cachedSettings?.count ?? 0) voice settings")
            #endif
        } catch {
            #if DEBUG
            print("VoiceSettingsManager: Failed to decode settings: \(error)")
            #endif
            cachedSettings = [:]
        }
    }
    
    private func persist() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(cachedSettings)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            #if DEBUG
            print("VoiceSettingsManager: Failed to encode settings: \(error)")
            #endif
        }
    }
}
