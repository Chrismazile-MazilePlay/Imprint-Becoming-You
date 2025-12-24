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
/// Uses on-device system TTS for basic speech synthesis.
/// ElevenLabs cloud TTS will be added in Phase 5.
///
/// ## Architecture
/// ```
/// TTSService
/// ├── SystemTTSService (on-device synthesis)
/// └── AudioCacheManager (caching for ElevenLabs)
/// ```
final class TTSService: TTSServiceProtocol, @unchecked Sendable {
    
    // MARK: - Dependencies
    
    /// System TTS service for offline speech
    private let systemTTS: SystemTTSService
    
    /// Audio cache manager for ElevenLabs audio
    private let cacheManager: AudioCacheManager
    
    // MARK: - Initialization
    
    /// Creates a new TTS service with default dependencies
    init() {
        self.systemTTS = SystemTTSService()
        self.cacheManager = AudioCacheManager.shared
    }
    
    /// Creates a TTS service with injected dependencies (for testing)
    /// - Parameters:
    ///   - systemTTS: System TTS service instance
    ///   - cacheManager: Audio cache manager instance
    init(systemTTS: SystemTTSService, cacheManager: AudioCacheManager) {
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
    
    func stopSpeaking() async {
        systemTTS.stopSpeaking()
    }
}
