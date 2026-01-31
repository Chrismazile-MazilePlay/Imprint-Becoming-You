//
//  MockVoiceCloneService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Voice Clone Service

/// Mock implementation for testing.
///
/// Uses `@MainActor` isolation consistent with the protocol.
@MainActor
final class MockVoiceCloneService: VoiceCloneServiceProtocol {
    
    // MARK: - Configuration
    
    /// Simulated clone creation delay
    var cloneCreationDelay: Duration = .seconds(1)
    
    /// Set of valid voice IDs for validation
    var validVoiceIds: Set<String> = []
    
    // MARK: - VoiceCloneServiceProtocol
    
    func createVoiceClone(from audioData: Data, name: String) async throws -> String {
        try await Task.sleep(for: cloneCreationDelay)
        let voiceId = "mock-clone-\(UUID().uuidString.prefix(8))"
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
        Data()
    }
}
