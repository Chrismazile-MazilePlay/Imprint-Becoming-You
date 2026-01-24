//
//  TTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation
import AVFoundation

// MARK: - TTS Service

/// Production implementation of text-to-speech service.
///
/// ## Current Implementation
/// Uses iOS system TTS (AVSpeechSynthesizer) as the default provider.
/// Kokoro on-device TTS will be added in Phase 4.
///
/// ## Architecture
/// ```
/// TTSService
/// ├── SystemTTSService (on-device AVSpeechSynthesizer)
/// ├── AudioCacheManager (caching synthesized audio)
/// └── Future: KokoroTTSEngine (on-device neural TTS)
/// ```
///
/// ## Usage
/// ```swift
/// let tts = dependencies.ttsService
///
/// // Real-time playback (for practice sessions)
/// try await tts.speakText("I am confident and capable")
///
/// // Synthesis with caching (for offline use)
/// let result = try await tts.synthesize(
///     text: "I am confident",
///     voice: Voice.defaultVoice,
///     speed: 1.0
/// )
/// ```
@MainActor
final class TTSService: TTSServiceProtocol {
    
    // MARK: - Properties
    
    let provider: VoiceProvider = .system  // Will change to .kokoro in Phase 4
    
    var isAvailable: Bool {
        // System TTS is always available on iOS
        true
    }
    
    var isSpeaking: Bool {
        systemTTS.isSpeaking
    }
    
    // MARK: - Dependencies
    
    /// System TTS service for on-device speech synthesis
    private let systemTTS: SystemTTSService
    
    /// Audio cache manager
    private let cacheManager: AudioCacheManager
    
    // MARK: - Initialization
    
    /// Creates a new TTS service with default dependencies.
    init() {
        let systemTTS = SystemTTSService()
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        
        self.systemTTS = systemTTS
        self.cacheManager = AudioCacheManager.shared
    }
    
    /// Creates a TTS service with injected dependencies (for testing).
    init(systemTTS: SystemTTSService, cacheManager: AudioCacheManager) {
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        
        self.systemTTS = systemTTS
        self.cacheManager = cacheManager
    }
    
    // MARK: - TTSServiceProtocol - Real-Time Playback
    
    func speakText(_ text: String, voice: Voice?) async throws {
        // For system TTS, use direct speak() method for real-time playback
        // This uses AVSpeechSynthesizer.speak() which plays audio directly
        // and properly handles the audio session
        try await systemTTS.speak(text)
    }
    
    // MARK: - TTSServiceProtocol - Synthesis
    
    func synthesize(text: String, voice: Voice, speed: Float) async throws -> TTSResult {
        // Check cache first
        let cacheKey = cacheManager.cacheKey(for: text, voice: voice, speed: speed)
        if let cached = await cacheManager.get(key: cacheKey) {
            return cached
        }
        
        // Route to appropriate synthesizer based on voice provider
        let result: TTSResult
        
        switch voice.provider {
        case .system:
            result = try await synthesizeWithSystem(text: text, voice: voice, speed: speed)
            
        case .kokoro:
            // TODO: Phase 4 - Kokoro CoreML integration
            // For now, fall back to system TTS
            result = try await synthesizeWithSystem(text: text, voice: voice, speed: speed)
            
        case .qwenCloud:
            // TODO: Phase 7 - Qwen cloud integration
            throw TTSError.voiceNotAvailable(voiceId: voice.id)
        }
        
        // Cache the result (ignore errors - caching is non-critical)
        if TTSConfiguration.enableCaching {
            _ = try? await cacheManager.store(key: cacheKey, result: result)
        }
        
        return result
    }
    
    func availableVoices() -> [Voice] {
        // For now, return system voices
        // Phase 4 will add Kokoro voices
        var voices: [Voice] = []
        
        // Add available system voices
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        for avVoice in systemVoices where avVoice.language.starts(with: "en") {
            voices.append(Voice.systemVoice(
                identifier: avVoice.identifier,
                name: avVoice.name,
                languageCode: avVoice.language
            ))
        }
        
        return voices
    }
    
    func prepareVoice(_ voice: Voice) async throws {
        // System voices don't need preparation
        // Kokoro voices will need model loading (Phase 4)
        switch voice.provider {
        case .system:
            // No-op for system voices
            break
            
        case .kokoro:
            // TODO: Phase 4 - Load Kokoro model if not loaded
            break
            
        case .qwenCloud:
            // Cloud voices don't need local preparation
            break
        }
    }
    
    func canSynthesize(voice: Voice) -> Bool {
        switch voice.provider {
        case .system:
            // Extract system identifier from Voice.id (strips "system_" prefix)
            if let identifier = extractSystemVoiceIdentifier(from: voice) {
                return AVSpeechSynthesisVoice(identifier: identifier) != nil
            }
            return true  // Default system voice always available
            
        case .kokoro:
            // TODO: Phase 4 - Check if Kokoro model is available
            return false  // Not yet implemented
            
        case .qwenCloud:
            // TODO: Phase 7 - Check network and subscription
            return false  // Not yet implemented
        }
    }
    
    func stopSpeaking() {
        systemTTS.stopSpeaking()
    }
    
    // MARK: - Private Methods
    
    /// Extracts the AVSpeechSynthesisVoice identifier from a Voice.
    ///
    /// System voices have IDs like "system_com.apple.ttsbundle.Samantha-compact"
    /// This extracts "com.apple.ttsbundle.Samantha-compact"
    private func extractSystemVoiceIdentifier(from voice: Voice) -> String? {
        guard voice.provider == .system else { return nil }
        
        let prefix = "system_"
        if voice.id.hasPrefix(prefix) {
            return String(voice.id.dropFirst(prefix.count))
        }
        return voice.id
    }
    
    /// Synthesizes text using system TTS (AVSpeechSynthesizer)
    private func synthesizeWithSystem(text: String, voice: Voice, speed: Float) async throws -> TTSResult {
        // Configure system TTS speech rate
        systemTTS.speechRate = TTSConfiguration.speechRate * speed
        
        // Note: SystemTTSService uses its internal selectedVoice.
        // For custom voice selection, we would need to extend SystemTTSService
        // to accept a voice identifier. For now, use default enhanced voice.
        
        // Synthesize to audio data
        let startTime = Date()
        let audioData = try await systemTTS.synthesizeToData(text)
        let duration = estimateDuration(for: text, speed: speed)
        
        return TTSResult(
            audioData: audioData,
            audioFormat: .linearPCM,
            duration: duration,
            originalText: text,
            voice: voice,
            wordTimings: [],  // System TTS doesn't provide word timings via this API
            source: .synthesized,
            synthesizedAt: startTime
        )
    }
    
    /// Estimates speech duration based on text length and speed
    private func estimateDuration(for text: String, speed: Float) -> TimeInterval {
        // Rough estimate: ~150 words per minute at normal speed
        let wordCount = text.split(separator: " ").count
        let baseMinutes = Double(wordCount) / 150.0
        let adjustedMinutes = baseMinutes / Double(speed)
        return adjustedMinutes * 60.0
    }
}
