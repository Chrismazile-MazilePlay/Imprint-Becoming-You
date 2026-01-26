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
/// - `nil` / empty: Kokoro with default voice (af_heart)
/// - `af_heart`, `am_adam`, etc.: Kokoro with specified voice
/// - `system`: System AVSpeechSynthesizer
///
/// ## Pre-Synthesis
/// Use `preSynthesize()` to prepare the next affirmation while the current
/// one is playing, reducing latency for seamless transitions.
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
    
    /// Active pre-synthesis task
    private var preSynthesisTask: Task<Void, Never>?
    
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
        #if DEBUG
        print("🎤 TTSService.synthesize: voiceId = \(voiceId ?? "nil")")
        #endif
        
        // Route based on voiceId
        if voiceId == TTSConfiguration.systemVoiceId {
            return try await systemTTS.synthesizeToData(text)
        }
        
        // Try Kokoro for nil, empty, or voice style IDs
        return try await synthesizeWithKokoro(text: text, voiceId: voiceId)
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        #if DEBUG
        print("🎤 TTSService.speakText: voiceId = \(voiceId ?? "nil")")
        #endif
        
        stopSpeaking()
        
        _isSpeaking = true
        defer { _isSpeaking = false }
        
        // Route based on voiceId
        if voiceId == TTSConfiguration.systemVoiceId {
            #if DEBUG
            print("🎤 TTSService: Routing to System TTS")
            #endif
            try await systemTTS.speak(text)
            return
        }
        
        // Try Kokoro for nil, empty, or voice style IDs
        try await speakWithKokoro(text: text, voiceId: voiceId)
    }
    
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        playerDelegate = nil
        systemTTS.stopSpeaking()
        _isSpeaking = false
    }
    
    // MARK: - Pre-Synthesis
    
    func preSynthesize(text: String, voiceId: String?) async {
        #if DEBUG
        print("🎤 TTSService: Pre-synthesizing '\(text.prefix(30))...' with voice \(voiceId ?? "default")")
        #endif
        
        // Cancel any existing pre-synthesis
        preSynthesisTask?.cancel()
        
        // Synthesize in background (result is cached automatically by the engine/cache manager)
        preSynthesisTask = Task {
            do {
                _ = try await synthesize(text: text, voiceId: voiceId)
                #if DEBUG
                print("✅ TTSService: Pre-synthesis complete")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ TTSService: Pre-synthesis failed: \(error)")
                #endif
            }
        }
    }
    
    func cancelPreSynthesis() {
        preSynthesisTask?.cancel()
        preSynthesisTask = nil
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
        
        #if DEBUG
        print("🎤 TTSService: Resolved voice style: \(voiceStyle.rawValue)")
        #endif
        
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
        #if DEBUG
        print("🎤 TTSService.speakWithKokoro: voiceId = \(voiceId ?? "nil")")
        #endif
        
        guard _isKokoroReady else {
            #if DEBUG
            print("⚠️ TTSService: Kokoro not ready, falling back to System TTS")
            #endif
            try await systemTTS.speak(text)
            return
        }
        
        // Resolve voice style
        let voiceStyle = resolveVoiceStyle(voiceId: voiceId)
        
        #if DEBUG
        print("🎤 TTSService: Resolved voice style: \(voiceStyle.rawValue)")
        #endif
        
        do {
            let audioData = try await kokoroEngine.synthesizeToData(
                text: text,
                voiceStyle: voiceStyle,
                speed: TTSConfiguration.kokoroSpeed
            )
            
            #if DEBUG
            print("✅ TTSService: Kokoro synthesis complete, playing \(audioData.count) bytes")
            #endif
            
            try await playAudioData(audioData)
            
        } catch {
            #if DEBUG
            print("⚠️ TTSService: Kokoro playback failed, falling back to System TTS - \(error)")
            #endif
            try await systemTTS.speak(text)
        }
    }
    
    // MARK: - Voice Style Resolution
    
    /// Resolves a voice ID string to a Kokoro VoiceStyle.
    ///
    /// - Parameter voiceId: Voice ID in snake_case (e.g., "af_heart", "am_adam")
    /// - Returns: The corresponding VoiceStyle, or .afHeart as default
    private func resolveVoiceStyle(voiceId: String?) -> VoiceStyle {
        guard let voiceId = voiceId, !voiceId.isEmpty else {
            #if DEBUG
            print("🎤 TTSService.resolveVoiceStyle: nil/empty -> default af_heart")
            #endif
            return .afHeart // Default voice
        }
        
        // Voice ID should match VoiceStyle.rawValue directly (e.g., "af_heart")
        if let voiceStyle = VoiceStyle(rawValue: voiceId) {
            #if DEBUG
            print("🎤 TTSService.resolveVoiceStyle: \(voiceId) -> \(voiceStyle.rawValue)")
            #endif
            return voiceStyle
        }
        
        // Legacy support: remove "kokoro_" prefix if present
        if voiceId.hasPrefix(TTSConfiguration.kokoroPrefix) {
            let styleString = String(voiceId.dropFirst(TTSConfiguration.kokoroPrefix.count))
            if let voiceStyle = VoiceStyle(rawValue: styleString) {
                #if DEBUG
                print("🎤 TTSService.resolveVoiceStyle: \(voiceId) (legacy) -> \(voiceStyle.rawValue)")
                #endif
                return voiceStyle
            }
        }
        
        #if DEBUG
        print("⚠️ TTSService.resolveVoiceStyle: \(voiceId) not found, using default af_heart")
        #endif
        return .afHeart
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
