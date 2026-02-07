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
/// try await service.startCapture()
///
/// for await update in service.captureStream {
///     switch update {
///     case .transcription(let text, let isFinal):
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
    
    /// Audio engine for microphone capture
    /// Note: nonisolated(unsafe) allows access in deinit
    nonisolated(unsafe) private var audioEngine: AVAudioEngine?
    
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
    
    /// Stream continuation for emitting updates
    nonisolated(unsafe) private var streamContinuation: AsyncStream<CaptureUpdate>.Continuation?
    
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
        
        if let engine = audioEngine {
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
                service.streamContinuation = continuation
                
                #if DEBUG
                AppLogger.debug("Stream continuation set", category: .speech)
                #endif
            }
            
            // Handle stream termination
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    service.streamContinuation = nil
                    #if DEBUG
                    AppLogger.debug("Stream terminated", category: .speech)
                    #endif
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
        
        // Configure audio session
        try await configureAudioSession()
        
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
        
        // Stop audio engine
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        isCapturing = false
        
        // End signpost interval
        endCaptureSignpost()
        
        emit(.stopped)

        // Best-effort pre-warm: restore audio session to .playback for TTS.
        // This is fire-and-forget — it may complete before the next playback
        // call or it may not. AudioPlayerService.ensurePlaybackCategory() is
        // the definitive fallback that awaits completion before playback.
        // If this dispatch completes first, ensurePlaybackCategory() becomes
        // a no-op (~0ms) since the category is already .playback.
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            if session.category == .playAndRecord {
                try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
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

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil

        isCapturing = false
        currentTranscription = ""

        // End signpost interval
        endCaptureSignpost()

        emit(.stopped)

        // Best-effort pre-warm: restore audio session to .playback for TTS.
        // This is fire-and-forget — it may complete before the next playback
        // call or it may not. AudioPlayerService.ensurePlaybackCategory() is
        // the definitive fallback that awaits completion before playback.
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            if session.category == .playAndRecord {
                try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
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
    
    /// Configures the audio session for recording.
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
    private func configureAudioSession() async throws {
        // Total attempts: immediate + 2 retries with increasing back-off.
        // Only delay BEFORE retries, not before the first attempt.
        let retryDelays: [UInt64] = [0, 250, 500] // milliseconds
        var lastError: Error?
        
        for (attempt, delayMs) in retryDelays.enumerated() {
            // Delay before retries only (first attempt is immediate)
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            
            do {
                // Dispatch blocking audio session calls to a background queue.
                // setCategory() triggers HAL driver reconfiguration (50-200ms synchronous).
                // setActive() acquires hardware resources (10-50ms synchronous).
                // Running these off MainActor prevents animation frame drops.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let session = AVAudioSession.sharedInstance()
                            try session.setCategory(
                                .playAndRecord,
                                mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetoothHFP]
                            )
                            try session.setActive(true, options: .notifyOthersOnDeactivation)
                            
                            #if DEBUG
                            AppLogger.debug("Audio session configured (attempt \(attempt + 1)) - Sample rate: \(session.sampleRate)", category: .speech)
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
                return // Success
            } catch {
                lastError = error
            }
        }
        
        // All retries exhausted — determine if a competing app holds the session.
        // OSStatus 561017449 ('!pri') = another app has audio session priority.
        let errorDesc = lastError?.localizedDescription ?? ""
        if errorDesc.contains("561017449") || errorDesc.contains("!pri") {
            throw CaptureError.audioSessionUnavailable
        }
        
        throw CaptureError.audioEngineFailure("Failed to configure audio session: \(errorDesc)")
    }
    
    /// Starts the audio engine and recognition pipeline.
    ///
    /// ## Performance
    /// `AVAudioEngine` allocation, `prepare()`, and `start()` are synchronous operations
    /// that take 50–150ms total. `SFSpeechRecognizer.recognitionTask(with:)` also blocks
    /// briefly. All heavy work is dispatched to a background queue to keep MainActor
    /// free for animations.
    ///
    /// Pipeline components are assigned to `nonisolated(unsafe)` properties from the
    /// background queue. This is safe because the flow is sequential — the continuation
    /// resumes only after all assignments complete, and no other code accesses these
    /// properties during setup.
    private func startCapturePipeline() async throws {
        guard let recognizer = speechRecognizer else {
            throw CaptureError.speechRecognizerUnavailable
        }
        
        // Dispatch heavy audio pipeline setup to a background queue.
        // This frees MainActor for ~100-150ms of animation frames.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CaptureError.audioEngineFailure("Service deallocated during setup"))
                    return
                }
                
                do {
                    // Create fresh audio engine
                    let engine = AVAudioEngine()
                    
                    // Get the input node and its NATIVE format
                    let inputNode = engine.inputNode
                    
                    // CRITICAL: Use the input node's native format, not a custom format
                    // This prevents format mismatch crashes when audio route changes
                    let recordingFormat = inputNode.outputFormat(forBus: 0)
                    
                    guard recordingFormat.sampleRate > 0 else {
                        throw CaptureError.audioEngineFailure("Invalid input format: sample rate is 0")
                    }
                    
                    #if DEBUG
                    AppLogger.debug("Recording format - \(Int(recordingFormat.sampleRate)) Hz, \(recordingFormat.channelCount) ch", category: .speech)
                    #endif
                    
                    // Create recognition request
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    request.requiresOnDeviceRecognition = false // Cloud for better accuracy
                    
                    if #available(iOS 17.0, *) {
                        request.addsPunctuation = true
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
                    
                    // Prepare and start engine
                    engine.prepare()
                    
                    do {
                        try engine.start()
                    } catch {
                        // Clean up tap and recognition task on engine start failure
                        inputNode.removeTap(onBus: 0)
                        task.cancel()
                        throw CaptureError.audioEngineFailure("Failed to start audio engine: \(error.localizedDescription)")
                    }
                    
                    // Store pipeline components on nonisolated(unsafe) properties.
                    // Safe: sequential flow — continuation resumes only after these writes,
                    // and no other code accesses these properties during setup.
                    self.audioEngine = engine
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
        
        // Get transcription
        let transcription = result.bestTranscription.formattedString
        currentTranscription = transcription
        
        // Update last speech time
        lastSpeechTime = Date()
        
        // Emit transcription update
        emit(.transcription(text: transcription, isFinal: result.isFinal))
        
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
                    let engineRunning = self.audioEngine?.isRunning ?? false
                    if !engineRunning {
                        // Engine stopped after device removal - emit error
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
    }
}

// NOTE: Convenience extensions for CaptureUpdate (isTranscription,
// transcriptionText, isFinalTranscription) are now on the top-level
// SpeechCaptureUpdate type in SpeechCaptureServiceProtocol.swift.
