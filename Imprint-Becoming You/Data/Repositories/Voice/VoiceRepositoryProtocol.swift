//
//  VoiceRepositoryProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation
import SwiftData

// MARK: - Voice Repository Protocol

/// Protocol for persisting voice data.
///
/// Manages:
/// - User's selected voice preference
/// - Custom voices (cloned, designed)
/// - Voice usage statistics
///
/// ## Storage
/// - **Selected voice**: UserProfile.selectedVoiceId
/// - **Custom voices**: VoiceRecord SwiftData entities
/// - **Preset voices**: Static catalogs in Voice.swift
///
/// - Note: `@MainActor` isolated for SwiftData compatibility.
@MainActor
protocol VoiceRepositoryProtocol: AnyObject {
    
    // MARK: - Selected Voice
    
    /// Gets the user's currently selected voice ID.
    func getSelectedVoiceId() -> String?
    
    /// Sets the user's selected voice.
    func setSelectedVoice(_ voiceId: String) throws
    
    /// Clears voice selection (falls back to default).
    func clearSelectedVoice() throws
    
    /// Gets selected voice or default.
    func getSelectedVoiceOrDefault() -> Voice
    
    // MARK: - Voice Retrieval
    
    /// Fetches a voice by ID (checks custom, then preset catalogs).
    func fetchVoice(id: String) -> Voice?
    
    /// Fetches voices by category.
    func fetchVoices(category: VoiceCategory) -> [Voice]
    
    /// Fetches all custom voices (cloned + designed).
    func fetchCustomVoices() -> [Voice]
    
    /// Fetches all available voices.
    func fetchAllVoices() -> [Voice]
    
    // MARK: - Custom Voice Management
    
    /// Saves a custom voice.
    func saveVoice(_ voice: Voice) throws
    
    /// Updates a custom voice.
    func updateVoice(_ voice: Voice) throws
    
    /// Deletes a custom voice.
    func deleteVoice(id: String) throws
    
    /// Checks if a custom voice exists.
    func customVoiceExists(id: String) -> Bool
    
    // MARK: - Usage Tracking
    
    /// Records voice usage for recommendations.
    func recordUsage(voiceId: String)
    
    /// Gets recently used voices.
    func getRecentlyUsed(limit: Int) -> [Voice]
    
    // MARK: - Default Voice
    
    /// Gets the default voice for new users.
    func getDefaultVoice() -> Voice
}

// MARK: - Default Implementations

extension VoiceRepositoryProtocol {
    
    func getSelectedVoiceOrDefault() -> Voice {
        if let id = getSelectedVoiceId(), let voice = fetchVoice(id: id) {
            return voice
        }
        return getDefaultVoice()
    }
    
    func getRecentlyUsed() -> [Voice] {
        getRecentlyUsed(limit: 5)
    }
    
    func getDefaultVoice() -> Voice {
        Voice.defaultVoice
    }
}

// MARK: - Voice Record (SwiftData Entity)

/// SwiftData entity for custom voices (cloned, designed).
@Model
final class VoiceRecord {
    
    @Attribute(.unique)
    var id: String
    
    var name: String
    var categoryRawValue: String
    var languageCode: String
    var qwenSpeakerId: String?
    var sourceAudioPath: String?
    var createdAt: Date
    var style: String?
    var genderRawValue: String?
    var usageCount: Int
    var lastUsedAt: Date?
    
    init(
        id: String,
        name: String,
        category: VoiceCategory,
        languageCode: String,
        qwenSpeakerId: String? = nil,
        sourceAudioPath: String? = nil,
        style: String? = nil,
        gender: VoiceGender? = nil
    ) {
        self.id = id
        self.name = name
        self.categoryRawValue = category.rawValue
        self.languageCode = languageCode
        self.qwenSpeakerId = qwenSpeakerId
        self.sourceAudioPath = sourceAudioPath
        self.createdAt = Date()
        self.style = style
        self.genderRawValue = gender?.rawValue
        self.usageCount = 0
        self.lastUsedAt = nil
    }
    
    // MARK: - Computed Properties
    
    var category: VoiceCategory {
        VoiceCategory(rawValue: categoryRawValue) ?? .cloned
    }
    
    var gender: VoiceGender? {
        genderRawValue.flatMap { VoiceGender(rawValue: $0) }
    }
    
    var isCloned: Bool {
        category == .cloned
    }
    
    var sourceAudioURL: URL? {
        guard let path = sourceAudioPath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(path)
    }
    
    // MARK: - Conversion
    
    func toVoice() -> Voice {
        Voice(
            id: id,
            name: name,
            provider: .qwenCloud,
            category: category,
            languageCode: languageCode,
            isPremiumOnly: true,
            qwenSpeakerId: qwenSpeakerId,
            isCloned: isCloned,
            cloneSourceAudioURL: sourceAudioURL,
            clonedAt: createdAt,
            gender: gender,
            style: style
        )
    }
}

// MARK: - VoiceRecord Factory

extension VoiceRecord {
    
    convenience init(from voice: Voice) {
        let relativePath = voice.cloneSourceAudioURL?.lastPathComponent
        
        self.init(
            id: voice.id,
            name: voice.name,
            category: voice.category,
            languageCode: voice.languageCode,
            qwenSpeakerId: voice.qwenSpeakerId,
            sourceAudioPath: relativePath,
            style: voice.style,
            gender: voice.gender
        )
    }
}

// MARK: - Voice Usage Record

/// Tracks voice usage for recommendations.
@Model
final class VoiceUsageRecord {
    
    @Attribute(.unique)
    var voiceId: String
    
    var synthesisCount: Int
    var lastUsedAt: Date
    var firstUsedAt: Date
    
    init(voiceId: String) {
        self.voiceId = voiceId
        self.synthesisCount = 1
        self.lastUsedAt = Date()
        self.firstUsedAt = Date()
    }
    
    func recordUsage() {
        synthesisCount += 1
        lastUsedAt = Date()
    }
}
