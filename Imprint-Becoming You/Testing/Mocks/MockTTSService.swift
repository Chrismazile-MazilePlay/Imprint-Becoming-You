//
//  MockTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock TTS Service

/// Mock implementation of TTS service for previews and testing.
///
/// Simulates speech synthesis with configurable delays.
/// Does not produce actual audio output.
final class MockTTSService: TTSServiceProtocol, @unchecked Sendable {
    
    // MARK: - Thread Safety
    
    private let stateQueue = DispatchQueue(label: "com.imprint.mocktts")
    private var _isSpeaking: Bool = false
    
    // MARK: - Configuration
    
    /// Simulated synthesis delay
    var synthesisDelay: Duration = .milliseconds(500)
    
    /// Simulated speaking delay
    var speakingDelay: Duration = .seconds(2)
    
    /// Whether to simulate errors
    var shouldSimulateError: Bool = false
    
    // MARK: - TTSServiceProtocol
    
    var isSpeaking: Bool {
        stateQueue.sync { _isSpeaking }
    }
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        if shouldSimulateError {
            throw AppError.ttsGenerationFailed(reason: "Simulated error")
        }
        
        try await Task.sleep(for: synthesisDelay)
        return Data() // Return empty data for mock
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        if shouldSimulateError {
            throw AppError.ttsGenerationFailed(reason: "Simulated error")
        }
        
        stateQueue.sync { _isSpeaking = true }
        try await Task.sleep(for: speakingDelay)
        stateQueue.sync { _isSpeaking = false }
    }
    
    func stopSpeaking() async {
        stateQueue.sync { _isSpeaking = false }
    }
}
