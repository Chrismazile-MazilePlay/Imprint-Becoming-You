//
//  VoiceCloneService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Voice Clone Service

/// Stub implementation of voice cloning (Phase 7).
final class VoiceCloneService: VoiceCloneServiceProtocol, @unchecked Sendable {
    
    func createVoiceClone(from audioData: Data, name: String) async throws -> String {
        throw AppError.notImplemented(feature: "Voice cloning")
    }
    
    func deleteVoiceClone(voiceId: String) async throws {
        // No-op
    }
    
    func validateVoiceClone(voiceId: String) async -> Bool {
        false
    }
    
    func getVoicePreview(voiceId: String) async throws -> Data {
        throw AppError.notImplemented(feature: "Voice preview")
    }
}
