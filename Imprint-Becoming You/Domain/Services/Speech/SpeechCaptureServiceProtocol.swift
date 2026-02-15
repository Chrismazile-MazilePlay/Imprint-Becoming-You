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

    // MARK: - Audio Service

    /// The shared audio service for session controller access.
    ///
    /// Must be set before calling ``startCapture()``. The capture service
    /// uses the session controller for audio category transitions. Mic
    /// capture uses a standalone `AVAudioEngine` — the shared engine is
    /// NOT used for input taps.
    ///
    /// Injected by `PracticeStore` at creation time.
    var audioService: (any AudioServiceProtocol)? { get set }

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

    // MARK: - Session-Level Recognition

    /// Merged affirmation words for the entire session.
    ///
    /// Set once before calling ``startCapture()`` for the first segment.
    /// All session affirmation words are collected into one hint set
    /// (capped at 100) and applied to the single session-long recognition
    /// request. This avoids recreating recognition tasks per affirmation.
    var sessionContextualStrings: [String]? { get set }

    /// Whether a session-long recognition task is currently active.
    ///
    /// When `true`, ``startCapture()`` reuses the existing task and only
    /// begins a new segment (zero audio disruption). When `false`, the
    /// next ``startCapture()`` call creates the engine, tap, and task.
    var hasSessionRecognitionTask: Bool { get }

    // MARK: - Capture Control

    /// Words to hint the speech recognizer for improved accuracy.
    ///
    /// **Deprecated in favor of ``sessionContextualStrings``.**
    /// Kept for backward compatibility. If ``sessionContextualStrings``
    /// is set, it takes priority. If neither is set, no hints are applied.
    var contextualStrings: [String]? { get set }

    /// Starts audio capture and speech recognition for one segment.
    ///
    /// On the first call per session, creates the recognition engine, tap,
    /// and a session-long recognition task. Subsequent calls reuse the
    /// existing task and only begin a new segment — zero audio disruption.
    ///
    /// Emits updates on `captureStream` including transcription deltas
    /// relative to this segment's start (not the full session accumulation).
    ///
    /// - Throws: `SpeechCaptureError` if permissions are missing or
    ///   the audio pipeline fails to start
    func startCapture() async throws

    /// Stops the current segment and returns the segment's transcription.
    ///
    /// Ends the active segment but keeps the session-long recognition task
    /// alive. Buffers continue flowing to keep the task warm; transcription
    /// events are suppressed until the next ``startCapture()`` call.
    /// Call ``releaseEngine()`` at session end to fully tear down.
    ///
    /// - Returns: The segment's accumulated transcription text (delta)
    @discardableResult
    func stopCapture() -> String

    /// Cancels the current segment without waiting for a final result.
    ///
    /// Ends the active segment and clears the transcription, but keeps
    /// the session-long recognition task alive for the next segment.
    func cancelCapture()

    /// Releases the persistent capture engine, deactivating mic hardware.
    ///
    /// Cancels the session-long recognition task, removes the input tap,
    /// stops the engine, and resets all session state. Call at session end
    /// or when the service is no longer needed. The engine and task are
    /// automatically recreated on the next ``startCapture()`` call.
    /// Safe to call multiple times — no-op if no engine exists.
    func releaseEngine()

    // MARK: - State

    /// Whether a listening segment is currently active.
    var isCapturing: Bool { get }

    /// The current segment's accumulated transcription text (delta).
    var currentTranscription: String { get }
}
