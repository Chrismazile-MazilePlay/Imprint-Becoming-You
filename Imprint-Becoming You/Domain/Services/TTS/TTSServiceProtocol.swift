//
//  TTSServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech services.
///
/// Provides a unified interface for speech synthesis, supporting:
/// - Kokoro on-device neural TTS (primary, high quality)
/// - System AVSpeechSynthesizer (fallback, always available)
/// - Cloud TTS with voice cloning (future Phase 7)
///
/// ## Voice ID Routing
/// - `nil` or empty: Uses default Kokoro voice (afHeart)
/// - `kokoro_*`: Uses Kokoro neural TTS
/// - `system`: Uses System AVSpeechSynthesizer
/// - Other: Reserved for future cloud voices
///
/// ## Pre-Synthesis
/// Use `preSynthesize()` to prepare audio in advance,
/// reducing latency for sequential playback.
///
/// ## Architecture
/// ```
/// TTSServiceProtocol
/// ├── TTSService (Production)
/// │   ├── KokoroTTSEngine (primary - neural TTS)
/// │   └── SystemTTSService (fallback)
/// └── MockTTSService (Testing)
/// ```
///
/// ## Usage
/// ```swift
/// let ttsService = dependencies.ttsService
///
/// // Warm up at app launch
/// await ttsService.warmUp()
///
/// // Check if Kokoro is ready before session
/// if ttsService.isKokoroReady {
///     // Proceed with neural TTS
/// }
///
/// // Speak with default Kokoro voice
/// try await ttsService.speakText("I am confident", voiceId: nil)
///
/// // Speak with specific Kokoro voice
/// try await ttsService.speakText("I am capable", voiceId: "af_heart")
///
/// // Force system TTS
/// try await ttsService.speakText("Hello", voiceId: "system")
/// ```
@MainActor
protocol TTSServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether speech is currently playing
    var isSpeaking: Bool { get }
    
    /// Whether Kokoro engine is ready for synthesis.
    ///
    /// Check this before starting a session to determine if
    /// the session preparation screen should wait for warm-up.
    var isKokoroReady: Bool { get }
    
    // MARK: - Initialization
    
    /// Warms up the Kokoro TTS engine.
    ///
    /// Call this at app launch to reduce first-synthesis latency.
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// If warm-up fails, the service falls back to System TTS automatically.
    /// Posts `Constants.NotificationNames.kokoroTTSReady` when complete.
    func warmUp() async
    
    /// Retries Kokoro initialization after a failure.
    ///
    /// Call this when:
    /// - User taps "Retry" in session preparation fallback UI
    /// - Warm-up timed out and user wants to try again
    ///
    /// This resets the internal Kokoro state and attempts warm-up again.
    /// Posts `Constants.NotificationNames.kokoroTTSReady` when complete.
    func retryKokoroInitialization() async
    
    // MARK: - Synthesis
    
    /// Synthesizes speech for the given text and returns audio data.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: Voice ID (nil for default Kokoro, "system" for AVSpeech)
    /// - Returns: Audio data (WAV format)
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesize(text: String, voiceId: String?) async throws -> Data
    
    /// Synthesizes speech using System TTS regardless of Kokoro state.
    ///
    /// Use this when user explicitly chooses "Continue with System Voice"
    /// in the session preparation fallback UI.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    /// - Returns: Audio data (WAV format)
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesizeWithSystemTTS(text: String) async throws -> Data
    
    /// Synthesizes and plays speech immediately.
    ///
    /// - Parameters:
    ///   - text: Text to speak
    ///   - voiceId: Voice ID (nil for default Kokoro, "system" for AVSpeech)
    /// - Throws: `AppError.ttsError` if synthesis or playback fails
    func speakText(_ text: String, voiceId: String?) async throws
    
    // MARK: - Playback Control
    
    /// Stops current speech playback immediately.
    func stopSpeaking()
    
    // MARK: - Pre-Synthesis
    
    /// Pre-synthesizes text for faster subsequent playback.
    ///
    /// Call this to prepare the next affirmation while the current one
    /// is playing. The result is cached for instant playback.
    ///
    /// - Parameters:
    ///   - text: The text to pre-synthesize
    ///   - voiceId: Optional voice ID
    func preSynthesize(text: String, voiceId: String?) async
    
    /// Cancels any active pre-synthesis task.
    func cancelPreSynthesis()
}

// MARK: - Default Implementations

extension TTSServiceProtocol {
    
    /// Default implementation for pre-synthesis (synthesize and cache)
    func preSynthesize(text: String, voiceId: String?) async {
        // Default: synthesize and let cache handle it
        _ = try? await synthesize(text: text, voiceId: voiceId)
    }
    
    /// Default implementation for cancel (no-op for simple services)
    func cancelPreSynthesis() {
        // Default: no-op
    }
    
    /// Default implementation for retry (just call warmUp again)
    func retryKokoroInitialization() async {
        await warmUp()
    }
    
    /// Default implementation for system TTS fallback
    func synthesizeWithSystemTTS(text: String) async throws -> Data {
        // Default: use regular synthesize with system voice
        return try await synthesize(text: text, voiceId: TTSConfiguration.systemVoiceId)
    }
}

// MARK: - TTS Configuration

/// Configuration options for TTS playback.
enum TTSConfiguration {
    
    // MARK: - System TTS Settings
    
    /// Speech rate for System TTS (0.0 - 1.0)
    static let speechRate: Float = 0.48
    
    /// Pitch multiplier for System TTS (0.5 - 2.0)
    static let pitchMultiplier: Float = 1.0
    
    /// Volume (0.0 - 1.0)
    static let volume: Float = 1.0
    
    // MARK: - Kokoro TTS Settings
    
    /// Default speed for Kokoro TTS (0.5 - 2.0)
    static let kokoroSpeed: Float = 1.0
    
    /// Kokoro output sample rate (24kHz)
    static let kokoroSampleRate: Int = 24000
    
    // MARK: - Voice ID Constants
    
    /// Voice ID prefix for Kokoro voices
    static let kokoroPrefix = "kokoro_"
    
    /// Voice ID for system TTS
    static let systemVoiceId = "system"
    
    /// Default Kokoro voice ID (raw form for TTS engine)
    static let defaultVoiceId = "af_heart"
}
