//
//  TTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation
import AVFoundation
import iOS_TTS

// MARK: - TTS Service

/// Production implementation of text-to-speech service.
///
/// Integrates Kokoro neural TTS with System TTS fallback for reliable
/// high-quality speech synthesis optimized for affirmation delivery.
///
/// ## Voice Routing
/// - `nil` / empty / `kokoro_*`: Kokoro neural TTS (falls back to System if unavailable)
/// - `system`: System AVSpeechSynthesizer
///
/// ## Architecture
/// ```
/// TTSService
/// ├── KokoroTTSEngine (primary - high quality neural TTS)
/// │   └── Falls back to SystemTTS if:
/// │       - Engine not initialized
/// │       - Synthesis fails
/// │       - Invalid voice ID
/// └── SystemTTSService (fallback - always available)
/// ```
@MainActor
final class TTSService: TTSServiceProtocol {
    
    // MARK: - Dependencies
    
    /// Kokoro neural TTS engine (primary)
    private let kokoroEngine: KokoroTTSEngine
    
    /// System TTS service for fallback
    private let systemTTS: SystemTTSService
    
    /// Audio player for Kokoro output
    private var audioPlayer: AVAudioPlayer?
    
    /// Audio player delegate (must be retained)
    private var playerDelegate: TTSAudioPlayerDelegate?
    
    /// Audio cache manager
    private let cacheManager: AudioCacheManager
    
    // MARK: - State
    
    /// Whether Kokoro or System TTS is currently speaking
    private var _isSpeaking: Bool = false
    
    /// Whether Kokoro engine is ready
    private var _isKokoroReady: Bool = false
    
    // MARK: - Initialization
    
    init() {
        self.kokoroEngine = KokoroTTSEngine()
        
        let systemTTS = SystemTTSService()
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        self.systemTTS = systemTTS
        
        self.cacheManager = AudioCacheManager.shared
    }
    
    /// Creates a TTS service with injected dependencies (for testing).
    init(kokoroEngine: KokoroTTSEngine, systemTTS: SystemTTSService, cacheManager: AudioCacheManager) {
        self.kokoroEngine = kokoroEngine
        
        systemTTS.speechRate = TTSConfiguration.speechRate
        systemTTS.pitchMultiplier = TTSConfiguration.pitchMultiplier
        self.systemTTS = systemTTS
        
        self.cacheManager = cacheManager
    }
    
    // MARK: - TTSServiceProtocol
    
    var isSpeaking: Bool {
        _isSpeaking || systemTTS.isSpeaking || (audioPlayer?.isPlaying ?? false)
    }
    
    var isKokoroReady: Bool {
        _isKokoroReady
    }
    
    func warmUp() async {
        #if DEBUG
        print("🎤 TTSService: Warming up Kokoro engine...")
        #endif
        
        do {
            try await kokoroEngine.warmUp()
            _isKokoroReady = true
            
            #if DEBUG
            print("✅ TTSService: Kokoro engine ready")
            #endif
        } catch {
            _isKokoroReady = false
            
            #if DEBUG
            print("⚠️ TTSService: Kokoro warm-up failed, will use System TTS fallback - \(error)")
            #endif
        }
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        // Route based on voiceId
        if voiceId == TTSConfiguration.systemVoiceId {
            return try await systemTTS.synthesizeToData(text)
        }
        
        // Try Kokoro for nil, empty, or kokoro_* voice IDs
        return try await synthesizeWithKokoro(text: text, voiceId: voiceId)
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        stopSpeaking()
        
        _isSpeaking = true
        defer { _isSpeaking = false }
        
        // Route based on voiceId
        if voiceId == TTSConfiguration.systemVoiceId {
            try await systemTTS.speak(text)
            return
        }
        
        // Try Kokoro for nil, empty, or kokoro_* voice IDs
        try await speakWithKokoro(text: text, voiceId: voiceId)
    }
    
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        playerDelegate = nil
        systemTTS.stopSpeaking()
        _isSpeaking = false
    }
    
    // MARK: - Kokoro Synthesis
    
    private func synthesizeWithKokoro(text: String, voiceId: String?) async throws -> Data {
        guard _isKokoroReady else {
            #if DEBUG
            print("⚠️ TTSService: Kokoro not ready, falling back to System TTS")
            #endif
            return try await systemTTS.synthesizeToData(text)
        }
        
        // Resolve voice style
        let voiceStyle = resolveVoiceStyle(voiceId: voiceId)
        
        do {
            return try await kokoroEngine.synthesizeToData(
                text: text,
                voiceStyle: voiceStyle,
                speed: TTSConfiguration.kokoroSpeed
            )
        } catch {
            #if DEBUG
            print("⚠️ TTSService: Kokoro synthesis failed, falling back to System TTS - \(error)")
            #endif
            return try await systemTTS.synthesizeToData(text)
        }
    }
    
    private func speakWithKokoro(text: String, voiceId: String?) async throws {
        guard _isKokoroReady else {
            #if DEBUG
            print("⚠️ TTSService: Kokoro not ready, falling back to System TTS")
            #endif
            try await systemTTS.speak(text)
            return
        }
        
        // Resolve voice style
        let voiceStyle = resolveVoiceStyle(voiceId: voiceId)
        
        do {
            let audioData = try await kokoroEngine.synthesizeToData(
                text: text,
                voiceStyle: voiceStyle,
                speed: TTSConfiguration.kokoroSpeed
            )
            
            try await playAudioData(audioData)
            
        } catch {
            #if DEBUG
            print("⚠️ TTSService: Kokoro playback failed, falling back to System TTS - \(error)")
            #endif
            try await systemTTS.speak(text)
        }
    }
    
    /// Resolves voiceId to iOS_TTS VoiceStyle, using default if not found.
    private func resolveVoiceStyle(voiceId: String?) -> VoiceStyle {
        guard let voiceId = voiceId, !voiceId.isEmpty else {
            return .afHeart // Default voice
        }
        
        // Remove "kokoro_" prefix if present
        let styleString = voiceId.hasPrefix(TTSConfiguration.kokoroPrefix)
            ? String(voiceId.dropFirst(TTSConfiguration.kokoroPrefix.count))
            : voiceId
        
        // Try to match VoiceStyle case
        return VoiceStyle(rawValue: styleString) ?? .afHeart
    }
    
    // MARK: - Audio Playback
    
    private func playAudioData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let player = try AVAudioPlayer(data: data)
                self.audioPlayer = player
                
                let delegate = TTSAudioPlayerDelegate { [weak self] success in
                    self?.audioPlayer = nil
                    self?.playerDelegate = nil
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AppError.ttsError("Audio playback interrupted"))
                    }
                }
                
                self.playerDelegate = delegate
                player.delegate = delegate
                
                // Configure audio session
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                try session.setActive(true)
                
                if !player.play() {
                    continuation.resume(throwing: AppError.ttsError("Failed to start audio playback"))
                }
                
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Audio Player Delegate

/// Helper class to handle AVAudioPlayer delegate callbacks.
private final class TTSAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    
    private let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion(flag)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        completion(false)
    }
}
