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
/// ## MainActor Isolation
/// This protocol is `@MainActor` isolated because:
/// 1. Voice clone status affects UI state
/// 2. Audio data may be passed to other MainActor services
/// 3. Consistent with other service protocols
///
/// ## Usage
/// ```swift
/// let voiceId = try await service.createVoiceClone(from: audioData, name: "My Voice")
/// let isValid = await service.validateVoiceClone(voiceId: voiceId)
/// ```
@MainActor
protocol VoiceCloneServiceProtocol: AnyObject {
    
    /// Creates a voice clone from audio data.
    /// - Parameters:
    ///   - audioData: Raw audio data for voice sampling
    ///   - name: Display name for the cloned voice
    /// - Returns: Unique identifier for the created voice clone
    /// - Throws: `AppError.notImplemented` or voice cloning errors
    func createVoiceClone(from audioData: Data, name: String) async throws -> String
    
    /// Deletes a voice clone.
    /// - Parameter voiceId: The voice clone identifier to delete
    /// - Throws: Deletion errors
    func deleteVoiceClone(voiceId: String) async throws
    
    /// Validates that a voice clone exists and is usable.
    /// - Parameter voiceId: The voice clone identifier to validate
    /// - Returns: Whether the voice clone is valid and usable
    func validateVoiceClone(voiceId: String) async -> Bool
    
    /// Gets a preview audio sample for a voice.
    /// - Parameter voiceId: The voice clone identifier
    /// - Returns: Audio data for the preview sample
    /// - Throws: `AppError.notImplemented` or preview generation errors
    func getVoicePreview(voiceId: String) async throws -> Data
}
