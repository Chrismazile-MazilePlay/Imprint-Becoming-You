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
/// // Speak with default Kokoro voice
/// try await ttsService.speakText("I am confident", voiceId: nil)
///
/// // Speak with specific Kokoro voice
/// try await ttsService.speakText("I am capable", voiceId: "kokoro_amAdam")
///
/// // Force system TTS
/// try await ttsService.speakText("Hello", voiceId: "system")
/// ```
@MainActor
protocol TTSServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether speech is currently playing
    var isSpeaking: Bool { get }
    
    /// Whether Kokoro engine is ready
    var isKokoroReady: Bool { get }
    
    // MARK: - Initialization
    
    /// Warms up the Kokoro TTS engine.
    ///
    /// Call this at app launch to reduce first-synthesis latency.
    /// Safe to call multiple times - subsequent calls are no-ops.
    ///
    /// If warm-up fails, the service falls back to System TTS automatically.
    func warmUp() async
    
    // MARK: - Synthesis
    
    /// Synthesizes speech for the given text and returns audio data.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: Voice ID (nil for default Kokoro, "system" for AVSpeech)
    /// - Returns: Audio data (WAV format)
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesize(text: String, voiceId: String?) async throws -> Data
    
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
    
    /// Default Kokoro voice ID
    static let defaultVoiceId = "kokoro_afHeart"
}
