//
//  SpeechCaptureService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/9/26.
//

import AVFoundation
@preconcurrency import Speech
import os.signpost

// MARK: - SpeechCaptureService

/// Dumb pipe for speech capture and recognition.
///
/// ## Architecture
/// Owns a standalone `AVAudioEngine` for mic capture and maintains a
/// session-long `SFSpeechRecognitionTask`. Streams the **full cumulative**
/// recognized text on every partial result via ``captureStream``. The service
/// knows nothing about affirmation segments or word matching — consumers
/// (e.g., `PracticeStore`) handle all matching logic.
///
/// ## Session-Long Recognition Task
/// Maintains a **single recognition task for the entire practice session**.
/// The engine and recognition request are created once on the first
/// ``startCapture()`` call. The input **tap** is installed per-listening-phase
/// in ``installTap()`` and removed in ``removeTap()``. This ensures:
/// - Mic hardware is only active during listening (iOS orange indicator off between phases)
/// - Bluetooth returns to A2DP quality between listening phases
/// - The session-long task survives tap removal (recreated if it expires)
///
/// ## Mic Lifecycle
/// - ``startCapture()``: Installs tap → mic ON (iOS orange indicator appears)
/// - ``stopCapture()``: Removes tap → mic OFF (indicator disappears)
/// - ``releaseEngine()``: Full teardown at session end
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
///         print("Heard: \(text)")
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

    /// The shared audio service for session controller access.
    ///
    /// **Must** be set before calling ``startCapture()``. The capture service
    /// verifies the audio session is active via the session controller. Mic
    /// capture uses a standalone `AVAudioEngine` — the shared engine is
    /// NOT used for input taps.
    weak var audioService: (any AudioServiceProtocol)?

    /// Persistent capture engine kept alive across the entire session.
    ///
    /// Created on the first `startCapture()` call with `prepare()` + `start()`.
    /// Reused across all listening phases until ``releaseEngine()`` is called.
    nonisolated(unsafe) private var captureEngine: AVAudioEngine?

    /// Whether an input tap is currently installed on the capture engine.
    ///
    /// Tracks tap state for the per-phase mic lifecycle. The tap is
    /// installed in ``installTap()`` and removed in ``removeTap()``.
    /// When `false`, mic hardware is deactivated (iOS orange indicator off).
    nonisolated(unsafe) private var tapInstalled: Bool = false

    /// Speech recognizer.
    private let speechRecognizer: SFSpeechRecognizer?

    /// Session-long recognition request. Stays alive across listening phases.
    nonisolated(unsafe) private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// Session-long recognition task. Stays alive across listening phases.
    nonisolated(unsafe) private var recognitionTask: SFSpeechRecognitionTask?

    /// Whether a listening phase is currently active (mic is ON).
    private(set) var isCapturing: Bool = false

    /// The current cumulative transcription text from the session-long task.
    private(set) var currentTranscription: String = ""

    /// Whether a session-long recognition task has been prepared.
    ///
    /// Set to `true` after ``startCapturePipeline()`` succeeds.
    /// Reset to `false` in ``releaseEngine()``.
    private(set) var hasSessionRecognitionTask: Bool = false

    // MARK: - Contextual Strings

    /// Contextual string hints for the session-long recognition request.
    ///
    /// Set once before the first ``startCapture()`` call with ALL session
    /// affirmation words (capped at 500, sorted by frequency — most common
    /// words first). Applied to the single session-long recognition request.
    nonisolated(unsafe) var sessionContextualStrings: [String]?

    // MARK: - Stream & Observers

    /// Stream continuation for emitting updates.
    nonisolated(unsafe) private var streamContinuation: AsyncStream<CaptureUpdate>.Continuation?

    /// Monotonic generation counter for stream lifecycle management.
    ///
    /// Incremented each time `captureStream` creates a new `AsyncStream`.
    /// The `onTermination` handler captures the generation at creation time
    /// and only nils `streamContinuation` if the generation still matches.
    /// This prevents a stale stream's termination from clearing a newer stream's
    /// continuation — the root cause of word highlighting breaking on replay.
    nonisolated(unsafe) private var streamGeneration: Int = 0

    /// Route change observer.
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?

    /// Interruption observer.
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    // MARK: - Silence & Audio Level

    /// Silence tracking.
    private var lastSpeechTime: Date?
    nonisolated(unsafe) private var silenceTimer: Task<Void, Never>?
    private let silenceThreshold: TimeInterval = 1.5

    /// Audio level smoothing.
    private var smoothedLevel: Float = 0
    private let smoothingFactor: Float = 0.3

    /// Signpost ID for current capture session (for proper begin/end pairing).
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

        // Clean up the standalone capture engine if still active.
        if let engine = captureEngine {
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

    /// Stream of capture updates.
    ///
    /// Subscribe to receive real-time updates including:
    /// - Transcription progress (full cumulative text)
    /// - Audio levels
    /// - Silence detection
    /// - Errors
    nonisolated var captureStream: AsyncStream<CaptureUpdate> {
        AsyncStream { continuation in
            let service = self

            Task { @MainActor in
                service.streamGeneration += 1
                let currentGeneration = service.streamGeneration
                service.streamContinuation = continuation

                #if DEBUG
                AppLogger.debug("Stream continuation set (generation \(currentGeneration))", category: .speech)
                #endif

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

    /// Requests microphone permission.
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Requests speech recognition permission.
    func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Whether microphone permission is granted.
    var hasMicrophonePermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Whether speech recognition permission is granted.
    var hasSpeechRecognitionPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Capture Control

    /// Starts audio capture and speech recognition.
    ///
    /// On the first call per session, creates the standalone capture engine
    /// and a session-long recognition task. Subsequent calls reuse the
    /// existing task and only install the input tap (mic ON).
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

        // Begin signpost interval
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

        // SESSION-LONG TASK: Only create the recognition pipeline once.
        // First call per session creates engine + task (one-time cost).
        // Subsequent calls skip straight to installTap() — zero disruption.
        if !hasSessionRecognitionTask {
            // Verify audio session is active (AudioService.start() must be called first)
            guard let audioService = audioService,
                  audioService.sessionController.isSessionActive else {
                endCaptureSignpost()
                throw CaptureError.audioEngineFailure("Audio session not active — AudioService.start() must be called first")
            }

            // Setup observers
            setupObservers()

            // Start the capture pipeline (creates engine + task)
            try await startCapturePipeline()
        } else {
            #if DEBUG
            AppLogger.debug("Reusing session recognition task (zero audio disruption)", category: .speech)
            #endif
        }

        // Install input tap (mic ON)
        installTap()

        #if DEBUG
        AppLogger.debug("Capture started successfully", category: .speech)
        #endif
    }

    /// Stops capture and removes the input tap (mic OFF).
    ///
    /// The session-long recognition task stays alive. Call
    /// ``releaseEngine()`` at session end to fully tear down.
    func stopCapture() {
        guard isCapturing else { return }

        #if DEBUG
        AppLogger.debug("Stopping capture...", category: .speech)
        #endif

        removeTap()

        #if DEBUG
        AppLogger.debug("Capture stopped. Transcription: \"\(currentTranscription)\"", category: .speech)
        #endif
    }

    /// Cancels capture without returning a result.
    ///
    /// Removes the input tap (mic OFF). The session-long recognition task
    /// stays alive for the next ``startCapture()`` call.
    func cancelCapture() {
        guard isCapturing else { return }

        #if DEBUG
        AppLogger.debug("Cancelling capture...", category: .speech)
        #endif

        removeTap()
        currentTranscription = ""
    }

    /// Releases the capture engine and recognition task.
    ///
    /// Full teardown: cancels the recognition task, removes the input tap,
    /// stops the engine, and resets all session state. Call at session end.
    /// Safe to call multiple times.
    func releaseEngine() {
        if isCapturing { cancelCapture() }

        // Cancel the session-long recognition task
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        hasSessionRecognitionTask = false

        // Reset session state
        sessionContextualStrings = nil
        currentTranscription = ""

        // Tear down engine and tap
        if let engine = captureEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        captureEngine = nil
        tapInstalled = false

        #if DEBUG
        AppLogger.debug("Capture engine released — mic hardware deactivated", category: .speech)
        #endif
    }

    // MARK: - Tap Lifecycle

    /// Installs an input tap on the capture engine (mic ON).
    ///
    /// Activates mic hardware, starts forwarding audio buffers to the
    /// session-long recognition request, begins silence monitoring, and
    /// emits `.started`.
    private func installTap() {
        // Install tap on capture engine to activate mic hardware
        if let engine = captureEngine, !tapInstalled {
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 else {
                #if DEBUG
                AppLogger.warning("Cannot install tap: invalid format (0 Hz)", category: .speech)
                #endif
                // Continue without tap — silence detector will eventually time out
                isCapturing = true
                currentTranscription = ""
                lastSpeechTime = Date()
                startSilenceMonitoring()
                emit(.started)
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }

                // Forward buffers to the session-long recognition request
                self.recognitionRequest?.append(buffer)

                // Only dispatch audio level updates during active capture
                if self.isCapturing {
                    Task { @MainActor in
                        self.processAudioLevel(buffer: buffer)
                    }
                }
            }
            tapInstalled = true

            #if DEBUG
            AppLogger.debug("Tap installed (mic ON)", category: .speech)
            #endif
        }

        isCapturing = true
        currentTranscription = ""
        smoothedLevel = 0
        lastSpeechTime = Date()

        // Start silence monitoring
        startSilenceMonitoring()

        emit(.started)
    }

    /// Removes the input tap from the capture engine (mic OFF).
    ///
    /// Deactivates mic hardware, stops silence monitoring, and emits `.stopped`.
    /// The session-long recognition task stays alive.
    private func removeTap() {
        // Stop silence monitoring
        silenceTimer?.cancel()
        silenceTimer = nil

        isCapturing = false
        smoothedLevel = 0

        // Remove tap from capture engine to deactivate mic hardware
        if tapInstalled, let engine = captureEngine {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false

            #if DEBUG
            AppLogger.debug("Tap removed (mic OFF)", category: .speech)
            #endif
        }

        // End signpost interval
        endCaptureSignpost()

        emit(.stopped)
    }

    // MARK: - Private Methods

    /// Ends the capture signpost interval if one is active.
    private func endCaptureSignpost() {
        if let signpostID = captureSignpostID {
            AppLogger.endInterval(AppLogger.SignpostName.speechCapture, id: signpostID, category: .speech)
            captureSignpostID = nil
        }
    }

    /// Creates the session-long recognition pipeline.
    ///
    /// Creates a standalone `AVAudioEngine` and ONE
    /// `SFSpeechAudioBufferRecognitionRequest` + task that stays alive
    /// for the entire session. This is a one-time cost — subsequent
    /// ``startCapture()`` calls only install the input tap.
    ///
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
                    // Reuse existing engine if already running
                    let engine: AVAudioEngine
                    let needsStart: Bool

                    if let existing = self.captureEngine, existing.isRunning {
                        engine = existing
                        needsStart = false
                        #if DEBUG
                        AppLogger.debug("Reusing persistent capture engine", category: .speech)
                        #endif
                    } else {
                        engine = AVAudioEngine()
                        needsStart = true
                        #if DEBUG
                        AppLogger.debug("Creating new capture engine", category: .speech)
                        #endif
                    }

                    let inputNode = engine.inputNode

                    // Use the input node's native format to prevent format mismatch crashes
                    var recordingFormat = inputNode.outputFormat(forBus: 0)

                    if recordingFormat.sampleRate == 0 {
                        // Audio session may be in a transient state. Wait briefly and retry.
                        Thread.sleep(forTimeInterval: 0.1)
                        recordingFormat = inputNode.outputFormat(forBus: 0)
                    }

                    guard recordingFormat.sampleRate > 0 else {
                        throw CaptureError.audioEngineFailure("Invalid input format: sample rate is 0")
                    }

                    #if DEBUG
                    AppLogger.debug("Recording format - \(Int(recordingFormat.sampleRate)) Hz, \(recordingFormat.channelCount) ch", category: .speech)
                    #endif

                    // Create the session-long recognition request
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true

                    // Prefer on-device for low-latency partial results
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

                    // Disable punctuation — SequentialWordMatcher strips it anyway
                    if #available(iOS 17.0, *) {
                        request.addsPunctuation = false
                    }

                    // Apply contextual string hints
                    if let hints = self.sessionContextualStrings, !hints.isEmpty {
                        request.contextualStrings = Array(hints.prefix(500))
                        #if DEBUG
                        AppLogger.debug("Added \(min(hints.count, 500)) contextual strings", category: .speech)
                        #endif
                    }

                    // Create the session-long recognition task
                    let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                        Task { @MainActor in
                            self?.handleRecognitionResult(result, error: error)
                        }
                    }

                    // Store request and task for the session's lifetime
                    self.recognitionRequest = request
                    self.recognitionTask = task

                    // Only prepare/start if this is a new engine
                    if needsStart {
                        engine.prepare()

                        do {
                            try engine.start()
                        } catch {
                            task.cancel()
                            self.recognitionRequest = nil
                            self.recognitionTask = nil
                            throw CaptureError.audioEngineFailure("Failed to start audio engine: \(error.localizedDescription)")
                        }

                        self.captureEngine = engine
                    }

                    self.hasSessionRecognitionTask = true

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Handles recognition results from the session-long task.
    ///
    /// Emits the **full cumulative text** from the recognizer on every
    /// partial result. Only emits when ``isCapturing`` is true (mic is ON).
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        // Handle errors
        if let error = error {
            let nsError = error as NSError

            // Ignore cancellation errors (code 216)
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                if hasSessionRecognitionTask && recognitionTask != nil {
                    #if DEBUG
                    AppLogger.debug("Session recognition task expired (216) — will recreate on next capture", category: .speech)
                    #endif
                    hasSessionRecognitionTask = false
                    recognitionTask = nil
                    recognitionRequest = nil

                    // If mid-capture, recreate task transparently
                    if isCapturing {
                        Task { @MainActor in
                            await self.recreateSessionTask()
                        }
                    }
                }
                return
            }

            // Ignore "no speech detected" errors (code 1110)
            if nsError.code == 1110 {
                #if DEBUG
                AppLogger.debug("No speech detected (expected)", category: .speech)
                #endif
                if hasSessionRecognitionTask {
                    hasSessionRecognitionTask = false
                    recognitionTask = nil
                    recognitionRequest = nil

                    if isCapturing {
                        Task { @MainActor in
                            await self.recreateSessionTask()
                        }
                    }
                }
                return
            }

            // Ignore rate limit errors (code 1101)
            if nsError.code == 1101 {
                #if DEBUG
                AppLogger.debug("Rate limited by iOS speech service (1101)", category: .speech)
                #endif
                return
            }

            AppLogger.error("Recognition error - \(error.localizedDescription)", category: .speech, error: error)

            // Only emit errors during active capture
            if isCapturing {
                emit(.error(.recognitionFailure(error.localizedDescription)))
            }
            return
        }

        guard let result = result else { return }

        // Only emit transcription events during active capture (mic ON)
        guard isCapturing else { return }

        // Build segments from the recognizer result
        let segments = result.bestTranscription.segments.map { segment in
            RecognizedSegment(
                substring: segment.substring,
                timestamp: segment.timestamp,
                duration: segment.duration,
                confidence: segment.confidence,
                alternatives: segment.alternativeSubstrings
            )
        }

        // Full cumulative text from the session-long task
        let fullText = result.bestTranscription.formattedString

        currentTranscription = fullText

        // Update last speech time
        if !fullText.isEmpty {
            lastSpeechTime = Date()
        }

        // Emit full cumulative transcription
        emit(.transcription(text: fullText, isFinal: result.isFinal, segments: segments))

        #if DEBUG
        if result.isFinal {
            AppLogger.debug("Final - \"\(fullText)\"", category: .speech)
        } else if !fullText.isEmpty {
            AppLogger.debug("Partial - \"\(fullText)\"", category: .speech)
        }
        #endif
    }

    /// Recreates the session-long recognition task after expiration.
    ///
    /// Called when the Speech framework terminates the task (e.g., 60-second
    /// limit). This is a rare event — at most once per session.
    private func recreateSessionTask() async {
        #if DEBUG
        AppLogger.debug("Recreating expired session recognition task...", category: .speech)
        #endif

        do {
            try await startCapturePipeline()
        } catch {
            AppLogger.error("Failed to recreate session task: \(error.localizedDescription)", category: .speech, error: error)
            emit(.error(.audioEngineFailure("Recognition task expired and could not be recreated")))
        }
    }

    /// Processes audio buffer for level metering.
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

    /// Starts monitoring for silence.
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

    /// Checks for silence and emits event if threshold exceeded.
    private func checkSilence() {
        guard let lastSpeech = lastSpeechTime else { return }

        let silenceDuration = Date().timeIntervalSince(lastSpeech)

        if silenceDuration >= silenceThreshold && smoothedLevel < 0.02 {
            emit(.silenceDetected(duration: silenceDuration))
        }
    }

    /// Sets up observers for audio route changes and interruptions.
    private func setupObservers() {
        removeObservers()

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }

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

    /// Handles audio route changes (e.g., headphones plugged in).
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

        switch reason {
        case .newDeviceAvailable:
            // New device connected — engine handles this automatically
            #if DEBUG
            AppLogger.debug("Device connected - audio engine handles seamlessly", category: .speech)
            #endif

        case .oldDeviceUnavailable:
            // Device disconnected — verify engine state
            #if DEBUG
            AppLogger.debug("Device disconnected - verifying engine state", category: .speech)
            #endif

            if isCapturing {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))

                    guard self.isCapturing else { return }

                    let engineRunning = self.captureEngine?.isRunning ?? false

                    if !engineRunning {
                        AppLogger.warning("Engine stopped after device disconnect", category: .speech)
                        self.streamContinuation?.yield(.error(.audioEngineFailure("Audio device disconnected")))
                        self.cancelCapture()
                        self.releaseEngine()
                    } else {
                        #if DEBUG
                        AppLogger.debug("Engine still running after device change", category: .speech)
                        #endif
                    }
                }
            } else {
                // Not capturing, but persistent engine may have stopped
                if !(captureEngine?.isRunning ?? true) {
                    releaseEngine()
                    #if DEBUG
                    AppLogger.debug("Idle capture engine stopped after device change — released", category: .speech)
                    #endif
                }
            }

        case .categoryChange:
            // Ignore — triggered by our own setCategory() call
            #if DEBUG
            AppLogger.debug("Ignoring categoryChange (self-triggered)", category: .speech)
            #endif

        default:
            break
        }
    }

    /// Handles audio session interruptions (e.g., phone call).
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
            cancelCapture()
            releaseEngine()

        case .ended:
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

    /// Removes notification observers.
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

    /// Emits an update to the stream.
    private func emit(_ update: CaptureUpdate) {
        streamContinuation?.yield(update)
    }

    /// Cleans up all resources.
    private func cleanup() {
        releaseEngine()
        removeObservers()
        streamContinuation?.finish()
        streamContinuation = nil
        streamGeneration = 0
    }
}
