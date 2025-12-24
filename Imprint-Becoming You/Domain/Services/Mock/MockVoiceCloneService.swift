//
//  MockVoiceCloneService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Voice Clone Service

/// Mock implementation of voice clone service for previews and testing.
///
/// Simulates voice cloning operations without actual API calls.
final class MockVoiceCloneService: VoiceCloneServiceProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Simulated clone creation delay
    var cloneCreationDelay: Duration = .seconds(3)
    
    /// Set of "valid" voice IDs for testing validation
    var validVoiceIds: Set<String> = []
    
    // MARK: - VoiceCloneServiceProtocol
    
    func createVoiceClone(from audioData: Data, name: String) async throws -> String {
        try await Task.sleep(for: cloneCreationDelay)
        
        let voiceId = "mock-voice-id-\(UUID().uuidString.prefix(8))"
        validVoiceIds.insert(voiceId)
        return voiceId
    }
    
    func deleteVoiceClone(voiceId: String) async throws {
        validVoiceIds.remove(voiceId)
    }
    
    func validateVoiceClone(voiceId: String) async -> Bool {
        validVoiceIds.contains(voiceId)
    }
    
    func getVoicePreview(voiceId: String) async throws -> Data {
        // Return empty data for mock
        Data()
    }
}
