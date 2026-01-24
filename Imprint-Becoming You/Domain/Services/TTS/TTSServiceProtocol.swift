//
//  TTSServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech synthesis services.
///
/// Implemented by provider-specific services:
/// - `SystemTTSService`: iOS AVSpeechSynthesizer
/// - `KokoroTTSService`: On-device CoreML synthesis
/// - `QwenCloudTTSService`: Qwen DashScope API
///
/// ## Usage
/// ```swift
/// let voice = Voice.freeKokoroVoices.first!
/// let result = try await ttsService.synthesize(text: "Hello", voice: voice)
/// audioPlayer.play(result.audioData)
/// ```
@MainActor
protocol TTSServiceProtocol: AnyObject {
    
    // MARK: - Properties
    
    /// The provider type for this service
    var provider: VoiceProvider { get }
    
    /// Whether this service is currently available
    var isAvailable: Bool { get }
    
    /// Whether speech is currently playing
    var isSpeaking: Bool { get }
    
    // MARK: - Synthesis
    
    /// Synthesizes speech from text using the specified voice.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize (must not be empty)
    ///   - voice: Voice configuration to use
    ///   - speed: Speech rate multiplier (0.5 - 2.0, default 1.0)
    /// - Returns: Synthesis result with audio data and metadata
    /// - Throws: `TTSError` if synthesis fails
    func synthesize(text: String, voice: Voice, speed: Float) async throws -> TTSResult
    
    // MARK: - Real-Time Playback
    
    /// Synthesizes and plays speech immediately (real-time playback).
    ///
    /// This is the primary method for real-time TTS during practice sessions.
    /// The method returns when speech completes or is interrupted.
    /// For caching/offline use, use `synthesize()` instead.
    ///
    /// - Parameters:
    ///   - text: Text to speak
    ///   - voice: Voice to use (nil for default system voice)
    /// - Throws: `TTSError` if synthesis or playback fails
    func speakText(_ text: String, voice: Voice?) async throws
    
    // MARK: - Voice Management
    
    /// Returns all voices available from this provider.
    func availableVoices() -> [Voice]
    
    /// Prepares a voice for synthesis (pre-loading, caching).
    func prepareVoice(_ voice: Voice) async throws
    
    /// Checks if this service can synthesize with the given voice.
    func canSynthesize(voice: Voice) -> Bool
    
    // MARK: - Playback Control
    
    /// Stops current speech playback immediately.
    func stopSpeaking()
}

// MARK: - Default Implementations

extension TTSServiceProtocol {
    
    /// Synthesizes with default speed
    func synthesize(text: String, voice: Voice) async throws -> TTSResult {
        try await synthesize(text: text, voice: voice, speed: TTSConfiguration.defaultSpeed)
    }
    
    /// Speaks with default voice
    func speakText(_ text: String) async throws {
        try await speakText(text, voice: nil)
    }
    
    /// Default checks provider match
    func canSynthesize(voice: Voice) -> Bool {
        voice.provider == provider
    }
    
    /// Default is no-op
    func prepareVoice(_ voice: Voice) async throws {}
}

// MARK: - TTS Configuration

/// Configuration constants for text-to-speech synthesis.
enum TTSConfiguration {
    
    // MARK: - Speed Settings
    
    /// Default speech speed multiplier (1.0 = normal)
    static let defaultSpeed: Float = 1.0
    
    /// Minimum allowed speed
    static let minSpeed: Float = 0.5
    
    /// Maximum allowed speed
    static let maxSpeed: Float = 2.0
    
    /// Affirmation-optimized speech rate (slightly slower for clarity)
    static let affirmationSpeed: Float = 0.9
    
    // MARK: - System TTS Settings
    
    /// Speech rate for AVSpeechSynthesizer (0.0 - 1.0 scale)
    /// 0.5 is normal, 0.48 is slightly slower for clarity
    static let speechRate: Float = 0.48
    
    /// Pitch multiplier for AVSpeechSynthesizer
    /// Range: 0.5 (low) to 2.0 (high), 1.0 is natural
    static let pitchMultiplier: Float = 1.0
    
    // MARK: - Audio Settings
    
    /// Default pitch (1.0 = normal)
    static let defaultPitch: Float = 1.0
    
    /// Default volume (0.0 - 1.0)
    static let defaultVolume: Float = 1.0
    
    // MARK: - Kokoro Settings
    
    /// Sample rate for Kokoro synthesis (24kHz)
    static let kokoroSampleRate: Int = 24000
    
    /// Default language code
    static let defaultLanguageCode: String = "en-US"
    
    // MARK: - Caching
    
    /// Whether to cache synthesized audio
    static let enableCaching: Bool = true
    
    /// Pre-warm voices on app launch
    static let preWarmVoices: Bool = true
    
    // MARK: - Timeouts
    
    /// Maximum time to wait for synthesis (seconds)
    static let synthesisTimeout: TimeInterval = 30.0
    
    /// Maximum time to wait for voice preparation (seconds)
    static let voicePreparationTimeout: TimeInterval = 10.0
}

// MARK: - TTS Synthesis Options

/// Fine-grained control over synthesis behavior.
struct TTSSynthesisOptions: Sendable {
    let speed: Float
    let pitch: Float
    let volume: Float
    let includeWordTimings: Bool
    let preferredFormat: TTSAudioFormat?
    
    init(
        speed: Float = 1.0,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        includeWordTimings: Bool = true,
        preferredFormat: TTSAudioFormat? = nil
    ) {
        self.speed = max(TTSConfiguration.minSpeed, min(TTSConfiguration.maxSpeed, speed))
        self.pitch = max(0.5, min(2.0, pitch))
        self.volume = max(0.0, min(1.0, volume))
        self.includeWordTimings = includeWordTimings
        self.preferredFormat = preferredFormat
    }
    
    static let `default` = TTSSynthesisOptions()
    static let meditation = TTSSynthesisOptions(speed: 0.8, pitch: 0.95, volume: 0.9)
    static let energetic = TTSSynthesisOptions(speed: 1.1, pitch: 1.05, volume: 1.0)
}
