//
//  MockTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock TTS Service

/// Mock implementation of TTSServiceProtocol for testing.
@MainActor
final class MockTTSService: TTSServiceProtocol {
    
    // MARK: - Configuration
    
    /// Delay before completing speakText
    var speakDelay: TimeInterval = 1.5
    
    /// Delay before completing synthesize
    var synthesizeDelay: TimeInterval = 0.5
    
    /// If set, methods will throw this error
    var errorToThrow: Error?
    
    /// Whether Kokoro is "ready" in the mock
    var mockKokoroReady: Bool = true
    
    // MARK: - Tracking
    
    private(set) var speakCallCount: Int = 0
    private(set) var synthesizeCallCount: Int = 0
    private(set) var stopCallCount: Int = 0
    private(set) var warmUpCallCount: Int = 0
    private(set) var lastSpokenText: String?
    private(set) var lastVoiceId: String?
    
    // MARK: - State
    
    private var _isSpeaking: Bool = false
    private var currentTask: Task<Void, Error>?
    
    // MARK: - TTSServiceProtocol
    
    var isSpeaking: Bool { _isSpeaking }
    
    var isKokoroReady: Bool { mockKokoroReady }
    
    func warmUp() async {
        warmUpCallCount += 1
        try? await Task.sleep(for: .milliseconds(100))
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        synthesizeCallCount += 1
        lastSpokenText = text
        lastVoiceId = voiceId
        
        if let error = errorToThrow {
            throw error
        }
        
        try await Task.sleep(for: .milliseconds(Int(synthesizeDelay * 1000)))
        
        return createMockWAVData()
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        speakCallCount += 1
        lastSpokenText = text
        lastVoiceId = voiceId
        
        if let error = errorToThrow {
            throw error
        }
        
        _isSpeaking = true
        defer { _isSpeaking = false }
        
        currentTask = Task {
            try await Task.sleep(for: .milliseconds(Int(speakDelay * 1000)))
        }
        
        do {
            try await currentTask?.value
        } catch is CancellationError {
            // Stopped early - expected
        }
        
        currentTask = nil
    }
    
    func stopSpeaking() {
        stopCallCount += 1
        currentTask?.cancel()
        currentTask = nil
        _isSpeaking = false
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        speakCallCount = 0
        synthesizeCallCount = 0
        stopCallCount = 0
        warmUpCallCount = 0
        lastSpokenText = nil
        lastVoiceId = nil
        errorToThrow = nil
        _isSpeaking = false
        currentTask = nil
    }
    
    private func createMockWAVData() -> Data {
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: [16, 0, 0, 0])
        data.append(contentsOf: [1, 0])
        data.append(contentsOf: [1, 0])
        data.append(contentsOf: [0x80, 0xBB, 0, 0])
        data.append(contentsOf: [0, 0xEE, 2, 0])
        data.append(contentsOf: [4, 0])
        data.append(contentsOf: [16, 0])
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: [0, 0, 0, 0])
        return data
    }
}
