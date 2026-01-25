//
//  VoiceCloneServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//


import Foundation

// MARK: - Voice Clone Service Protocol

/// Protocol for voice cloning (Phase 7 - Qwen DashScope API).
///
/// ## Usage
/// ```swift
/// let voiceId = try await service.createVoiceClone(from: audioData, name: "My Voice")
/// let isValid = await service.validateVoiceClone(voiceId: voiceId)
/// ```
protocol VoiceCloneServiceProtocol: AnyObject, Sendable {
    
    /// Creates a voice clone from audio data.
    func createVoiceClone(from audioData: Data, name: String) async throws -> String
    
    /// Deletes a voice clone.
    func deleteVoiceClone(voiceId: String) async throws
    
    /// Validates that a voice clone exists and is usable.
    func validateVoiceClone(voiceId: String) async -> Bool
    
    /// Gets a preview audio sample for a voice.
    func getVoicePreview(voiceId: String) async throws -> Data
}
