//
//  TTSSynthesisEngineProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/5/26.
//

import Foundation

// MARK: - TTS Synthesis Engine Protocol

/// Focused interface for TTS synthesis used by `SessionTTSQueueService`.
///
/// Extracts the synthesis-specific surface area from `TTSServiceProtocol`,
/// decoupling the queue service from the full TTS service (which includes
/// playback, pre-synthesis caching, and voice preview concerns).
///
/// ## Responsibilities
/// - Kokoro readiness polling and warm-up wait
/// - Single-affirmation audio synthesis (Kokoro or System TTS)
/// - Idle timer lifecycle (suppress during session, resume on end)
///
/// ## Architecture
/// ```
/// TTSSynthesisEngineProtocol
/// ├── TTSSynthesisEngine (Production)
/// │   └── Wraps TTSServiceProtocol
/// └── MockTTSSynthesisEngine (Testing)
/// ```
@MainActor
protocol TTSSynthesisEngineProtocol: AnyObject {

    /// Whether the Kokoro TTS engine is loaded and ready for synthesis.
    var isKokoroReady: Bool { get }

    /// Waits for the Kokoro TTS engine to become ready.
    ///
    /// Returns immediately if Kokoro is already ready. Otherwise polls
    /// every 100ms until the engine is ready or the timeout is reached.
    ///
    /// - Parameter timeout: Maximum wait time in seconds
    /// - Returns: `true` if Kokoro became ready, `false` if timeout
    func waitForKokoroReady(timeout: TimeInterval) async -> Bool

    /// Synthesizes audio for a single affirmation.
    ///
    /// Routes to Kokoro or System TTS based on `config.forceSystemTTS`.
    /// Applies voice settings (speed, pitch, pitch range) from the config.
    ///
    /// - Parameters:
    ///   - text: The affirmation text to synthesize
    ///   - config: Immutable voice configuration for the session
    /// - Returns: Synthesized audio data (PCM/WAV)
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesize(text: String, config: SessionVoiceConfiguration) async throws -> Data

    /// Suppresses the synthesis idle timer during active sessions.
    ///
    /// Prevents the TTS service from releasing ML pipelines (~800MB–1.5GB)
    /// while cached audio is being played through `AudioPlayerService`.
    func suppressIdleTimer()

    /// Resumes the synthesis idle timer after session ends.
    ///
    /// Allows pipelines to auto-release after the standard 30s timeout.
    func resumeIdleTimer()
}
