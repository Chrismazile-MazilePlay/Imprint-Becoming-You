//
//  TTSSynthesisEngine.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/5/26.
//

import Foundation

// MARK: - TTS Synthesis Engine

/// Production implementation of `TTSSynthesisEngineProtocol`.
///
/// Wraps `TTSServiceProtocol` to provide a focused synthesis interface
/// for `SessionTTSQueueService`. Delegates all calls to the underlying
/// TTS service.
///
/// ## Thread Safety
/// All state is `@MainActor` isolated, matching `SessionTTSQueueService`.
@MainActor
final class TTSSynthesisEngine: TTSSynthesisEngineProtocol {

    // MARK: - Dependencies

    /// The underlying TTS service for synthesis operations
    private let ttsService: any TTSServiceProtocol

    // MARK: - Initialization

    /// Creates a synthesis engine wrapping the given TTS service.
    ///
    /// - Parameter ttsService: The TTS service to delegate synthesis to
    init(ttsService: any TTSServiceProtocol) {
        self.ttsService = ttsService
    }

    // MARK: - TTSSynthesisEngineProtocol

    var isKokoroReady: Bool {
        ttsService.isKokoroReady
    }

    func waitForKokoroReady(timeout: TimeInterval) async -> Bool {
        // Return immediately if already ready
        if ttsService.isKokoroReady {
            return true
        }

        // Poll for readiness
        let startTime = Date()
        let checkInterval: Duration = .milliseconds(100)

        while Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(for: checkInterval)

            if ttsService.isKokoroReady {
                return true
            }

            // Check if cancelled
            if Task.isCancelled {
                return false
            }
        }

        return false
    }

    func synthesize(text: String, config: SessionVoiceConfiguration) async throws -> Data {
        if config.forceSystemTTS {
            return try await ttsService.synthesizeWithSystemTTS(text: text)
        } else {
            return try await ttsService.synthesize(
                text: text,
                voiceId: config.voiceId,
                speed: config.voiceSettings.speed,
                pitchShiftSemitones: config.voiceSettings.pitchShiftFloat,
                pitchRangeScale: config.voiceSettings.pitchRangeScale
            )
        }
    }

    func suppressIdleTimer() {
        ttsService.suppressSynthesisIdleTimer()
    }

    func resumeIdleTimer() {
        ttsService.resumeSynthesisIdleTimer()
    }
}
