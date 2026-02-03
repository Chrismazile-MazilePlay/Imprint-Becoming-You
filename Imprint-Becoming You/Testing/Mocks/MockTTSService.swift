//
//  MockTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock TTS Service

/// Mock implementation of TTSServiceProtocol for testing and previews.
///
/// Provides controllable TTS behavior without requiring actual audio synthesis.
/// Tracks method calls and parameters for verification in tests.
@MainActor
final class MockTTSService: TTSServiceProtocol {
    
    // MARK: - State
    
    private var _isSpeaking: Bool = false
    private var _isKokoroReady: Bool = true
    
    var isSpeaking: Bool { _isSpeaking }
    var isKokoroReady: Bool { _isKokoroReady }
    
    // MARK: - Configuration
    
    /// Simulated synthesis delay in seconds
    var synthesisDelay: TimeInterval = 0.1
    
    /// Whether to simulate Kokoro being ready
    var simulateKokoroReady: Bool = true {
        didSet { _isKokoroReady = simulateKokoroReady }
    }
    
    /// Error to throw during synthesis (for testing error handling)
    var synthesisError: Error?
    
    // MARK: - Call Tracking
    
    /// Number of times warmUp was called
    var warmUpCallCount: Int = 0
    
    /// Number of times synthesize was called
    var synthesizeCallCount: Int = 0
    
    /// Number of times speakText was called
    var speakTextCallCount: Int = 0
    
    /// Number of times preSynthesize was called
    var preSynthesizeCallCount: Int = 0
    
    /// Number of times stopSpeaking was called
    var stopSpeakingCallCount: Int = 0
    
    /// Last voice ID passed to synthesize
    var lastSynthesizeVoiceId: String?
    
    /// Last text passed to synthesize
    var lastSynthesizeText: String?
    
    /// Last speed passed to synthesize
    var lastSynthesizeSpeed: Float?
    
    /// Last pitch shift passed to synthesize
    var lastSynthesizePitchShift: Float?
    
    /// Last pitch range passed to synthesize
    var lastSynthesizePitchRange: Float?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - TTSServiceProtocol
    
    func warmUp() async {
        warmUpCallCount += 1
        _isKokoroReady = simulateKokoroReady
        
        // Simulate warm-up delay
        try? await Task.sleep(for: .milliseconds(50))
    }
    
    func retryKokoroInitialization() async {
        _isKokoroReady = false
        await warmUp()
    }
    
    func synthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws -> Data {
        synthesizeCallCount += 1
        lastSynthesizeText = text
        lastSynthesizeVoiceId = voiceId
        lastSynthesizeSpeed = speed
        lastSynthesizePitchShift = pitchShiftSemitones
        lastSynthesizePitchRange = pitchRangeScale
        
        // Check for configured error
        if let error = synthesisError {
            throw error
        }
        
        // Simulate synthesis delay
        try await Task.sleep(for: .milliseconds(Int(synthesisDelay * 1000)))
        
        // Return mock audio data (minimal WAV header)
        return createMockWAVData()
    }
    
    func synthesizeWithSystemTTS(text: String) async throws -> Data {
        return try await synthesize(
            text: text,
            voiceId: TTSConfiguration.systemVoiceId,
            speed: TTSConfiguration.defaultSpeed,
            pitchShiftSemitones: TTSConfiguration.defaultPitchShift,
            pitchRangeScale: TTSConfiguration.defaultPitchRange
        )
    }
    
    func speakText(
        _ text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async throws {
        speakTextCallCount += 1
        
        _isSpeaking = true
        defer { _isSpeaking = false }
        
        // Check for configured error
        if let error = synthesisError {
            throw error
        }
        
        // Simulate speaking delay
        try await Task.sleep(for: .milliseconds(Int(synthesisDelay * 1000)))
    }
    
    func stopSpeaking() {
        stopSpeakingCallCount += 1
        _isSpeaking = false
    }
    
    func preSynthesize(
        text: String,
        voiceId: String?,
        speed: Float,
        pitchShiftSemitones: Float,
        pitchRangeScale: Float
    ) async {
        preSynthesizeCallCount += 1
        _ = try? await synthesize(
            text: text,
            voiceId: voiceId,
            speed: speed,
            pitchShiftSemitones: pitchShiftSemitones,
            pitchRangeScale: pitchRangeScale
        )
    }
    
    func cancelPreSynthesis() {
        // No-op for mock
    }
    
    func releaseForBackground() async {
        _isKokoroReady = false
    }
    
    func releasePipelineMemory() async {
        // No-op for mock - Kokoro stays "ready"
    }
    
    // MARK: - Test Helpers
    
    /// Resets all call counts and tracked values
    func reset() {
        warmUpCallCount = 0
        synthesizeCallCount = 0
        speakTextCallCount = 0
        preSynthesizeCallCount = 0
        stopSpeakingCallCount = 0
        lastSynthesizeVoiceId = nil
        lastSynthesizeText = nil
        lastSynthesizeSpeed = nil
        lastSynthesizePitchShift = nil
        lastSynthesizePitchRange = nil
        synthesisError = nil
        _isSpeaking = false
        _isKokoroReady = simulateKokoroReady
    }
    
    // MARK: - Private Helpers
    
    /// Creates minimal mock WAV data for testing
    private func createMockWAVData() -> Data {
        var data = Data()
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: [0x24, 0x00, 0x00, 0x00]) // file size - 8
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // chunk size
        data.append(contentsOf: [0x01, 0x00]) // PCM
        data.append(contentsOf: [0x01, 0x00]) // mono
        data.append(contentsOf: [0x80, 0xBB, 0x00, 0x00]) // 48000 Hz
        data.append(contentsOf: [0x00, 0x77, 0x01, 0x00]) // byte rate
        data.append(contentsOf: [0x02, 0x00]) // block align
        data.append(contentsOf: [0x10, 0x00]) // bits per sample
        
        // data chunk (empty)
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // data size
        
        return data
    }
}
