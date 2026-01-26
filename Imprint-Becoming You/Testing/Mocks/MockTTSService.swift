//
//  MockTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock TTS Service

/// Mock TTS service for testing and previews.
///
/// Tracks all method calls for verification in tests.
/// Does not produce actual audio.
@MainActor
final class MockTTSService: TTSServiceProtocol {
    
    // MARK: - Call Tracking
    
    /// Number of times `synthesize` was called
    var synthesizeCallCount = 0
    
    /// Number of times `speakText` was called
    var speakTextCallCount = 0
    
    /// Number of times `stopSpeaking` was called
    var stopSpeakingCallCount = 0
    
    /// Number of times `preSynthesize` was called
    var preSynthesizeCallCount = 0
    
    /// Number of times `cancelPreSynthesis` was called
    var cancelPreSynthesisCallCount = 0
    
    /// Number of times `warmUp` was called
    var warmUpCallCount = 0
    
    /// Last text passed to `synthesize`
    var lastSynthesizeText: String?
    
    /// Last voice ID passed to `synthesize`
    var lastSynthesizeVoiceId: String?
    
    /// Last text passed to `speakText`
    var lastSpeakText: String?
    
    /// Last voice ID passed to `speakText`
    var lastSpeakVoiceId: String?
    
    /// Last text passed to `preSynthesize`
    var lastPreSynthesizeText: String?
    
    /// Last voice ID passed to `preSynthesize`
    var lastPreSynthesizeVoiceId: String?
    
    // MARK: - Mock Configuration
    
    /// Simulated synthesis duration (seconds)
    var mockDuration: TimeInterval = 2.0
    
    /// Whether synthesis should fail
    var shouldFail = false
    
    /// Error to throw when shouldFail is true
    var mockError: Error = AppError.ttsError("Mock error")
    
    /// Mock speaking state
    var mockIsSpeaking = false
    
    /// Mock Kokoro ready state
    var mockIsKokoroReady = true
    
    // MARK: - TTSServiceProtocol
    
    var isSpeaking: Bool { mockIsSpeaking }
    
    var isKokoroReady: Bool { mockIsKokoroReady }
    
    func warmUp() async {
        warmUpCallCount += 1
        mockIsKokoroReady = true
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        synthesizeCallCount += 1
        lastSynthesizeText = text
        lastSynthesizeVoiceId = voiceId
        
        if shouldFail {
            throw mockError
        }
        
        // Simulate synthesis delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Return empty data
        return Data()
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        speakTextCallCount += 1
        lastSpeakText = text
        lastSpeakVoiceId = voiceId
        
        if shouldFail {
            throw mockError
        }
        
        mockIsSpeaking = true
        
        // Simulate playback delay
        try? await Task.sleep(nanoseconds: UInt64(mockDuration * 1_000_000_000))
        
        mockIsSpeaking = false
    }
    
    func stopSpeaking() {
        stopSpeakingCallCount += 1
        mockIsSpeaking = false
    }
    
    func preSynthesize(text: String, voiceId: String?) async {
        preSynthesizeCallCount += 1
        lastPreSynthesizeText = text
        lastPreSynthesizeVoiceId = voiceId
        
        // Simulate synthesis delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
    
    func cancelPreSynthesis() {
        cancelPreSynthesisCallCount += 1
    }
    
    // MARK: - Test Helpers
    
    /// Resets all tracking state
    func reset() {
        synthesizeCallCount = 0
        speakTextCallCount = 0
        stopSpeakingCallCount = 0
        preSynthesizeCallCount = 0
        cancelPreSynthesisCallCount = 0
        warmUpCallCount = 0
        
        lastSynthesizeText = nil
        lastSynthesizeVoiceId = nil
        lastSpeakText = nil
        lastSpeakVoiceId = nil
        lastPreSynthesizeText = nil
        lastPreSynthesizeVoiceId = nil
        
        shouldFail = false
        mockDuration = 2.0
        mockIsSpeaking = false
        mockIsKokoroReady = true
    }
}
