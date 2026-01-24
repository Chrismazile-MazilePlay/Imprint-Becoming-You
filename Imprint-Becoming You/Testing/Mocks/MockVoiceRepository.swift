//
//  MockVoiceRepository.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation

// MARK: - Mock Voice Repository

/// Mock implementation of VoiceRepositoryProtocol for testing and previews.
@MainActor
final class MockVoiceRepository: VoiceRepositoryProtocol {
    
    // MARK: - Properties
    
    private var selectedVoiceId: String?
    private var customVoices: [String: Voice] = [:]
    private var usageRecords: [String: Int] = [:]
    
    // Test hooks
    var shouldFailOnSave: Bool = false
    var shouldFailOnDelete: Bool = false
    
    // MARK: - Initialization
    
    init(selectedVoiceId: String? = nil) {
        self.selectedVoiceId = selectedVoiceId
    }
    
    // MARK: - Selected Voice
    
    func getSelectedVoiceId() -> String? {
        selectedVoiceId
    }
    
    func setSelectedVoice(_ voiceId: String) throws {
        guard fetchVoice(id: voiceId) != nil else {
            throw VoiceRepositoryError.voiceNotFound(id: voiceId)
        }
        selectedVoiceId = voiceId
    }
    
    func clearSelectedVoice() throws {
        selectedVoiceId = nil
    }
    
    // MARK: - Voice Retrieval
    
    func fetchVoice(id: String) -> Voice? {
        // Check custom voices first
        if let voice = customVoices[id] {
            return voice
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
            return customVoices.values.filter { $0.category == category }
        }
    }
    
    func fetchCustomVoices() -> [Voice] {
        Array(customVoices.values)
    }
    
    func fetchAllVoices() -> [Voice] {
        var voices = Voice.freeKokoroVoices
        voices.append(contentsOf: customVoices.values)
        voices.append(contentsOf: Voice.premiumKokoroVoices)
        voices.append(contentsOf: Voice.qwenPresetVoices)
        return voices
    }
    
    // MARK: - Custom Voice Management
    
    func saveVoice(_ voice: Voice) throws {
        if shouldFailOnSave {
            throw VoiceRepositoryError.saveFailed(underlying: NSError(domain: "Mock", code: 1))
        }
        
        guard voice.category == .cloned || voice.category == .designed else {
            throw VoiceRepositoryError.invalidVoiceCategory
        }
        
        customVoices[voice.id] = voice
    }
    
    func updateVoice(_ voice: Voice) throws {
        guard customVoices[voice.id] != nil else {
            throw VoiceRepositoryError.voiceNotFound(id: voice.id)
        }
        customVoices[voice.id] = voice
    }
    
    func deleteVoice(id: String) throws {
        if shouldFailOnDelete {
            throw VoiceRepositoryError.saveFailed(underlying: NSError(domain: "Mock", code: 1))
        }
        
        guard customVoices[id] != nil else {
            throw VoiceRepositoryError.voiceNotFound(id: id)
        }
        
        if selectedVoiceId == id {
            selectedVoiceId = nil
        }
        
        customVoices.removeValue(forKey: id)
    }
    
    func customVoiceExists(id: String) -> Bool {
        customVoices[id] != nil
    }
    
    // MARK: - Usage Tracking
    
    func recordUsage(voiceId: String) {
        usageRecords[voiceId, default: 0] += 1
    }
    
    func getRecentlyUsed(limit: Int) -> [Voice] {
        let sortedIds = usageRecords
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
        
        return sortedIds.compactMap { fetchVoice(id: $0) }
    }
    
    // MARK: - Default Voice
    
    func getDefaultVoice() -> Voice {
        Voice.defaultVoice
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        selectedVoiceId = nil
        customVoices.removeAll()
        usageRecords.removeAll()
        shouldFailOnSave = false
        shouldFailOnDelete = false
    }
    
    func seedCustomVoices(_ voices: [Voice]) {
        for voice in voices {
            customVoices[voice.id] = voice
        }
    }
}
