//
//  MockTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock TTS Service

/// Mock implementation of TTSServiceProtocol for testing and previews.
@MainActor
final class MockTTSService: TTSServiceProtocol {
    
    // MARK: - Properties
    
    let provider: VoiceProvider
    var isAvailable: Bool = true
    private(set) var isSpeaking: Bool = false
    
    // Test hooks
    var synthesizeDelay: TimeInterval = 0.1
    var speakDelay: TimeInterval = 1.5
    var shouldFail: Bool = false
    var failureError: TTSError = .unknown(underlyingError: nil)
    
    // Tracking
    private(set) var synthesizeCallCount = 0
    private(set) var speakCallCount = 0
    private(set) var lastSynthesizedText: String?
    private(set) var lastSpokenText: String?
    private(set) var lastUsedVoice: Voice?
    
    /// Current speak task (for cancellation)
    private var speakTask: Task<Void, Error>?
    
    // MARK: - Initialization
    
    init(provider: VoiceProvider = .kokoro) {
        self.provider = provider
    }
    
    // MARK: - TTSServiceProtocol - Real-Time Playback
    
    func speakText(_ text: String, voice: Voice?) async throws {
        if shouldFail {
            throw failureError
        }
        
        speakCallCount += 1
        lastSpokenText = text
        lastUsedVoice = voice
        isSpeaking = true
        
        // Simulate speech duration
        speakTask = Task {
            try await Task.sleep(for: .seconds(speakDelay))
        }
        
        do {
            try await speakTask?.value
            isSpeaking = false
        } catch {
            isSpeaking = false
            if !(error is CancellationError) {
                throw error
            }
        }
    }
    
    // MARK: - TTSServiceProtocol - Synthesis
    
    func synthesize(text: String, voice: Voice, speed: Float) async throws -> TTSResult {
        synthesizeCallCount += 1
        lastSynthesizedText = text
        lastUsedVoice = voice
        
        if shouldFail {
            throw failureError
        }
        
        isSpeaking = true
        defer { isSpeaking = false }
        
        // Simulate synthesis delay
        if synthesizeDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(synthesizeDelay * 1_000_000_000))
        }
        
        // Generate mock audio data (silence)
        let sampleRate = 24000
        let duration = Double(text.count) * 0.05 // ~50ms per character
        let sampleCount = Int(duration * Double(sampleRate))
        let mockAudioData = Data(repeating: 0, count: sampleCount * 2) // 16-bit samples
        
        // Generate mock word timings
        let words = text.split(separator: " ").map(String.init)
        var wordTimings: [WordTiming] = []
        var currentTime: TimeInterval = 0
        var currentChar = 0
        
        for word in words {
            let wordDuration = Double(word.count) * 0.05
            wordTimings.append(WordTiming(
                word: word,
                startTime: currentTime,
                endTime: currentTime + wordDuration,
                characterRange: currentChar..<(currentChar + word.count)
            ))
            currentTime += wordDuration + 0.1
            currentChar += word.count + 1
        }
        
        return TTSResult(
            audioData: mockAudioData,
            audioFormat: .wav,
            duration: duration,
            originalText: text,
            voice: voice,
            wordTimings: wordTimings,
            source: .synthesized
        )
    }
    
    func availableVoices() -> [Voice] {
        switch provider {
        case .system:
            return []
        case .kokoro:
            return Voice.allKokoroVoices
        case .qwenCloud:
            return Voice.qwenPresetVoices
        }
    }
    
    func prepareVoice(_ voice: Voice) async throws {
        // No-op for mock
    }
    
    func canSynthesize(voice: Voice) -> Bool {
        voice.provider == provider
    }
    
    func stopSpeaking() {
        speakTask?.cancel()
        speakTask = nil
        isSpeaking = false
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        synthesizeCallCount = 0
        speakCallCount = 0
        lastSynthesizedText = nil
        lastSpokenText = nil
        lastUsedVoice = nil
        shouldFail = false
        isSpeaking = false
        speakTask?.cancel()
        speakTask = nil
    }
}
