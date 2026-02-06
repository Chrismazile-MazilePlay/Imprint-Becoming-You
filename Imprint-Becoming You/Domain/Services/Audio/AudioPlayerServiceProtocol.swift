//
//  AudioPlayerServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - Audio Player Service Protocol

/// Consumer-facing interface for TTS audio playback.
///
/// Extracts the playback surface area used by `SessionPlaybackCoordinator`
/// from the concrete `AudioPlayerService` actor. This decouples playback
/// consumers from the implementation, enabling mock injection for tests.
///
/// ## Responsibilities
/// - Raw PCM and encoded audio playback
/// - Immediate and graceful stop semantics
/// - Volume, pause, and resume control
/// - Playback progress tracking
///
/// ## Architecture
/// ```
/// AudioPlayerServiceProtocol
/// ├── AudioPlayerService (Production — actor)
/// └── MockAudioPlayerService (Testing)
/// ```
///
/// ## Thread Safety
/// All methods are actor-isolated in the production implementation.
/// `immediateStop()` is the sole `nonisolated` method — it uses
/// `OSAllocatedUnfairLock` for safe synchronous cross-isolation access.
protocol AudioPlayerServiceProtocol: AnyObject, Sendable {

    // MARK: - Playback

    /// Plays raw PCM audio data (Kokoro TTS output format).
    ///
    /// Handles audio session configuration, player setup, and awaits
    /// playback completion. Stops any in-progress playback first.
    ///
    /// - Parameters:
    ///   - data: Audio data (WAV format from Kokoro TTS)
    ///   - sampleRate: Sample rate (default 24000 Hz)
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playRawPCMData(_ data: Data, sampleRate: Double) async throws

    /// Plays encoded audio data (e.g., MP3).
    ///
    /// Writes data to a temporary file, plays via `AVAudioEngine`,
    /// and cleans up after completion.
    ///
    /// - Parameter data: Encoded audio data
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playData(_ data: Data) async throws

    // MARK: - Stop

    /// Immediately silences audio from any isolation context.
    ///
    /// Bypasses actor isolation to stop `AVAudioPlayer` synchronously,
    /// eliminating audible bleed when exiting sessions or transitioning.
    /// Always follow with an actor-isolated `cancelAndStop()` or `stop()`
    /// to clean up continuations.
    ///
    /// - Note: `nonisolated` — safe to call from any thread.
    nonisolated func immediateStop()

    /// Atomically silences audio, stops playback, and resolves all
    /// pending continuations with `CancellationError`.
    ///
    /// Use for session exit and segment transitions where callers
    /// need to distinguish cancellation from successful completion.
    func cancelAndStop() async

    /// Stops playback and resolves pending continuations with success.
    ///
    /// Use for clean shutdown paths where callers should complete
    /// normally rather than receiving a cancellation error.
    func stop() async

    // MARK: - Playback Control

    /// Pauses active playback.
    func pause() async

    /// Resumes paused playback.
    func resume() async

    /// Sets the playback volume.
    ///
    /// - Parameter newVolume: Volume level (0.0 - 1.0, clamped)
    func setVolume(_ newVolume: Float) async

    // MARK: - Playback Info

    /// Whether playback is currently active.
    var isPlaying: Bool { get async }

    /// Whether playback is paused.
    var isPaused: Bool { get async }

    /// Current playback position in seconds.
    var currentTime: TimeInterval { get async }

    /// Total duration of current audio in seconds.
    var duration: TimeInterval { get async }

    /// Playback progress (0.0 - 1.0).
    var progress: Double { get async }
}
