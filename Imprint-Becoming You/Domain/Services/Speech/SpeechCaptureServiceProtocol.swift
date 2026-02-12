//
//  SpeechCaptureServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - Recognized Segment

/// Sendable snapshot of an `SFTranscriptionSegment`.
///
/// `SFTranscriptionSegment` is a non-Sendable Foundation class.
/// This struct captures the properties needed for word matching
/// so they can cross actor boundaries safely.
struct RecognizedSegment: Sendable, Equatable {
    /// The recognized word text.
    let substring: String
    /// When in the audio stream this word was spoken (seconds from start).
    let timestamp: TimeInterval
    /// Duration of the spoken word.
    let duration: TimeInterval
    /// Recognition confidence (0.0 – 1.0).
    let confidence: Float
    /// Alternative word possibilities computed by the recognizer.
    let alternatives: [String]
}

// MARK: - Speech Capture Update

/// Updates emitted by a speech capture service.
///
/// Extracted from `SpeechCaptureService.CaptureUpdate` to enable
/// protocol-based DI without importing the concrete implementation.
enum SpeechCaptureUpdate: Sendable {
    /// New transcription text (partial or final) with per-word segment data.
    case transcription(text: String, isFinal: Bool, segments: [RecognizedSegment])

    /// Audio level update (0.0 - 1.0 normalized)
    case audioLevel(Float)

    /// Silence detected for specified duration
    case silenceDetected(duration: TimeInterval)

    /// Error occurred during capture
    case error(SpeechCaptureError)

    /// Capture started successfully
    case started

    /// Capture stopped
    case stopped
}

// MARK: - Speech Capture Error

/// Errors that can occur during speech capture.
///
/// Extracted from `SpeechCaptureService.CaptureError` to enable
/// protocol-based DI without importing the concrete implementation.
enum SpeechCaptureError: Error, Sendable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognizerUnavailable
    case audioEngineFailure(String)
    case recognitionFailure(String)
    /// Another app (Zoom, FaceTime, phone call) holds the audio session,
    /// preventing microphone access for speech recognition.
    case audioSessionUnavailable
}

// MARK: - Speech Capture Update Convenience

extension SpeechCaptureUpdate {

    /// Whether this is a transcription update
    var isTranscription: Bool {
        if case .transcription = self { return true }
        return false
    }

    /// Extracts transcription text if this is a transcription update
    var transcriptionText: String? {
        if case .transcription(let text, _, _) = self { return text }
        return nil
    }

    /// Whether this is a final transcription
    var isFinalTranscription: Bool {
        if case .transcription(_, let isFinal, _) = self { return isFinal }
        return false
    }
}

// MARK: - Speech Capture Service Protocol

/// Consumer-facing interface for speech capture and recognition.
///
/// Extracts the capture surface area used by `PracticeStore` from the
/// concrete `SpeechCaptureService`, enabling mock injection for tests.
///
/// ## Responsibilities
/// - Microphone and speech recognition permission management
/// - Audio capture start/stop/cancel lifecycle
/// - Real-time transcription streaming via `captureStream`
///
/// ## Architecture
/// ```
/// SpeechCaptureServiceProtocol
/// ├── SpeechCaptureService (Production)
/// └── MockSpeechCaptureService (Testing)
/// ```
///
/// ## Thread Safety
/// All methods are `@MainActor` isolated. The `captureStream` property
/// is `nonisolated` to allow subscription from async contexts.
@MainActor
protocol SpeechCaptureServiceProtocol: AnyObject {

    // MARK: - Stream Access

    /// Stream of capture updates (transcription, audio levels, errors).
    ///
    /// Subscribe to receive real-time updates during active capture.
    nonisolated var captureStream: AsyncStream<SpeechCaptureUpdate> { get }

    // MARK: - Permissions

    /// Requests microphone permission from the user.
    ///
    /// - Returns: `true` if permission was granted
    func requestMicrophonePermission() async -> Bool

    /// Requests speech recognition permission from the user.
    ///
    /// - Returns: `true` if permission was granted
    func requestSpeechRecognitionPermission() async -> Bool

    /// Whether microphone permission is currently granted.
    var hasMicrophonePermission: Bool { get }

    /// Whether speech recognition permission is currently granted.
    var hasSpeechRecognitionPermission: Bool { get }

    // MARK: - Capture Control

    /// Words to hint the speech recognizer for improved accuracy.
    ///
    /// Set before calling ``startCapture()`` to boost recognition of
    /// known expected words. Applied as `contextualStrings` on the recognition request.
    /// Limited to 100 entries per Apple documentation.
    /// Cleared automatically when capture stops.
    var contextualStrings: [String]? { get set }

    /// Starts audio capture and speech recognition.
    ///
    /// Configures the audio session, starts the AVAudioEngine pipeline,
    /// and begins emitting updates on `captureStream`.
    ///
    /// - Throws: `SpeechCaptureError` if permissions are missing or
    ///   the audio pipeline fails to start
    func startCapture() async throws

    /// Stops capture and returns the final transcription.
    ///
    /// Tears down the audio engine, cancels recognition, and restores
    /// the audio session to `.playback` category.
    ///
    /// - Returns: The accumulated transcription text
    @discardableResult
    func stopCapture() -> String

    /// Cancels capture without waiting for a final result.
    ///
    /// Clears the transcription and tears down the pipeline.
    func cancelCapture()

    // MARK: - State

    /// Whether audio capture is currently active.
    var isCapturing: Bool { get }

    /// The current accumulated transcription text.
    var currentTranscription: String { get }
}
