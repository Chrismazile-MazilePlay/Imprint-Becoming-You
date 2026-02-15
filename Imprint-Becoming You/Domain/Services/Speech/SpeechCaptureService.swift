//
//  SpeechCaptureService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/9/26.
//

import AVFoundation
@preconcurrency import Speech
import Combine
import os.signpost

// MARK: - SpeechCaptureService

/// Unified service for speech capture and recognition.
///
/// ## Architecture
/// Combines audio capture and speech recognition into a single service to avoid
/// coordination issues between separate components. Uses Apple's recommended
/// pattern of feeding AVAudioEngine buffers directly to SFSpeechRecognizer.
///
/// ## Shared Engine
/// Uses the shared `AVAudioEngine` from `AudioService` via the `audioService`
/// property. The service installs an input tap on the engine's `inputNode`
/// for microphone capture — no separate engine is created. This eliminates
/// dual-render-client HAL contention.
///
/// If `audioService` is not set (defensive fallback), a standalone engine
/// is created for backward compatibility.
///
/// ## Session Management
/// Audio session transitions are routed through `AudioSessionController`:
/// - **Start capture:** Transitions to `.playAndRecord` / `.default` mode
///   (NOT `.measurement` — avoids iOS volume reduction)
/// - **Stop/cancel capture:** Restores `.playback` / `.spokenAudio` mode
///   (fixes SpeakOnly volume bug where session was never restored)
///
/// ## Key Features
/// - **Route Change Handling**: Automatically restarts capture when audio route changes
/// - **Format Agnostic**: Adapts to hardware sample rate changes
/// - **Real-time Transcription**: Provides live transcription updates
/// - **Audio Level Monitoring**: Exposes RMS levels for UI visualization
///
/// ## Performance Profiling
/// Key operations are instrumented with os_signpost for Instruments profiling:
/// - `Speech Capture`: Active capture duration
/// - `Speech Recognition Init`: Audio engine and recognizer setup time
///
/// ## Usage
/// ```swift
/// let service = SpeechCaptureService()
/// service.audioService = dependencies.audioService
/// try await service.startCapture()
///
/// for await update in service.captureStream {
///     switch update {
///     case .transcription(let text, let isFinal, let segments):
///         print("Heard: \(text) (\(segments.count) segments)")
///     case .audioLevel(let level):
///         updateMeter(level)
///     case .error(let error):
///         handleError(error)
///     }
/// }
/// ```
@MainActor
final class SpeechCaptureService: NSObject, SpeechCaptureServiceProtocol, @unchecked Sendable {

    // MARK: - Type Aliases

    /// Backward-compatible alias for `SpeechCaptureUpdate`.
    typealias CaptureUpdate = SpeechCaptureUpdate

    /// Backward-compatible alias for `SpeechCaptureError`.
    typealias CaptureError = SpeechCaptureError

    // MARK: - Properties

    /// The shared audio service for engine and session access.
    ///
    /// When set, `startCapture()` installs an input tap on the shared engine's
    /// `inputNode` and transitions the session via `sessionController`.
    /// When `nil`, falls back to a standalone engine (defensive).
    weak var audioService: (any AudioServiceProtocol)?

    /// Fallback audio engine for when `audioService` is not available.
    /// Only created if `audioService` is nil at capture start time.
    nonisolated(unsafe) private var fallbackAudioEngine: AVAudioEngine?

    /// Whether we are using the shared engine (true) or fallback (false).
    private var usesSharedEngine: Bool = false

    /// Speech recognizer
    private let speechRecognizer: SFSpeechRecognizer?

    /// Current recognition request
    nonisolated(unsafe) private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// Current recognition task
    nonisolated(unsafe) private var recognitionTask: SFSpeechRecognitionTask?

    /// Whether capture is active
    private(set) var isCapturing: Bool = false

    /// Current transcription text
    private(set) var currentTranscription: String = ""

    /// Words to hint the speech recognizer for improved accuracy.
    ///
    /// Set before calling ``startCapture()`` to boost recognition of
    /// known expected words. Applied as `contextualStrings` on the recognition
    /// request. Limited to 100 entries per Apple documentation.
    /// Cleared automatically when capture stops.
    ///
    /// `nonisolated(unsafe)` matches the pattern for other properties accessed
    /// from the background queue in `startCapturePipeline()`. Safe because:
    /// the property is set on MainActor before `startCapture()` is called,
    /// and the `async` await boundary guarantees happens-before ordering.
    nonisolated(unsafe) var contextualStrings: [String]?

    /// Stream continuation for emitting updates
    nonisolated(unsafe) private var streamContinuation: AsyncStream<CaptureUpdate>.Continuation?

    /// Monotonic generation counter for stream lifecycle management.
    ///
    /// Incremented each time `captureStream` creates a new `AsyncStream`.
    /// The `onTermination` handler captures the generation at creation time
    /// and only nils `streamContinuation` if the generation still matches.
    /// This prevents a stale stream's termination from clearing a newer stream's
    /// continuation — the root cause of word highlighting breaking on replay.
    nonisolated(unsafe) private var streamGeneration: Int = 0

    /// Route change observer
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?

    /// Interruption observer
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    /// Silence tracking
    private var lastSpeechTime: Date?
    nonisolated(unsafe) private var silenceTimer: Task<Void, Never>?
    private let silenceThreshold: TimeInterval = 1.5

    /// Audio level smoothing
    private var smoothedLevel: Float = 0
    private let smoothingFactor: Float = 0.3

    /// Signpost ID for current capture session (for proper begin/end pairing)
    nonisolated(unsafe) private var captureSignpostID: OSSignpostID?

    // MARK: - Initialization

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        super.init()

        #if DEBUG
        AppLogger.debug("Initialized with locale \(Locale.current.identifier)", category: .speech)
        #endif
    }

    deinit {
        // Inline cleanup for deinit (can't call MainActor methods)
        silenceTimer?.cancel()
        recognitionTask?.cancel()

        // Only clean up the fallback engine in deinit. When using the shared
        // engine, tap removal is handled by stopCapture()/cancelCapture() which
        // must be called before releasing this service. We cannot access
        // @MainActor-isolated `audioService.sharedEngine` from nonisolated deinit.
        if let engine = fallbackAudioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        streamContinuation?.finish()

        // End capture signpost if still active
        if let signpostID = captureSignpostID {
            AppLogger.endInterval(AppLogger.SignpostName.speechCapture, id: signpostID, category: .speech)
        }
    }

    // MARK: - Stream Access

    /// Stream of capture updates
    ///
    /// Subscribe to this stream to receive real-time updates about:
    /// - Transcription progress
    /// - Audio levels
    /// - Silence detection
    /// - Errors
    nonisolated var captureStream: AsyncStream<CaptureUpdate> {
        AsyncStream { continuation in
            // Store continuation immediately (this closure runs synchronously)
            // We need to dispatch to MainActor but can't block here
            let service = self

            Task { @MainActor in
                // Increment generation BEFORE setting the new continuation.
                // This ensures any pending onTermination from the old stream
                // will see a stale generation and skip the nil assignment.
                service.streamGeneration += 1
                let currentGeneration = service.streamGeneration
                service.streamContinuation = continuation

                #if DEBUG
                AppLogger.debug("Stream continuation set (generation \(currentGeneration))", category: .speech)
                #endif

                // Handle stream termination — only nil the continuation
                // if this stream's generation is still current.
                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor in
                        guard service.streamGeneration == currentGeneration else {
                            #if DEBUG
                            AppLogger.debug("Stream terminated (stale generation \(currentGeneration), current \(service.streamGeneration)) — skipping nil", category: .speech)
                            #endif
                            return
                        }
                        service.streamContinuation = nil
                        #if DEBUG
                        AppLogger.debug("Stream terminated (generation \(currentGeneration))", category: .speech)
                        #endif
                    }
                }
            }
        }
    }

    // MARK: - Permissions

    /// Requests microphone permission
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Requests speech recognition permission
    func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Whether microphone permission is granted
    var hasMicrophonePermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Whether speech recognition permission is granted
    var hasSpeechRecognitionPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Capture Control

    /// Starts audio capture and speech recognition
    func startCapture() async throws {
        guard !isCapturing else {
            #if DEBUG
            AppLogger.debug("Already capturing, ignoring start request", category: .speech)
            #endif
            return
        }

        #if DEBUG
        AppLogger.debug("Starting capture...", category: .speech)
        #endif

        // Begin signpost interval for capture
        captureSignpostID = AppLogger.makeSignpostID(for: .speech)
        if let signpostID = captureSignpostID {
            AppLogger.beginInterval(AppLogger.SignpostName.speechCapture, id: signpostID, category: .speech)
        }

        // Check permissions
        guard hasMicrophonePermission else {
            endCaptureSignpost()
            emit(.error(.microphonePermissionDenied))
            throw CaptureError.microphonePermissionDenied
        }

        guard hasSpeechRecognitionPermission else {
            endCaptureSignpost()
            emit(.error(.speechRecognitionPermissionDenied))
            throw CaptureError.speechRecognitionPermissionDenied
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            endCaptureSignpost()
            emit(.error(.speechRecognizerUnavailable))
            throw CaptureError.speechRecognizerUnavailable
        }

        // Configure audio session via session controller (shared engine path)
        // or fall back to direct configuration (standalone engine path)
        if let audioService = audioService {
            try await configureAudioSessionViaController(audioService: audioService)
            usesSharedEngine = true
        } else {
            #if DEBUG
            AppLogger.debug("⚠️ audioService not set — falling back to standalone engine", category: .speech)
            #endif
            try await configureAudioSessionFallback()
            usesSharedEngine = false
        }

        // Verify the shared engine is running before installing a tap.
        // If the engine isn't running, the input node won't produce buffers
        // and recognition will silently fail.
        if usesSharedEngine, let audioService = audioService {
            guard audioService.sharedEngine.isRunning else {
                throw CaptureError.audioEngineFailure("Shared audio engine is not running")
            }
        }

        // Setup observers
        setupObservers()

        // Start the capture pipeline
        try await startCapturePipeline()

        isCapturing = true
        currentTranscription = ""
        lastSpeechTime = Date()

        // Start silence monitoring
        startSilenceMonitoring()

        emit(.started)

        #if DEBUG
        AppLogger.debug("Capture started successfully", category: .speech)
        #endif
    }

    /// Stops capture and returns final transcription
    @discardableResult
    func stopCapture() -> String {
        guard isCapturing else { return currentTranscription }

        #if DEBUG
        AppLogger.debug("Stopping capture...", category: .speech)
        #endif

        // Stop silence monitoring
        silenceTimer?.cancel()
        silenceTimer = nil

        // End recognition request
        recognitionRequest?.endAudio()

        // Remove input tap from the engine we used
        if usesSharedEngine, let audioService = audioService {
            audioService.sharedEngine.inputNode.removeTap(onBus: 0)
        } else if let engine = fallbackAudioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            fallbackAudioEngine = nil
        }

        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        isCapturing = false
        contextualStrings = nil

        // End signpost interval
        endCaptureSignpost()

        emit(.stopped)

        // Restore audio session to .playback via session controller.
        // This is the definitive restoration — fixes the SpeakOnly bug where
        // the session was never restored after mic use.
        if usesSharedEngine, let audioService = audioService {
            Task { @MainActor in
                try? await audioService.sessionController.transition(
                    to: .playback,
                    mode: .spokenAudio,
                    options: [.mixWithOthers],
                    engineAction: .pauseAndResume
                )
            }
        }

        #if DEBUG
        AppLogger.debug("Capture stopped. Final: \"\(currentTranscription)\"", category: .speech)
        #endif

        return currentTranscription
    }

    /// Cancels capture without waiting for final result
    func cancelCapture() {
        guard isCapturing else { return }

        #if DEBUG
        AppLogger.debug("Cancelling capture...", category: .speech)
        #endif

        silenceTimer?.cancel()
        silenceTimer = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Remove input tap from the engine we used
        if usesSharedEngine, let audioService = audioService {
            audioService.sharedEngine.inputNode.removeTap(onBus: 0)
        } else if let engine = fallbackAudioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            fallbackAudioEngine = nil
        }

        isCapturing = false
        currentTranscription = ""
        contextualStrings = nil

        // End signpost interval
        endCaptureSignpost()

        emit(.stopped)

        // Restore audio session to .playback via session controller.
        if usesSharedEngine, let audioService = audioService {
            Task { @MainActor in
                try? await audioService.sessionController.transition(
                    to: .playback,
                    mode: .spokenAudio,
                    options: [.mixWithOthers],
                    engineAction: .pauseAndResume
                )
            }
        }
    }

    // MARK: - Private Methods

    /// Ends the capture signpost interval if one is active
    private func endCaptureSignpost() {
        if let signpostID = captureSignpostID {
            AppLogger.endInterval(AppLogger.SignpostName.speechCapture, id: signpostID, category: .speech)
            captureSignpostID = nil
        }
    }

    /// Configures the audio session for recording via the shared AudioSessionController.
    ///
    /// Uses `.default` mode instead of `.measurement` to avoid iOS-imposed volume
    /// reduction. The session controller handles the engine stop/restart cycle
    /// required for `.playback` → `.playAndRecord` transitions.
    private func configureAudioSessionViaController(audioService: any AudioServiceProtocol) async throws {
        do {
            try await audioService.sessionController.transition(
                to: .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers],
                engineAction: .pauseAndResume
            )

            #if DEBUG
            let session = AVAudioSession.sharedInstance()
            AppLogger.debug("Audio session configured via controller - Sample rate: \(session.sampleRate)", category: .speech)
            #endif
        } catch {
            // Determine if a competing app holds the session
            let errorDesc = error.localizedDescription
            if errorDesc.contains("561017449") || errorDesc.contains("!pri") {
                throw CaptureError.audioSessionUnavailable
            }
            throw CaptureError.audioEngineFailure("Failed to configure audio session: \(errorDesc)")
        }
    }

    /// Fallback: Configures the audio session directly when `audioService` is nil.
    ///
    /// ## Performance
    /// `AVAudioSession.setCategory()` and `setActive()` are synchronous blocking calls
    /// that take 50–200ms for HAL driver reconfiguration. These are dispatched to a
    /// background queue to keep MainActor free for animations during the TTS→listening
    /// transition.
    ///
    /// ## Retry Strategy
    /// - **Attempt 1**: Immediate — no delay. TTS playback has already completed by the
    ///   time this runs, so the audio session is typically available.
    /// - **Attempt 2**: 250ms delay — handles transient conflicts from recent TTS teardown.
    /// - **Attempt 3**: 500ms delay — handles slower hardware reconfiguration.
    private func configureAudioSessionFallback() async throws {
        let retryDelays: [UInt64] = [0, 250, 500]
        var lastError: Error?

        for (attempt, delayMs) in retryDelays.enumerated() {
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let session = AVAudioSession.sharedInstance()
                            try session.setCategory(
                                .playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
                            )
                            try session.setActive(true, options: .notifyOthersOnDeactivation)

                            #if DEBUG
                            AppLogger.debug("Audio session configured (fallback, attempt \(attempt + 1)) - Sample rate: \(session.sampleRate)", category: .speech)
                            #endif

                            continuation.resume()
                        } catch {
                            #if DEBUG
                            AppLogger.debug("Audio session config attempt \(attempt + 1)/\(retryDelays.count) failed: \(error.localizedDescription)", category: .speech)
                            #endif
                            continuation.resume(throwing: error)
                        }
                    }
                }
                return
            } catch {
                lastError = error
            }
        }

        let errorDesc = lastError?.localizedDescription ?? ""
        if errorDesc.contains("561017449") || errorDesc.contains("!pri") {
            throw CaptureError.audioSessionUnavailable
        }

        throw CaptureError.audioEngineFailure("Failed to configure audio session: \(errorDesc)")
    }

    /// Starts the recognition pipeline using the appropriate engine.
    ///
    /// When `audioService` is available, installs an input tap on the shared
    /// engine's `inputNode` — no new engine is created.
    ///
    /// When `audioService` is nil (fallback), creates a standalone engine.
    ///
    /// ## Performance
    /// Heavy work is dispatched to a background queue to keep MainActor
    /// free for animations.
    private func startCapturePipeline() async throws {
        guard let recognizer = speechRecognizer else {
            throw CaptureError.speechRecognizerUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CaptureError.audioEngineFailure("Service deallocated during setup"))
                    return
                }

                do {
                    // Determine which engine to use for the input node
                    let inputNode: AVAudioInputNode
                    if self.usesSharedEngine, let audioService = self.audioService {
                        // Use the shared engine's input node — no new engine needed
                        inputNode = audioService.sharedEngine.inputNode
                    } else {
                        // Fallback: create a standalone engine
                        let engine = AVAudioEngine()
                        inputNode = engine.inputNode
                        self.fallbackAudioEngine = engine
                    }

                    // CRITICAL: Use the input node's native format, not a custom format.
                    // This prevents format mismatch crashes when audio route changes.
                    var recordingFormat = inputNode.outputFormat(forBus: 0)

                    if recordingFormat.sampleRate == 0 {
                        // Audio session likely in a transient state.
                        // Wait briefly and retry once.
                        Thread.sleep(forTimeInterval: 0.1)
                        recordingFormat = inputNode.outputFormat(forBus: 0)
                    }

                    guard recordingFormat.sampleRate > 0 else {
                        throw CaptureError.audioEngineFailure("Invalid input format: sample rate is 0")
                    }

                    #if DEBUG
                    AppLogger.debug("Recording format - \(Int(recordingFormat.sampleRate)) Hz, \(recordingFormat.channelCount) ch", category: .speech)
                    #endif

                    // Create recognition request
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true

                    if recognizer.supportsOnDeviceRecognition {
                        request.requiresOnDeviceRecognition = true
                        #if DEBUG
                        AppLogger.debug("Using on-device recognition (low latency)", category: .speech)
                        #endif
                    } else {
                        request.requiresOnDeviceRecognition = false
                        #if DEBUG
                        AppLogger.debug("On-device unavailable — falling back to cloud recognition", category: .speech)
                        #endif
                    }

                    if #available(iOS 17.0, *) {
                        request.addsPunctuation = false
                    }

                    if let hints = self.contextualStrings, !hints.isEmpty {
                        request.contextualStrings = Array(hints.prefix(100))
                        #if DEBUG
                        AppLogger.debug("Added \(min(hints.count, 100)) contextual strings", category: .speech)
                        #endif
                    }

                    // Start recognition task
                    let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                        Task { @MainActor in
                            self?.handleRecognitionResult(result, error: error)
                        }
                    }

                    // Install tap with the NATIVE format
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                        // Append buffer to recognition request
                        request.append(buffer)

                        // Calculate audio level on MainActor
                        Task { @MainActor in
                            self?.processAudioLevel(buffer: buffer)
                        }
                    }

                    // If using fallback engine, prepare and start it
                    if let fallbackEngine = self.fallbackAudioEngine, !self.usesSharedEngine {
                        fallbackEngine.prepare()
                        do {
                            try fallbackEngine.start()
                        } catch {
                            inputNode.removeTap(onBus: 0)
                            task.cancel()
                            throw CaptureError.audioEngineFailure("Failed to start audio engine: \(error.localizedDescription)")
                        }
                    }
                    // Shared engine is already running — no start needed

                    // Store pipeline components
                    self.recognitionRequest = request
                    self.recognitionTask = task

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Handles recognition results from SFSpeechRecognizer
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        // Handle errors
        if let error = error {
            let nsError = error as NSError

            // Ignore cancellation errors (code 216)
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                return
            }

            // Ignore "no speech detected" errors (code 1110)
            if nsError.code == 1110 {
                #if DEBUG
                AppLogger.debug("No speech detected (expected)", category: .speech)
                #endif
                return
            }

            // Ignore rate limit errors (code 1101) - just log once
            if nsError.code == 1101 {
                #if DEBUG
                AppLogger.debug("Rate limited by iOS speech service (1101)", category: .speech)
                #endif
                return
            }

            AppLogger.error("Recognition error - \(error.localizedDescription)", category: .speech, error: error)

            emit(.error(.recognitionFailure(error.localizedDescription)))
            return
        }

        guard let result = result else { return }

        // Get transcription and per-word segment data
        let transcription = result.bestTranscription.formattedString
        let segments = result.bestTranscription.segments.map { segment in
            RecognizedSegment(
                substring: segment.substring,
                timestamp: segment.timestamp,
                duration: segment.duration,
                confidence: segment.confidence,
                alternatives: segment.alternativeSubstrings
            )
        }
        currentTranscription = transcription

        // Update last speech time
        lastSpeechTime = Date()

        // Emit transcription update with segment data
        emit(.transcription(text: transcription, isFinal: result.isFinal, segments: segments))

        #if DEBUG
        if result.isFinal {
            AppLogger.debug("Final transcription - \"\(transcription)\"", category: .speech)
        } else if !transcription.isEmpty {
            AppLogger.debug("Partial - \"\(transcription)\"", category: .speech)
        }
        #endif
    }

    /// Processes audio buffer for level metering
    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Calculate RMS
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Smooth the level
        smoothedLevel = (smoothingFactor * rms) + ((1 - smoothingFactor) * smoothedLevel)

        // Convert to normalized level (0-1)
        // RMS of speech typically ranges from 0.01 to 0.3
        let normalizedLevel = min(1.0, smoothedLevel * 5)

        emit(.audioLevel(normalizedLevel))
    }

    /// Starts monitoring for silence
    private func startSilenceMonitoring() {
        silenceTimer?.cancel()

        silenceTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))

                guard let self = self, self.isCapturing else { break }

                await MainActor.run {
                    self.checkSilence()
                }
            }
        }
    }

    /// Checks for silence and emits event if threshold exceeded
    private func checkSilence() {
        guard let lastSpeech = lastSpeechTime else { return }

        let silenceDuration = Date().timeIntervalSince(lastSpeech)

        // Only emit silence if we haven't received speech recently
        // and audio level is low
        // NOTE: We emit continuously so PracticeStore can track duration.
        // lastSpeechTime is ONLY reset when actual transcription is received.
        if silenceDuration >= silenceThreshold && smoothedLevel < 0.02 {
            emit(.silenceDetected(duration: silenceDuration))
            // DO NOT reset lastSpeechTime here - let duration accumulate!
        }
    }

    /// Sets up observers for audio route changes and interruptions
    private func setupObservers() {
        // Remove existing observers
        removeObservers()

        // Route change observer
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }

        // Interruption observer
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    /// Handles audio route changes (e.g., headphones plugged in)
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        #if DEBUG
        let reasonName: String
        switch reason {
        case .unknown: reasonName = "unknown"
        case .newDeviceAvailable: reasonName = "newDeviceAvailable"
        case .oldDeviceUnavailable: reasonName = "oldDeviceUnavailable"
        case .categoryChange: reasonName = "categoryChange"
        case .override: reasonName = "override"
        case .wakeFromSleep: reasonName = "wakeFromSleep"
        case .noSuitableRouteForCategory: reasonName = "noSuitableRouteForCategory"
        case .routeConfigurationChange: reasonName = "routeConfigurationChange"
        @unknown default: reasonName = "unknown(\(reason.rawValue))"
        }
        AppLogger.debug("Route change - \(reasonName)", category: .speech)
        #endif

        // CRITICAL FIX: Let AVAudioEngine handle route changes automatically!
        // AVAudioEngine is designed to handle device changes seamlessly.
        // We should only intervene if the engine actually stops or fails.
        switch reason {
        case .newDeviceAvailable:
            // New device connected (e.g., AirPods) - engine handles this automatically
            #if DEBUG
            AppLogger.debug("Device connected - audio engine handles seamlessly", category: .speech)
            #endif
            // Do NOT cancel! Let engine continue with new device.

        case .oldDeviceUnavailable:
            // Device disconnected (e.g., AirPods removed) - may need to verify engine
            #if DEBUG
            AppLogger.debug("Device disconnected - verifying engine state", category: .speech)
            #endif

            if isCapturing {
                // Give the engine a moment to reconfigure, then verify it's still running
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))

                    guard self.isCapturing else { return }

                    // Check if engine stopped after route change
                    let engineRunning: Bool
                    if self.usesSharedEngine, let audioService = self.audioService {
                        engineRunning = audioService.sharedEngine.isRunning
                    } else {
                        engineRunning = self.fallbackAudioEngine?.isRunning ?? false
                    }

                    if !engineRunning {
                        AppLogger.warning("Engine stopped after device disconnect", category: .speech)
                        self.streamContinuation?.yield(.error(.audioEngineFailure("Audio device disconnected")))
                        self.cancelCapture()
                    } else {
                        #if DEBUG
                        AppLogger.debug("Engine still running after device change", category: .speech)
                        #endif
                    }
                }
            }

        case .categoryChange:
            // IGNORE: This is triggered by our own setCategory() call.
            // Restarting here causes infinite restart loops!
            #if DEBUG
            AppLogger.debug("Ignoring categoryChange (self-triggered)", category: .speech)
            #endif

        default:
            // Other reasons don't typically require restart
            break
        }
    }

    /// Handles audio session interruptions (e.g., phone call)
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        #if DEBUG
        AppLogger.debug("Interruption - \(type == .began ? "began" : "ended")", category: .speech)
        #endif

        switch type {
        case .began:
            // Pause capture
            cancelCapture()

        case .ended:
            // Check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    Task { @MainActor in
                        try? await self.startCapture()
                    }
                }
            }

        @unknown default:
            break
        }
    }

    /// Removes notification observers
    private func removeObservers() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }

        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    /// Emits an update to the stream
    private func emit(_ update: CaptureUpdate) {
        streamContinuation?.yield(update)
    }

    /// Cleans up all resources
    private func cleanup() {
        cancelCapture()
        removeObservers()
        streamContinuation?.finish()
        streamContinuation = nil
        streamGeneration = 0
    }
}

// NOTE: Convenience extensions for CaptureUpdate (isTranscription,
// transcriptionText, isFinalTranscription) are now on the top-level
// SpeechCaptureUpdate type in SpeechCaptureServiceProtocol.swift.
