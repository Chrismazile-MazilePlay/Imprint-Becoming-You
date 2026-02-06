//
//  SessionPlaybackCoordinator.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/5/26.
//

import Foundation
import AVFoundation

// MARK: - Session Playback Coordinator

/// Coordinates TTS audio playback for practice sessions.
///
/// Encapsulates `speakText()` and `stopTTSPlayback()` logic previously
/// embedded in `PracticeStore+FlowExecution.swift`, providing a focused
/// interface for audio playback management.
///
/// ## Index Capture
/// The affirmation `index` is passed as an explicit parameter at call site,
/// making the entire async chain immune to concurrent `sessionIndex` mutations
/// caused by rapid skipping. The coordinator never reads `sessionIndex` from
/// the store — it only uses the passed-in value.
///
/// ## Playback Chain
/// ```
/// 1. Check queue cache (instant)
/// 2. Try on-demand synthesis (1-2s)
/// 3. Fallback to direct TTS service (last resort)
/// ```
///
/// ## Stop Behavior
/// Uses a two-phase stop:
/// 1. `immediateStop()` — synchronous, nonisolated. Zeros volume instantly.
/// 2. Fire-and-forget `stop()` — resolves pending continuations on the actor.
///
/// ## Thread Safety
/// All methods are `@MainActor` isolated, matching `PracticeStore`.
@MainActor
final class SessionPlaybackCoordinator {

    // MARK: - Dependencies

    /// Queue service for cached audio retrieval and on-demand synthesis
    private let queueService: any SessionTTSQueueServiceProtocol

    /// Audio player for raw PCM playback
    private let audioPlayerService: any AudioPlayerServiceProtocol

    /// TTS service for fallback direct synthesis (browse mode / cache miss)
    private let ttsService: any TTSServiceProtocol

    // MARK: - Initialization

    /// Creates a playback coordinator with the required services.
    ///
    /// - Parameters:
    ///   - queueService: Session TTS queue for cached audio
    ///   - audioPlayerService: Audio player for PCM playback
    ///   - ttsService: TTS service for fallback synthesis
    init(
        queueService: any SessionTTSQueueServiceProtocol,
        audioPlayerService: any AudioPlayerServiceProtocol,
        ttsService: any TTSServiceProtocol
    ) {
        self.queueService = queueService
        self.audioPlayerService = audioPlayerService
        self.ttsService = ttsService
    }

    // MARK: - Playback

    /// Plays audio for a specific affirmation at the given index.
    ///
    /// The `index` and `affirmationID` parameters are captured atomically at the
    /// call site, making this method immune to concurrent `sessionIndex` mutations
    /// from rapid skipping.
    ///
    /// Playback chain:
    /// 1. Check queue cache for pre-synthesized audio by UUID (instant)
    /// 2. Synthesize on-demand if not cached (1-2s delay)
    /// 3. Fall back to direct TTS service if both fail
    ///
    /// - Parameters:
    ///   - index: The affirmation index in the session (captured at call site)
    ///   - affirmationID: The affirmation's UUID for cache lookup
    ///   - text: The affirmation text (for fallback synthesis)
    ///   - isSessionActive: Whether a session is currently active
    ///   - selectedVoiceId: The voice ID for fallback TTS
    /// - Throws: `TTSError` if all synthesis paths fail
    func playAffirmation(
        index: Int,
        affirmationID: UUID,
        text: String,
        isSessionActive: Bool,
        selectedVoiceId: String?
    ) async throws {
        // Notify queue of current playback position
        if isSessionActive {
            queueService.notifyPlaying(index: index)
        }

        // Try to get cached audio first (keyed by affirmation UUID)
        if isSessionActive, let cachedAudio = queueService.getAudio(for: affirmationID) {
            AppLogger.debug(
                "Playing cached audio",
                category: .tts,
                context: ["index": index]
            )

            // Play raw PCM Float32 data at 24000 Hz (Kokoro TTS output format)
            try await audioPlayerService.playRawPCMData(cachedAudio, sampleRate: 24000)
            return
        }

        // Try on-demand synthesis if in session
        if isSessionActive {
            AppLogger.debug(
                "On-demand synthesis",
                category: .tts,
                context: ["index": index]
            )

            do {
                let audioData = try await queueService.synthesizeOnDemand(index: index)
                // Play raw PCM Float32 data at 24000 Hz (Kokoro TTS output format)
                try await audioPlayerService.playRawPCMData(audioData, sampleRate: 24000)
                return
            } catch {
                AppLogger.warning(
                    "On-demand synthesis failed, falling back to TTS service",
                    category: .tts,
                    context: ["index": index]
                )
                // Fall through to direct TTS
            }
        }

        // Fallback: Direct TTS synthesis (browse mode or cache miss)
        try await ttsService.speakText(text, voiceId: selectedVoiceId)
    }

    /// Stops any ongoing TTS playback immediately.
    ///
    /// Uses a two-phase stop:
    /// 1. `immediateStop()` — synchronous, nonisolated. Zeros volume and stops
    ///    the AVAudioPlayer via OSAllocatedUnfairLock. Guarantees silence within
    ///    the current run loop turn, even if the actor is busy.
    /// 2. Fire-and-forget `stop()` — resolves pending continuations on the actor
    ///    so `playAffirmation()`'s `try await playRawPCMData()` returns cleanly.
    func stopPlayback() {
        ttsService.stopSpeaking()
        audioPlayerService.immediateStop()
        Task { [weak self] in
            await self?.audioPlayerService.stop()
        }
    }

    // MARK: - Audio Session Management

    /// Pre-configures the audio session to `.playback` category.
    ///
    /// Call during loop transitions to eliminate the 50-200ms HAL
    /// reconfiguration delay that would otherwise occur in `playRawPCMData()`.
    ///
    /// When `playRawPCMData()` → `ensurePlaybackCategory()` runs after this,
    /// the category is already `.playback` → only `setActive(true)` (~1-5ms).
    func preConfigureAudioSession() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                do {
                    if session.category != .playback {
                        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                    }
                    try session.setActive(true)
                } catch {
                    #if DEBUG
                    AppLogger.debug("Audio session pre-config failed: \(error.localizedDescription)", category: .audio)
                    #endif
                }
                continuation.resume()
            }
        }
    }
}
