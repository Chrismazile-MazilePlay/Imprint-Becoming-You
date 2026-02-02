//
//  VoicePreviewCacheServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Voice Preview Service Protocol

/// Protocol for on-demand voice preview synthesis.
///
/// Provides voice preview audio synthesis for the voice selection UI
/// in both onboarding and settings. Synthesizes fresh audio on each
/// request (no caching) with automatic cancellation and retry support.
///
/// ## Behavior
/// - **On-demand synthesis:** Each tap synthesizes a fresh preview
/// - **Cancellation:** Tapping a new voice cancels the previous synthesis
/// - **Auto-retry:** Automatically retries once on failure
/// - **No caching:** Audio is not persisted between requests
///
/// ## Usage
/// ```swift
/// let service = dependencies.voicePreviewCacheService
///
/// // User taps a voice
/// service.cancelSynthesis()  // Cancel any in-flight synthesis
///
/// do {
///     let audioData = try await service.synthesizePreview(voiceId: "af_heart")
///     playAudio(audioData)
/// } catch {
///     // Handle error (already retried once)
/// }
/// ```
@MainActor
protocol VoicePreviewCacheServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether a synthesis is currently in progress.
    ///
    /// Use this to show loading indicators in the UI.
    var isSynthesizing: Bool { get }
    
    // MARK: - Synthesis
    
    /// Synthesize a voice preview on-demand.
    ///
    /// This method synthesizes the preview phrase using the specified voice.
    /// It automatically retries once on failure before throwing an error.
    ///
    /// **Note:** This does NOT cancel previous synthesis - call `cancelSynthesis()`
    /// first if you want to cancel an in-flight request.
    ///
    /// - Parameter voiceId: The raw voice ID (e.g., "af_heart")
    /// - Returns: Audio data (WAV format)
    /// - Throws: `AppError.ttsError` if synthesis fails after retry
    func synthesizePreview(voiceId: String) async throws -> Data
    
    // MARK: - Cancellation
    
    /// Cancel any in-flight synthesis task.
    ///
    /// Call this before starting a new synthesis to ensure only one
    /// synthesis runs at a time. Safe to call even if no synthesis
    /// is in progress.
    func cancelSynthesis()
}
