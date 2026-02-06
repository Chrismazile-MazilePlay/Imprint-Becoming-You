//
//  MockTTSSynthesisEngine.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/5/26.
//

import Foundation

// MARK: - Mock TTS Synthesis Engine

/// Mock implementation of `TTSSynthesisEngineProtocol` for testing and previews.
///
/// Provides configurable behavior:
/// - Instant synthesis (default)
/// - Simulated delay per synthesis call
/// - Failure simulation
/// - Kokoro readiness control
@MainActor
final class MockTTSSynthesisEngine: TTSSynthesisEngineProtocol {

    // MARK: - Configuration

    /// Whether Kokoro is reported as ready (default: true)
    var kokoroReady: Bool = true

    /// Delay per synthesis call (default: zero for instant)
    var synthesisDelay: Duration = .zero

    /// Whether to simulate synthesis failure
    var shouldFail: Bool = false

    /// Error message for simulated failures
    var failureMessage: String = "Mock synthesis failure"

    /// Whether idle timer is currently suppressed (observable for tests)
    private(set) var isIdleTimerSuppressed: Bool = false

    // MARK: - TTSSynthesisEngineProtocol

    var isKokoroReady: Bool {
        kokoroReady
    }

    func waitForKokoroReady(timeout: TimeInterval) async -> Bool {
        kokoroReady
    }

    func synthesize(text: String, config: SessionVoiceConfiguration) async throws -> Data {
        if synthesisDelay > .zero {
            try await Task.sleep(for: synthesisDelay)
        }

        if shouldFail {
            throw TTSError.synthesisFailedError(message: failureMessage)
        }

        return generateMockAudio(for: text)
    }

    func suppressIdleTimer() {
        isIdleTimerSuppressed = true
    }

    func resumeIdleTimer() {
        isIdleTimerSuppressed = false
    }

    // MARK: - Private

    /// Generates a minimal WAV file with silence. Duration scales with text length.
    private func generateMockAudio(for text: String) -> Data {
        let sampleRate: UInt32 = 24000
        let duration = max(1.0, Double(text.count) / 20.0)
        let numSamples = Int(Double(sampleRate) * duration)

        var data = Data()

        let dataSize = UInt32(numSamples * 2)
        let fileSize = dataSize + 36

        // WAV header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: (sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Silent audio samples
        data.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

        return data
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension MockTTSSynthesisEngine {

    static var instant: MockTTSSynthesisEngine {
        MockTTSSynthesisEngine()
    }

    static var failing: MockTTSSynthesisEngine {
        let mock = MockTTSSynthesisEngine()
        mock.shouldFail = true
        return mock
    }
}
#endif
