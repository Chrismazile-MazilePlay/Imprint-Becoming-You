//
//  SpeechCaptureServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - RecognizedSegment

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
    /// Recognition confidence (0.0–1.0).
    let confidence: Float
    /// Alternative word possibilities computed by the recognizer.
    let alternatives: [String]
}

// MARK: - SpeechCaptureUpdate

/// Updates emitted by the speech capture service.
///
/// The capture service is a **dumb pipe** — it streams whatever the
/// recognizer produces without any segment awareness or word matching.
/// Consumers (e.g., `PracticeStore`) handle all word matching logic.
enum SpeechCaptureUpdate: Sendable {
    /// New transcription text (partial or final) with per-word segment data.
    ///
    /// `text` is the **full cumulative** transcription from the session-long
    /// recognition task. `segments` contains per-word timing and confidence data.
    /// On each partial result, the full text is re-emitted so consumers can
    /// diff against their own state.
    case transcription(text: String, isFinal: Bool, segments: [RecognizedSegment])

    /// Audio level update (0.0–1.0 normalized).
    case audioLevel(Float)

    /// Silence detected for the specified duration.
    case silenceDetected(duration: TimeInterval)

    /// Error occurred during capture.
    case error(SpeechCaptureError)

    /// Capture started successfully (mic ON).
    case started

    /// Capture stopped (mic OFF).
    case stopped
}

// MARK: - SpeechCaptureError

/// Errors that can occur during speech capture.
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

// MARK: - SpeechCaptureUpdate Convenience

extension SpeechCaptureUpdate {

    /// Whether this is a transcription update.
    var isTranscription: Bool {
        if case .transcription = self { return true }
        return false
    }

    /// Extracts transcription text if this is a transcription update.
    var transcriptionText: String? {
        if case .transcription(let text, _, _) = self { return text }
        return nil
    }

    /// Whether this is a final transcription.
    var isFinalTranscription: Bool {
        if case .transcription(_, let isFinal, _) = self { return isFinal }
        return false
    }
}

// MARK: - SpeechCaptureServiceProtocol

/// Consumer-facing interface for speech capture and recognition.
///
/// The capture service is a **dumb pipe**: it owns a standalone `AVAudioEngine`
/// for mic capture, maintains a session-long `SFSpeechRecognitionTask`, and
/// streams recognized text via ``captureStream``. It knows nothing about
/// affirmation segments or word matching — that logic belongs in `PracticeStore`.
///
/// ## Architecture
/// ```
/// SpeechCaptureServiceProtocol
/// ├── SpeechCaptureService  (Production)
/// └── MockSpeechCaptureService (Testing)
/// ```
///
/// ## Mic Lifecycle
/// - `startCapture()` installs an input tap → mic ON (iOS orange indicator)
/// - `stopCapture()` removes the input tap → mic OFF (indicator disappears)
/// - `releaseEngine()` tears down everything at session end
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
    /// uses the session controller to verify the audio session is configured.
    /// Mic capture uses a **standalone** `AVAudioEngine` — the shared engine
    /// is NOT used for input taps.
    var audioService: (any AudioServiceProtocol)? { get set }

    // MARK: - Stream Access

    /// Stream of capture updates (transcription, audio levels, errors).
    ///
    /// Subscribe to receive real-time updates during active capture.
    /// Transcription updates contain the **full cumulative text** from the
    /// session-long recognition task. Consumers diff against their own state.
    nonisolated var captureStream: AsyncStream<SpeechCaptureUpdate> { get }

    // MARK: - Permissions

    /// Requests microphone permission from the user.
    ///
    /// - Returns: `true` if permission was granted.
    func requestMicrophonePermission() async -> Bool

    /// Requests speech recognition permission from the user.
    ///
    /// - Returns: `true` if permission was granted.
    func requestSpeechRecognitionPermission() async -> Bool

    /// Whether microphone permission is currently granted.
    var hasMicrophonePermission: Bool { get }

    /// Whether speech recognition permission is currently granted.
    var hasSpeechRecognitionPermission: Bool { get }

    // MARK: - Session-Level Configuration

    /// Contextual string hints for the session-long recognition request.
    ///
    /// Set once before calling ``startCapture()`` for the first time.
    /// All session affirmation words are collected into one hint set
    /// (capped at 500) and applied to the recognition request. This
    /// avoids recreating recognition tasks per affirmation.
    var sessionContextualStrings: [String]? { get set }

    /// Whether a session-long recognition task is currently active.
    ///
    /// When `true`, ``startCapture()`` reuses the existing task and only
    /// installs the input tap (zero audio disruption). When `false`, the
    /// next ``startCapture()`` call creates the engine, tap, and task.
    var hasSessionRecognitionTask: Bool { get }

    // MARK: - Capture Control

    /// Starts audio capture and speech recognition.
    ///
    /// On the first call per session, creates the standalone capture engine
    /// and a session-long recognition task. Subsequent calls reuse the
    /// existing task and only install the input tap (mic ON).
    ///
    /// - Throws: `SpeechCaptureError` if permissions are missing,
    ///   `audioService` is not set, or the audio pipeline fails to start.
    func startCapture() async throws

    /// Stops capture and removes the input tap (mic OFF).
    ///
    /// The session-long recognition task stays alive. Call
    /// ``releaseEngine()`` at session end to fully tear down.
    func stopCapture()

    /// Cancels capture without returning a result.
    ///
    /// Removes the input tap (mic OFF). The session-long recognition task
    /// stays alive for the next ``startCapture()`` call.
    func cancelCapture()

    /// Releases the capture engine and recognition task.
    ///
    /// Full teardown: cancels the recognition task, removes the input tap,
    /// stops the engine, and resets all session state. Call at session end.
    /// Safe to call multiple times.
    func releaseEngine()

    // MARK: - State

    /// Whether a listening segment is currently active (mic is ON).
    var isCapturing: Bool { get }

    /// The current cumulative transcription text from the session-long task.
    var currentTranscription: String { get }
}
