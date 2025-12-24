//
//  VoiceCloneServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Voice Clone Service Protocol

/// Protocol for voice cloning via ElevenLabs.
///
/// Manages the lifecycle of user voice clones, including creation,
/// validation, and deletion.
///
/// ## Usage
/// ```swift
/// let service: VoiceCloneServiceProtocol = VoiceCloneService()
///
/// // Create a voice clone from recorded audio
/// let voiceId = try await service.createVoiceClone(
///     from: audioData,
///     name: "My Voice"
/// )
///
/// // Validate the clone still exists
/// let isValid = await service.validateVoiceClone(voiceId: voiceId)
/// ```
protocol VoiceCloneServiceProtocol: AnyObject, Sendable {
    
    /// Creates a voice clone from audio data
    /// - Parameters:
    ///   - audioData: Raw audio data from user recording
    ///   - name: Display name for the voice clone
    /// - Returns: ElevenLabs voice ID for the created clone
    /// - Throws: `AppError.notImplemented` or API errors
    func createVoiceClone(from audioData: Data, name: String) async throws -> String
    
    /// Deletes a voice clone from ElevenLabs
    /// - Parameter voiceId: The voice ID to delete
    /// - Throws: API errors if deletion fails
    func deleteVoiceClone(voiceId: String) async throws
    
    /// Validates that a voice clone still exists on ElevenLabs
    /// - Parameter voiceId: The voice ID to validate
    /// - Returns: `true` if the voice clone exists and is usable
    func validateVoiceClone(voiceId: String) async -> Bool
    
    /// Gets a preview audio sample for a voice
    /// - Parameter voiceId: The voice ID to preview
    /// - Returns: Audio data for the preview sample
    /// - Throws: `AppError.notImplemented` or API errors
    func getVoicePreview(voiceId: String) async throws -> Data
}
