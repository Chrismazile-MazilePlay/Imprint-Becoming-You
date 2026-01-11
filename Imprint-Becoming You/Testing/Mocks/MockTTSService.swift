//
//  MockTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock TTS Service

/// Mock implementation of TTSServiceProtocol for previews and testing.
///
/// Simulates TTS behavior with configurable delays and state.
/// Does not produce actual audio output.
///
/// ## Usage in Tests
/// ```swift
/// let mockTTS = MockTTSService()
/// mockTTS.simulatedSpeakDuration = 2.0  // 2 second "speech"
/// let container = DependencyContainer.preview
/// // MockTTSService is automatically used in preview container
/// ```
///
/// ## Usage in Previews
/// ```swift
/// PracticeStore(dependencies: .preview)  // Uses MockTTSService
/// ```
@MainActor
final class MockTTSService: TTSServiceProtocol {
    
    // MARK: - Configuration
    
    /// Duration to simulate for speakText calls (seconds)
    var simulatedSpeakDuration: TimeInterval = 1.5
    
    /// Whether to simulate errors
    var shouldSimulateError: Bool = false
    
    /// Error to throw when shouldSimulateError is true
    var simulatedError: Error = AppError.ttsError("Mock TTS error")
    
    // MARK: - State
    
    /// Whether speech is currently "playing"
    private(set) var isSpeaking: Bool = false
    
    /// Last text that was spoken
    private(set) var lastSpokenText: String?
    
    /// Count of speakText calls
    private(set) var speakCallCount: Int = 0
    
    /// Count of stopSpeaking calls
    private(set) var stopCallCount: Int = 0
    
    /// Current speak task (for cancellation)
    private var speakTask: Task<Void, Error>?
    
    // MARK: - TTSServiceProtocol
    
    func synthesize(text: String, voiceId: String?) async throws -> Data {
        if shouldSimulateError {
            throw simulatedError
        }
        
        // Return mock audio data
        return Data("mock-audio-data-\(text.hashValue)".utf8)
    }
    
    func speakText(_ text: String, voiceId: String?) async throws {
        if shouldSimulateError {
            throw simulatedError
        }
        
        speakCallCount += 1
        lastSpokenText = text
        isSpeaking = true
        
        // Simulate speech duration
        speakTask = Task {
            try await Task.sleep(for: .seconds(simulatedSpeakDuration))
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
    
    func stopSpeaking() {
        stopCallCount += 1
        speakTask?.cancel()
        speakTask = nil
        isSpeaking = false
    }
    
    // MARK: - Test Helpers
    
    /// Resets all state and counters
    func reset() {
        isSpeaking = false
        lastSpokenText = nil
        speakCallCount = 0
        stopCallCount = 0
        speakTask?.cancel()
        speakTask = nil
        shouldSimulateError = false
    }
}
