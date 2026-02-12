//
//  MockSpeechCaptureService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - Mock Speech Capture Service

/// Test double for `SpeechCaptureServiceProtocol`.
///
/// Records method calls and provides configurable behavior for unit tests.
/// Emits updates through `captureStream` via the `emitUpdate(_:)` helper.
///
/// ## Usage
/// ```swift
/// let mock = MockSpeechCaptureService()
/// mock.stubHasMicrophonePermission = true
/// mock.stubHasSpeechRecognitionPermission = true
///
/// try await mock.startCapture()
/// mock.emitUpdate(.transcription(text: "Hello", isFinal: true))
/// ```
@MainActor
final class MockSpeechCaptureService: SpeechCaptureServiceProtocol, @unchecked Sendable {

    // MARK: - Call Tracking

    /// Number of times `startCapture()` was called
    private(set) var startCaptureCallCount: Int = 0

    /// Number of times `stopCapture()` was called
    private(set) var stopCaptureCallCount: Int = 0

    /// Number of times `cancelCapture()` was called
    private(set) var cancelCaptureCallCount: Int = 0

    // MARK: - Stubs

    /// Stub value for `hasMicrophonePermission`
    var stubHasMicrophonePermission: Bool = true

    /// Stub value for `hasSpeechRecognitionPermission`
    var stubHasSpeechRecognitionPermission: Bool = true

    /// Stub return value for `requestMicrophonePermission()`
    var stubRequestMicPermissionResult: Bool = true

    /// Stub return value for `requestSpeechRecognitionPermission()`
    var stubRequestSpeechPermissionResult: Bool = true

    /// Error to throw from `startCapture()` (nil = success)
    var stubStartCaptureError: Error?

    /// Stub return value for `stopCapture()`
    var stubStopCaptureResult: String = ""

    /// Stub value for `isCapturing`
    var stubIsCapturing: Bool = false

    /// Stub value for `currentTranscription`
    var stubCurrentTranscription: String = ""

    /// Stub value for `currentVoiceAnalytics`
    var stubCurrentVoiceAnalytics: VoiceAnalyticsSummary = VoiceAnalyticsSummary()

    // MARK: - Stream

    /// Continuation for emitting test updates
    nonisolated(unsafe) private var streamContinuation: AsyncStream<SpeechCaptureUpdate>.Continuation?

    /// Stream of capture updates for test subscribers
    nonisolated var captureStream: AsyncStream<SpeechCaptureUpdate> {
        AsyncStream { continuation in
            let mock = self
            Task { @MainActor in
                mock.streamContinuation = continuation
            }
        }
    }

    /// Emits an update to test subscribers.
    ///
    /// - Parameter update: The update to emit
    func emitUpdate(_ update: SpeechCaptureUpdate) {
        streamContinuation?.yield(update)
    }

    // MARK: - SpeechCaptureServiceProtocol

    func requestMicrophonePermission() async -> Bool {
        stubRequestMicPermissionResult
    }

    func requestSpeechRecognitionPermission() async -> Bool {
        stubRequestSpeechPermissionResult
    }

    var hasMicrophonePermission: Bool { stubHasMicrophonePermission }
    var hasSpeechRecognitionPermission: Bool { stubHasSpeechRecognitionPermission }

    func startCapture() async throws {
        startCaptureCallCount += 1
        if let error = stubStartCaptureError { throw error }
        stubIsCapturing = true
    }

    @discardableResult
    func stopCapture() -> String {
        stopCaptureCallCount += 1
        stubIsCapturing = false
        return stubStopCaptureResult
    }

    func cancelCapture() {
        cancelCaptureCallCount += 1
        stubIsCapturing = false
        stubCurrentTranscription = ""
    }

    var isCapturing: Bool { stubIsCapturing }
    var currentTranscription: String { stubCurrentTranscription }
    var currentVoiceAnalytics: VoiceAnalyticsSummary { stubCurrentVoiceAnalytics }

    // MARK: - Reset

    /// Resets all tracked calls and stubs to defaults.
    func reset() {
        startCaptureCallCount = 0
        stopCaptureCallCount = 0
        cancelCaptureCallCount = 0
        stubHasMicrophonePermission = true
        stubHasSpeechRecognitionPermission = true
        stubRequestMicPermissionResult = true
        stubRequestSpeechPermissionResult = true
        stubStartCaptureError = nil
        stubStopCaptureResult = ""
        stubIsCapturing = false
        stubCurrentTranscription = ""
        stubCurrentVoiceAnalytics = VoiceAnalyticsSummary()
        streamContinuation?.finish()
        streamContinuation = nil
    }
}
