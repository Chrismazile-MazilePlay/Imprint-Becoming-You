//
//  VoiceCloneService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Voice Clone Service

/// Stub implementation of voice cloning (Phase 7).
///
/// ## MainActor Isolation
/// This service is `@MainActor` isolated because:
/// 1. Voice clone status affects UI state
/// 2. Audio data may be passed to other MainActor services
/// 3. Consistent with protocol conformance requirements
@MainActor
final class VoiceCloneService: VoiceCloneServiceProtocol {
    
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
