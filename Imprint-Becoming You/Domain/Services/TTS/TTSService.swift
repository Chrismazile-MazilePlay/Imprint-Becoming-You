//
//  TTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - TTS Service

/// Production implementation of text-to-speech service.
///
/// Integrates on-device system TTS with future ElevenLabs cloud TTS.
/// Configured with optimal settings for affirmation delivery.
///
/// ## Architecture
/// ```
/// TTSService
/// ├── SystemTTSService (on-device synthesis)
/// └── AudioCacheManager (caching for ElevenLabs - Phase 5)
/// ```
///
/// ## Configuration
/// Speech rate and pitch are configured at initialization using
/// `TTSConfiguration` values, optimized for clear affirmation delivery.
///
/// ## Usage
/// ```swift
/// // Access via DependencyContainer (preferred)
/// let tts = dependencies.ttsService
/// try await tts.speakText("I am confident and capable", voiceId: nil)
/// ```
@MainActor
final class TTSService: TTSServiceProtocol {
    
    // MARK: - Dependencies
    
    /// System TTS service for on-device speech synthesis
    private let systemTTS: SystemTTSService
    
    /// Audio cache manager for ElevenLabs audio (Phase 5)
    private let cacheManager: AudioCacheManager
    
    // MARK: - Initialization
    
    /// Creates a new TTS service with default dependencies.
    ///
    /// Configures SystemTTSService with optimal settings for affirmation delivery:
    /// - Speech rate: 0.48 (slightly slower for clarity)
    /// - Pitch: 1.0 (natural)
    init() {
        let systemTTS = SystemTTSService()
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        
        self.systemTTS = systemTTS
        self.cacheManager = AudioCacheManager.shared
    }
    
    /// Creates a TTS service with injected dependencies (for testing).
    ///
    /// - Parameters:
    ///   - systemTTS: System TTS service instance (will be configured)
    ///   - cacheManager: Audio cache manager instance
    init(systemTTS: SystemTTSService, cacheManager: AudioCacheManager) {
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        
        self.systemTTS = systemTTS
        self.cacheManager = cacheManager
    }
    
    // MARK: - TTSServiceProtocol
    
    var isSpeaking: Bool {
        systemTTS.isSpeaking
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        // If voiceId is provided, use ElevenLabs (Phase 5)
        if let voiceId = voiceId {
            // Check cache first
            if let cachedData = await cacheManager.getCachedAudio(forText: text, voiceId: voiceId) {
                return cachedData
            }
            
            // TODO: Phase 5 - ElevenLabs API call
            throw AppError.notImplemented(feature: "ElevenLabs TTS")
        }
        
        // Use system TTS
        return try await systemTTS.synthesizeToData(text)
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        // If voiceId is provided, use ElevenLabs (Phase 5)
        if voiceId != nil {
            throw AppError.notImplemented(feature: "ElevenLabs TTS Playback")
        }
        
        // Use system TTS
        try await systemTTS.speak(text)
    }
    
    func stopSpeaking() {
        systemTTS.stopSpeaking()
    }
}
