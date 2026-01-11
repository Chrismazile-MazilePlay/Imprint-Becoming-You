//
//  SpeechCaptureService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/9/26.
//

import AVFoundation
import Speech
import Combine

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
final class SpeechCaptureService: NSObject, @unchecked Sendable {
    
    // MARK: - Types
    
    /// Updates emitted by the capture stream
    enum CaptureUpdate: Sendable {
        /// New transcription text (partial or final)
        case transcription(text: String, isFinal: Bool)
        
        /// Audio level update (0.0 - 1.0 normalized)
        case audioLevel(Float)
        
        /// Silence detected for specified duration
        case silenceDetected(duration: TimeInterval)
        
        /// Error occurred during capture
        case error(CaptureError)
        
        /// Capture started successfully
        case started
        
        /// Capture stopped
        case stopped
    }
    
    /// Errors that can occur during capture
    enum CaptureError: Error, Sendable {
        case microphonePermissionDenied
        case speechRecognitionPermissionDenied
        case speechRecognizerUnavailable
        case audioEngineFailure(String)
        case recognitionFailure(String)
    }
    
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
    
    // MARK: - Initialization
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        super.init()
        
        #if DEBUG
        print("[LOG] SpeechCaptureService: Initialized with locale \(Locale.current.identifier)")
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
                print("[LOG] SpeechCaptureService: Stream continuation set")
                #endif
            }
            
            // Handle stream termination
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    service.streamContinuation = nil
                    #if DEBUG
                    print("[LOG] SpeechCaptureService: Stream terminated")
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
            print("[LOG] SpeechCaptureService: Already capturing, ignoring start request")
            #endif
            return
        }
        
        #if DEBUG
        print("[LOG] SpeechCaptureService: Starting capture...")
        #endif
        
        // Check permissions
        guard hasMicrophonePermission else {
            emit(.error(.microphonePermissionDenied))
            throw CaptureError.microphonePermissionDenied
        }
        
        guard hasSpeechRecognitionPermission else {
            emit(.error(.speechRecognitionPermissionDenied))
            throw CaptureError.speechRecognitionPermissionDenied
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
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
        print("[LOG] SpeechCaptureService: Capture started successfully")
        #endif
    }
    
    /// Stops capture and returns final transcription
    @discardableResult
    func stopCapture() -> String {
        guard isCapturing else { return currentTranscription }
        
        #if DEBUG
        print("[LOG] SpeechCaptureService: Stopping capture...")
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
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        isCapturing = false
        
        emit(.stopped)
        
        #if DEBUG
        print("[LOG] SpeechCaptureService: Capture stopped. Final: \"\(currentTranscription)\"")
        #endif
        
        return currentTranscription
    }
    
    /// Cancels capture without waiting for final result
    func cancelCapture() {
        guard isCapturing else { return }
        
        #if DEBUG
        print("[LOG] SpeechCaptureService: Cancelling capture...")
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
        
        isCapturing = false
        currentTranscription = ""
        
        emit(.stopped)
    }
    
    // MARK: - Private Methods
    
    /// Configures the audio session for recording
    private func configureAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Use playAndRecord to support both TTS and microphone
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            #if DEBUG
            print("[LOG] SpeechCaptureService: Audio session configured - Sample rate: \(session.sampleRate)")
            #endif
        } catch {
            throw CaptureError.audioEngineFailure("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    /// Starts the audio engine and recognition pipeline
    private func startCapturePipeline() async throws {
        // Create fresh audio engine
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        // Get the input node and its NATIVE format
        let inputNode = engine.inputNode
        
        // CRITICAL: Use the input node's native format, not a custom format
        // This prevents format mismatch crashes when audio route changes
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 else {
            throw CaptureError.audioEngineFailure("Invalid input format: sample rate is 0")
        }
        
        #if DEBUG
        print("[LOG] SpeechCaptureService: Recording format - \(Int(recordingFormat.sampleRate)) Hz, \(recordingFormat.channelCount) ch")
        #endif
        
        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false // Cloud for better accuracy
        
        if #available(iOS 17.0, *) {
            request.addsPunctuation = true
        }
        
        self.recognitionRequest = request
        
        // Start recognition task
        guard let recognizer = speechRecognizer else {
            throw CaptureError.speechRecognizerUnavailable
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }
        
        // Install tap with the NATIVE format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            // Append buffer to recognition request
            self?.recognitionRequest?.append(buffer)
            
            // Calculate audio level
            Task { @MainActor in
                self?.processAudioLevel(buffer: buffer)
            }
        }
        
        // Prepare and start engine
        engine.prepare()
        
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw CaptureError.audioEngineFailure("Failed to start audio engine: \(error.localizedDescription)")
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
                print("[LOG] SpeechCaptureService: No speech detected (expected)")
                #endif
                return
            }
            
            // Ignore rate limit errors (code 1101) - just log once
            if nsError.code == 1101 {
                #if DEBUG
                print("[LOG] SpeechCaptureService: Rate limited by iOS speech service (1101)")
                #endif
                return
            }
            
            #if DEBUG
            print("[ERROR] SpeechCaptureService: Recognition error - \(error.localizedDescription)")
            #endif
            
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
            print("[LOG] SpeechCaptureService: Final transcription - \"\(transcription)\"")
        } else if !transcription.isEmpty {
            print("[LOG] SpeechCaptureService: Partial - \"\(transcription)\"")
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
        if silenceDuration >= silenceThreshold && smoothedLevel < 0.02 {
            emit(.silenceDetected(duration: silenceDuration))
            
            // Reset to avoid repeated emissions
            lastSpeechTime = Date()
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
        print("[LOG] SpeechCaptureService: Route change - \(reasonName)")
        #endif
        
        // CRITICAL FIX: Only restart on actual hardware changes!
        // Do NOT restart on .categoryChange - this is triggered by our own
        // setCategory() call and causes an infinite restart loop.
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Hardware actually changed - need to handle gracefully
            if isCapturing {
                #if DEBUG
                print("[LOG] SpeechCaptureService: Hardware change during capture - cancelling (will not auto-restart)")
                #endif
                
                // CHANGED: Instead of restarting, just cancel gracefully.
                // The PracticeStore will handle the interrupted state via the error callback.
                // Attempting to restart mid-capture causes state corruption and crashes.
                Task { @MainActor in
                    // Emit error so PracticeStore knows capture was interrupted
                    self.streamContinuation?.yield(.error(.audioEngineFailure("Audio route changed")))
                    
                    // Cancel capture cleanly
                    self.cancelCapture()
                }
            }
            
        case .categoryChange:
            // IGNORE: This is triggered by our own setCategory() call.
            // Restarting here causes infinite restart loops!
            #if DEBUG
            print("[LOG] SpeechCaptureService: Ignoring categoryChange (self-triggered)")
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
        print("[LOG] SpeechCaptureService: Interruption - \(type == .began ? "began" : "ended")")
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

// MARK: - Convenience Extensions

extension SpeechCaptureService.CaptureUpdate {
    
    /// Whether this is a transcription update
    var isTranscription: Bool {
        if case .transcription = self { return true }
        return false
    }
    
    /// Extracts transcription text if this is a transcription update
    var transcriptionText: String? {
        if case .transcription(let text, _) = self { return text }
        return nil
    }
    
    /// Whether this is a final transcription
    var isFinalTranscription: Bool {
        if case .transcription(_, let isFinal) = self { return isFinal }
        return false
    }
}
