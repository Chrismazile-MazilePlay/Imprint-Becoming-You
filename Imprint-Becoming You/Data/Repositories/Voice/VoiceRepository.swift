//
//  VoiceRepository.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation
import SwiftData

// MARK: - Voice Repository

/// SwiftData implementation of voice persistence.
///
/// Manages:
/// - User's selected voice preference (stored in UserProfile)
/// - Custom voices (cloned, designed) as VoiceRecord entities
/// - Voice usage statistics for recommendations
///
/// ## Error Handling Strategy
///
/// This repository follows a consistent error handling contract:
///
/// - **Voice not found**: Return `nil` for fetch methods. This is expected behavior,
///   not an error condition. The caller should handle the nil case appropriately.
///
/// - **User profile not found**: Throw `VoiceRepositoryError.userProfileNotFound` for
///   operations that require the user profile to exist.
///
/// - **Invalid category**: Throw `VoiceRepositoryError.invalidVoiceCategory` when
///   attempting to save a non-custom voice.
///
/// - **Best-effort operations**: The `recordUsage` and `getRecentlyUsed` methods
///   log and return gracefully on errors, since usage tracking is non-critical.
///
/// ## Usage
/// ```swift
/// let repository = VoiceRepository(modelContext: context)
///
/// // Get selected voice
/// let voice = repository.getSelectedVoiceOrDefault()
///
/// // Save cloned voice
/// try repository.saveVoice(clonedVoice)
/// try repository.setSelectedVoice(clonedVoice.id)
/// ```
@MainActor
final class VoiceRepository: VoiceRepositoryProtocol {
    
    // MARK: - Properties
    
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Selected Voice
    
    func getSelectedVoiceId() -> String? {
        fetchUserProfile()?.selectedVoiceId
    }
    
    func setSelectedVoice(_ voiceId: String) throws {
        guard let profile = fetchUserProfile() else {
            throw VoiceRepositoryError.userProfileNotFound
        }
        
        // Verify voice exists
        guard fetchVoice(id: voiceId) != nil else {
            throw VoiceRepositoryError.voiceNotFound(id: voiceId)
        }
        
        profile.selectedVoiceId = voiceId
        try modelContext.save()
        
        AppLogger.debug(
            "Selected voice updated",
            category: .data,
            context: ["voiceId": voiceId]
        )
    }
    
    func clearSelectedVoice() throws {
        guard let profile = fetchUserProfile() else {
            throw VoiceRepositoryError.userProfileNotFound
        }
        
        profile.selectedVoiceId = nil
        try modelContext.save()
        
        AppLogger.debug("Voice selection cleared", category: .data)
    }
    
    // MARK: - Voice Retrieval
    
    func fetchVoice(id: String) -> Voice? {
        // Check custom voices first (database)
        if let record = fetchVoiceRecord(id: id) {
            return record.toVoice()
        }
        
        // Check preset catalogs
        return VoiceCatalog.findVoice(id: id)
    }
    
    func fetchVoices(category: VoiceCategory) -> [Voice] {
        switch category {
        case .system:
            return []
            
        case .preset:
            return Voice.allKokoroVoices + Voice.qwenPresetVoices
            
        case .cloned, .designed:
            return fetchCustomVoiceRecords()
                .filter { $0.category == category }
                .map { $0.toVoice() }
        }
    }
    
    func fetchCustomVoices() -> [Voice] {
        fetchCustomVoiceRecords().map { $0.toVoice() }
    }
    
    func fetchAllVoices() -> [Voice] {
        var voices: [Voice] = []
        
        // Free Kokoro voices first (most accessible)
        voices.append(contentsOf: Voice.freeKokoroVoices)
        
        // Custom voices (user's own)
        voices.append(contentsOf: fetchCustomVoices())
        
        // Premium Kokoro voices
        voices.append(contentsOf: Voice.premiumKokoroVoices)
        
        // Qwen preset voices
        voices.append(contentsOf: Voice.qwenPresetVoices)
        
        return voices
    }
    
    // MARK: - Custom Voice Management
    
    func saveVoice(_ voice: Voice) throws {
        guard voice.category == .cloned || voice.category == .designed else {
            throw VoiceRepositoryError.invalidVoiceCategory
        }
        
        if let existing = fetchVoiceRecord(id: voice.id) {
            // Update existing
            existing.name = voice.name
            existing.qwenSpeakerId = voice.qwenSpeakerId
            existing.style = voice.style
            existing.genderRawValue = voice.gender?.rawValue
            
            AppLogger.debug(
                "Updated existing voice record",
                category: .data,
                context: ["voiceId": voice.id, "name": voice.name]
            )
        } else {
            // Create new
            let record = VoiceRecord(from: voice)
            modelContext.insert(record)
            
            AppLogger.info(
                "Created new voice record",
                category: .data,
                context: ["voiceId": voice.id, "name": voice.name, "category": voice.category.rawValue]
            )
        }
        
        try modelContext.save()
    }
    
    func updateVoice(_ voice: Voice) throws {
        guard let record = fetchVoiceRecord(id: voice.id) else {
            throw VoiceRepositoryError.voiceNotFound(id: voice.id)
        }
        
        record.name = voice.name
        record.qwenSpeakerId = voice.qwenSpeakerId
        record.style = voice.style
        record.genderRawValue = voice.gender?.rawValue
        
        try modelContext.save()
        
        AppLogger.debug(
            "Voice updated",
            category: .data,
            context: ["voiceId": voice.id, "name": voice.name]
        )
    }
    
    func deleteVoice(id: String) throws {
        guard let record = fetchVoiceRecord(id: id) else {
            throw VoiceRepositoryError.voiceNotFound(id: id)
        }
        
        let voiceName = record.name
        
        // Clear selection if this was selected
        if getSelectedVoiceId() == id {
            try clearSelectedVoice()
        }
        
        // Delete source audio file
        if let audioURL = record.sourceAudioURL {
            do {
                try FileManager.default.removeItem(at: audioURL)
                AppLogger.debug(
                    "Deleted voice audio file",
                    category: .data,
                    context: ["path": audioURL.lastPathComponent]
                )
            } catch {
                // Log but don't fail - the voice record deletion is more important
                AppLogger.warning(
                    "Failed to delete voice audio file",
                    category: .data,
                    context: ["path": audioURL.lastPathComponent, "error": error.localizedDescription]
                )
            }
        }
        
        modelContext.delete(record)
        try modelContext.save()
        
        AppLogger.info(
            "Deleted voice",
            category: .data,
            context: ["voiceId": id, "name": voiceName]
        )
    }
    
    func customVoiceExists(id: String) -> Bool {
        fetchVoiceRecord(id: id) != nil
    }
    
    // MARK: - Usage Tracking
    //
    // These are "best effort" operations - they log and return gracefully
    // on any error, since usage tracking is non-critical analytics.
    
    func recordUsage(voiceId: String) {
        let descriptor = FetchDescriptor<VoiceUsageRecord>(
            predicate: #Predicate { $0.voiceId == voiceId }
        )
        
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.recordUsage()
            } else {
                let record = VoiceUsageRecord(voiceId: voiceId)
                modelContext.insert(record)
            }
            try modelContext.save()
            
        } catch {
            // Log but don't throw - usage tracking is non-critical
            AppLogger.debug(
                "Failed to record voice usage",
                category: .data,
                context: ["voiceId": voiceId, "error": error.localizedDescription]
            )
        }
    }
    
    func getRecentlyUsed(limit: Int) -> [Voice] {
        var descriptor = FetchDescriptor<VoiceUsageRecord>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        do {
            let records = try modelContext.fetch(descriptor)
            return records.compactMap { fetchVoice(id: $0.voiceId) }
            
        } catch {
            // Log but return empty - usage tracking is non-critical
            AppLogger.debug(
                "Failed to fetch recently used voices",
                category: .data,
                context: ["error": error.localizedDescription]
            )
            return []
        }
    }
    
    // MARK: - Default Voice
    
    func getDefaultVoice() -> Voice {
        Voice.defaultVoice
    }
    
    // MARK: - Private Helpers
    
    private func fetchUserProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            AppLogger.warning(
                "Failed to fetch user profile",
                category: .data,
                context: ["error": error.localizedDescription]
            )
            return nil
        }
    }
    
    private func fetchVoiceRecord(id: String) -> VoiceRecord? {
        let descriptor = FetchDescriptor<VoiceRecord>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            AppLogger.debug(
                "Failed to fetch voice record",
                category: .data,
                context: ["voiceId": id, "error": error.localizedDescription]
            )
            return nil
        }
    }
    
    private func fetchCustomVoiceRecords() -> [VoiceRecord] {
        let descriptor = FetchDescriptor<VoiceRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            AppLogger.warning(
                "Failed to fetch custom voice records",
                category: .data,
                context: ["error": error.localizedDescription]
            )
            return []
        }
    }
}

// MARK: - Voice Repository Errors

/// Errors specific to voice repository operations.
///
/// These errors are thrown when voice operations fail due to
/// missing entities or invalid input.
enum VoiceRepositoryError: LocalizedError {
    /// User profile doesn't exist (should be created during onboarding)
    case userProfileNotFound
    
    /// Voice with the specified ID was not found
    case voiceNotFound(id: String)
    
    /// Attempted to save a voice that isn't a custom category
    case invalidVoiceCategory
    
    /// Underlying save operation failed
    case saveFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .userProfileNotFound:
            return "User profile not found"
        case .voiceNotFound(let id):
            return "Voice not found: \(id)"
        case .invalidVoiceCategory:
            return "Only cloned or designed voices can be saved"
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        }
    }
}
