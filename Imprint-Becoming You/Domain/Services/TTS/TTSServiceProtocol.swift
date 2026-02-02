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
/// ## Voice ID Format
/// Use full Voice.id format throughout the app (e.g., "kokoro_af_heart").
/// The service handles conversion to raw TTS engine format internally.
/// - `nil` or empty: Uses default Kokoro voice (af_heart)
/// - `kokoro_*`: Uses Kokoro neural TTS
/// - `system`: Uses System AVSpeechSynthesizer
/// - Other: Reserved for future cloud voices
///
/// ## Voice Settings
/// Pass `speed`, `pitchShiftSemitones`, and `pitchRangeScale` parameters
/// to apply user-customized voice settings during synthesis.
///
/// ## Pre-Synthesis
/// Use `preSynthesize()` to prepare audio in advance,
/// reducing latency for sequential playback.
///
/// ## Memory Management
/// Use `releaseForBackground()` when app enters background to free ML models.
/// Call `warmUp()` again when returning to foreground.
///
/// ## Architecture
/// ```
/// TTSServiceProtocol
/// +-- TTSService (Production)
/// |   +-- KokoroTTSEngine (primary - neural TTS)
/// |   +-- SystemTTSService (fallback)
/// +-- MockTTSService (Testing)
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
/// // Speak with default settings
/// try await ttsService.speakText("I am confident", voiceId: nil)
///
/// // Speak with voice settings
/// try await ttsService.speakText(
///     "I am capable",
///     voiceId: "kokoro_af_heart",
///     speed: 0.9,
///     pitchShiftSemitones: 2.0,
///     pitchRangeScale: 1.2
/// )
///
/// // Force system TTS
/// try await ttsService.speakText("Hello", voiceId: "system")
///
/// // When entering background (memory management)
/// await ttsService.releaseForBackground()
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
    ///   - voiceId: Voice ID in full format (e.g., "kokoro_af_heart"), nil for default
    ///   - speed: Playback speed multiplier (0.5 - 2.0, default 1.0)
    ///   - pitchShiftSemitones: Pitch shift in semitones (-12 to +12, default 0)
    ///   - pitchRangeScale: Pitch variation scale (0.5 - 1.5, default 1.0)
    /// - Returns: Audio data (WAV format)
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws -> Data
    
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
    ///   - voiceId: Voice ID in full format (e.g., "kokoro_af_heart"), nil for default
    ///   - speed: Playback speed multiplier (0.5 - 2.0, default 1.0)
    ///   - pitchShiftSemitones: Pitch shift in semitones (-12 to +12, default 0)
    ///   - pitchRangeScale: Pitch variation scale (0.5 - 1.5, default 1.0)
    /// - Throws: `AppError.ttsError` if synthesis or playback fails
    func speakText(
        _ text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws
    
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
    ///   - voiceId: Voice ID in full format (e.g., "kokoro_af_heart"), nil for default
    ///   - speed: Playback speed multiplier (0.5 - 2.0, default 1.0)
    ///   - pitchShiftSemitones: Pitch shift in semitones (-12 to +12, default 0)
    ///   - pitchRangeScale: Pitch variation scale (0.5 - 1.5, default 1.0)
    func preSynthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async
    
    /// Cancels any active pre-synthesis task.
    func cancelPreSynthesis()
    
    // MARK: - Memory Management
    
    /// Releases heavy resources (ML models) to free memory.
    ///
    /// Call when:
    /// - App enters background for extended period (>5 min)
    /// - iOS sends memory warning
    ///
    /// After calling this, `isKokoroReady` returns `false` and
    /// synthesis will fall back to System TTS until `warmUp()` is called again.
    ///
    /// This can free ~500MB-1GB of memory from Kokoro ML pipelines.
    func releaseForBackground() async
}

// MARK: - Convenience Extensions

extension TTSServiceProtocol {
    
    /// Synthesizes speech with default voice settings.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: Voice ID (nil for default Kokoro, "system" for AVSpeech)
    /// - Returns: Audio data (WAV format)
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        try await synthesize(
            text: text,
            voiceId: voiceId,
            speed: TTSConfiguration.defaultSpeed,
            pitchShiftSemitones: TTSConfiguration.defaultPitchShift,
            pitchRangeScale: TTSConfiguration.defaultPitchRange
        )
    }
    
    /// Speaks text with default voice settings.
    ///
    /// - Parameters:
    ///   - text: Text to speak
    ///   - voiceId: Voice ID (nil for default Kokoro, "system" for AVSpeech)
    func speakText(_ text: String, voiceId: String?) async throws {
        try await speakText(
            text,
            voiceId: voiceId,
            speed: TTSConfiguration.defaultSpeed,
            pitchShiftSemitones: TTSConfiguration.defaultPitchShift,
            pitchRangeScale: TTSConfiguration.defaultPitchRange
        )
    }
    
    /// Pre-synthesizes text with default voice settings.
    ///
    /// - Parameters:
    ///   - text: The text to pre-synthesize
    ///   - voiceId: Voice ID (nil for default Kokoro, "system" for AVSpeech)
    func preSynthesize(text: String, voiceId: String?) async {
        await preSynthesize(
            text: text,
            voiceId: voiceId,
            speed: TTSConfiguration.defaultSpeed,
            pitchShiftSemitones: TTSConfiguration.defaultPitchShift,
            pitchRangeScale: TTSConfiguration.defaultPitchRange
        )
    }
}

// MARK: - Default Implementations

extension TTSServiceProtocol {
    
    /// Default implementation for pre-synthesis (synthesize and cache)
    func preSynthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async {
        // Default: synthesize and let cache handle it
        _ = try? await synthesize(
            text: text,
            voiceId: voiceId,
            speed: speed,
            pitchShiftSemitones: pitchShiftSemitones,
            pitchRangeScale: pitchRangeScale
        )
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
    
    /// Default implementation for background release (no-op for mocks)
    func releaseForBackground() async {
        // Default: no-op for mock services
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
    
    // MARK: - Voice Settings Defaults
    
    /// Default speed (1.0 = normal speed)
    static let defaultSpeed: Float = 1.0
    
    /// Default pitch shift (0 = no shift)
    static let defaultPitchShift: Float = 0.0
    
    /// Default pitch range scale (1.0 = normal expressiveness)
    static let defaultPitchRange: Float = 1.0
    
    // MARK: - Voice ID Constants
    
    /// Voice ID prefix for Kokoro voices
    static let kokoroPrefix = "kokoro_"
    
    /// Voice ID for system TTS
    static let systemVoiceId = "system"
    
    /// Default Kokoro voice ID (raw form for TTS engine)
    static let defaultVoiceId = "af_heart"
}
