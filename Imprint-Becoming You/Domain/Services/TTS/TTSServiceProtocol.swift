//
//  TTSServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech services (System TTS and ElevenLabs).
///
/// Provides a unified interface for speech synthesis, supporting both
/// on-device system TTS and cloud-based ElevenLabs voice cloning.
///
/// ## Architecture
/// ```
/// TTSServiceProtocol
/// ├── TTSService (Production)
/// │   ├── SystemTTSService (on-device)
/// │   └── ElevenLabs API (Phase 5)
/// └── MockTTSService (Testing)
/// ```
///
/// ## Usage
/// ```swift
/// // Via DependencyContainer (preferred)
/// let ttsService = dependencies.ttsService
///
/// // Speak with system voice
/// try await ttsService.speakText("I am confident", voiceId: nil)
///
/// // Stop immediately
/// ttsService.stopSpeaking()
/// ```
///
/// ## Thread Safety
/// Protocol is `@MainActor` isolated since UI updates occur during speech.
/// The underlying AVSpeechSynthesizer operations are thread-safe.
@MainActor
protocol TTSServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether speech is currently playing
    var isSpeaking: Bool { get }
    
    // MARK: - Synthesis
    
    /// Synthesizes speech for the given text and returns audio data.
    ///
    /// Use this method when you need to cache the audio or play it later.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: ElevenLabs voice ID, or nil for system TTS
    /// - Returns: Audio data (format depends on implementation)
    /// - Throws: `AppError.notImplemented` if ElevenLabs is requested but not available
    func synthesize(text: String, voiceId: String?) async throws -> Data
    
    /// Synthesizes and plays speech immediately.
    ///
    /// This is the primary method for real-time TTS playback.
    /// The method returns when speech completes or is interrupted.
    ///
    /// - Parameters:
    ///   - text: Text to speak
    ///   - voiceId: ElevenLabs voice ID, or nil for system TTS
    /// - Throws: `AppError.ttsError` if synthesis or playback fails
    func speakText(_ text: String, voiceId: String?) async throws
    
    // MARK: - Playback Control
    
    /// Stops current speech playback immediately.
    ///
    /// This method is synchronous because the underlying AVSpeechSynthesizer
    /// stop operation is immediate. Safe to call even if nothing is playing.
    func stopSpeaking()
}

// MARK: - TTS Configuration

/// Configuration options for TTS playback.
///
/// These values are tuned for affirmation delivery:
/// - Slightly slower rate for clarity and absorption
/// - Natural pitch for authenticity
enum TTSConfiguration {
    
    /// Speech rate for affirmation delivery (0.0 - 1.0)
    /// Default system rate is 0.5; we use 0.48 for slightly slower, clearer speech
    static let speechRate: Float = 0.48
    
    /// Pitch multiplier (0.5 - 2.0)
    /// 1.0 is natural pitch
    static let pitchMultiplier: Float = 1.0
    
    /// Volume (0.0 - 1.0)
    static let volume: Float = 1.0
}
