//
//  AudioCoordinator.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/10/26.
//

import AVFoundation
import Speech
import os.log

// MARK: - Logger

/// Centralized logger for audio debugging
private let audioLog = Logger(subsystem: "com.imprint.audio", category: "AudioCoordinator")

// Note: AudioCoordinatorState, AudioCoordinatorError, AudioCoordinatorEvent,
// and AudioRouteChange are defined in AudioCoordinatorState.swift
// Protocols are defined in AudioSessionProviding.swift

// MARK: - AudioCoordinator

/// Central coordinator for all audio operations in Imprint.
///
/// This class is the single source of truth for audio state and handles:
/// - AVAudioSession configuration and lifecycle
/// - System notifications (interruptions, route changes, media reset)
/// - Coordination between TTS, speech recognition, and binaural beats
/// - Graceful recovery from interruptions
///
/// ## SOLID Compliance
/// - **SRP**: Audio session lifecycle management is the primary responsibility
/// - **OCP**: Implements protocols for extensibility
/// - **LSP**: Fully implements all protocol contracts
/// - **ISP**: Implements segregated protocols for different capabilities
/// - **DIP**: Clients depend on protocols, not this concrete class
///
/// ## Usage
/// ```swift
/// let coordinator = AudioCoordinator.shared
///
/// // Play TTS
/// try await coordinator.playTTS("Hello world")
///
/// // Listen for speech
/// try await coordinator.startListening(contextualPhrases: ["I am confident"])
/// for await transcription in coordinator.transcriptionStream { ... }
/// await coordinator.stopListening()
/// ```
@MainActor
final class AudioCoordinator: NSObject, Sendable, FullAudioSessionProviding {
    
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = AudioCoordinator()
    
    // MARK: - Audio Session
    
    /// The underlying audio session
    private let audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - Audio Engines
    
    /// Main audio engine for playback (TTS, binaural)
    private var playbackEngine: AVAudioEngine?
    
    /// Audio engine for recording (speech recognition)
    private var recordingEngine: AVAudioEngine?
    
    // MARK: - TTS
    
    /// Speech synthesizer for system TTS
    private let synthesizer = AVSpeechSynthesizer()
    
    /// Selected TTS voice
    private var selectedVoice: AVSpeechSynthesisVoice?
    
    /// Current TTS utterance
    private var currentUtterance: AVSpeechUtterance?
    
    /// TTS completion continuation
    private var ttsCompletion: CheckedContinuation<Void, Error>?
    
    /// Total word count for current utterance
    private var totalWordCount: Int = 0
    
    /// Words spoken so far
    private var wordsSpoken: Int = 0
    
    // MARK: - Speech Recognition
    
    /// Speech recognizer
    private let speechRecognizer: SFSpeechRecognizer?
    
    /// Current recognition request
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    /// Current recognition task
    private var recognitionTask: SFSpeechRecognitionTask?
    
    /// Transcription stream continuation
    private var transcriptionContinuation: AsyncStream<String>.Continuation?
    
    /// Latest transcription text
    private(set) var currentTranscription: String = ""
    
    // MARK: - Binaural
    
    /// Binaural beat generator
    private var binauralGenerator: StereoBinauralGenerator?
    
    /// Current binaural preset
    private(set) var currentBinauralPreset: BinauralPreset = .off
    
    // MARK: - State
    
    /// Current state
    private(set) var state: AudioCoordinatorState = .idle {
        didSet {
            audioLog.info("🔊 State: \(oldValue.description) → \(self.state.description)")
            eventContinuation?.yield(.stateChanged(state))
        }
    }
    
    /// Whether the audio session is currently active
    private(set) var isSessionActive: Bool = false
    
    /// State before interruption (for recovery) - always stores the ROOT state, never nested interrupted states
    private var stateBeforeInterruption: AudioCoordinatorState?
    
    /// Whether we should resume after interruption
    private var shouldResumeAfterInterruption: Bool = false
    
    // MARK: - Notification Observers
    
    /// Storage for notification observers (nonisolated access for deinit)
    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var routeChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var configurationChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaResetObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaLostObserver: NSObjectProtocol?
    
    // MARK: - Event Stream
    
    /// Continuation for event stream
    private var eventContinuation: AsyncStream<AudioCoordinatorEvent>.Continuation?
    
    /// Stream of coordinator events for UI binding
    lazy var eventStream: AsyncStream<AudioCoordinatorEvent> = {
        AsyncStream { [weak self] continuation in
            self?.eventContinuation = continuation
        }
    }()
    
    // MARK: - Transcription Stream
    
    /// Stream of transcription results
    lazy var transcriptionStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.transcriptionContinuation = continuation
        }
    }()
    
    // MARK: - Initialization
    
    private override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: .current)
        
        super.init()
        
        synthesizer.delegate = self
        selectDefaultVoice()
        setupNotificationObservers()
        
        audioLog.info("✅ AudioCoordinator initialized")
    }
    
    deinit {
        // Remove observers directly using NotificationCenter (nonisolated safe)
        let nc = NotificationCenter.default
        if let observer = interruptionObserver { nc.removeObserver(observer) }
        if let observer = routeChangeObserver { nc.removeObserver(observer) }
        if let observer = configurationChangeObserver { nc.removeObserver(observer) }
        if let observer = mediaResetObserver { nc.removeObserver(observer) }
        if let observer = mediaLostObserver { nc.removeObserver(observer) }
    }
    
    // MARK: - Voice Selection
    
    /// Selects the best available TTS voice
    private func selectDefaultVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Prefer enhanced English voices
        let preferredVoices = voices.filter { voice in
            voice.language.starts(with: "en") && voice.quality == .enhanced
        }
        
        selectedVoice = preferredVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
        
        if let voice = selectedVoice {
            audioLog.info("🎤 Selected voice: \(voice.name) (\(voice.quality == .enhanced ? "Enhanced" : "Default"))")
        }
    }
    
    // MARK: - Notification Setup
    
    private func setupNotificationObservers() {
        let nc = NotificationCenter.default
        
        // Audio session interruption
        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
        
        // Audio route change
        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
        
        // Audio engine configuration change
        configurationChangeObserver = nc.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleConfigurationChange(notification)
            }
        }
        
        // Media services were reset
        mediaResetObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleMediaServicesReset(notification)
            }
        }
        
        // Media services were lost
        mediaLostObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleMediaServicesLost(notification)
            }
        }
        
        audioLog.info("📡 Notification observers registered")
    }
    
    // MARK: - Session Configuration (AudioSessionProviding)
    
    /// Configures audio session for playback (TTS, binaural)
    func configureForPlayback() throws {
        audioLog.info("⚙️ Configuring session for playback")
        
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio, // Optimized for speech
                options: [.duckOthers] // Duck other audio, don't mix
            )
        } catch {
            audioLog.error("❌ Failed to configure playback: \(error.localizedDescription)")
            throw AudioCoordinatorError.sessionConfigurationFailed(error.localizedDescription)
        }
    }
    
    /// Configures audio session for playback and recording (speech recognition while maintaining audio output)
    func configureForPlaybackAndRecording() throws {
        audioLog.info("⚙️ Configuring session for playback and recording")
        
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement, // Best for speech recognition
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
        } catch {
            audioLog.error("❌ Failed to configure playbackAndRecord: \(error.localizedDescription)")
            throw AudioCoordinatorError.sessionConfigurationFailed(error.localizedDescription)
        }
    }
    
    /// Configures audio session for recording only (voice calibration)
    func configureForRecording() throws {
        audioLog.info("⚙️ Configuring session for recording only")
        
        do {
            try audioSession.setCategory(
                .record,
                mode: .measurement, // Best for speech recognition
                options: []
            )
        } catch {
            audioLog.error("❌ Failed to configure recording: \(error.localizedDescription)")
            throw AudioCoordinatorError.sessionConfigurationFailed(error.localizedDescription)
        }
    }
    
    /// Activates the audio session
    func activateSession() throws {
        guard !isSessionActive else {
            audioLog.debug("📢 Session already active")
            return
        }
        
        do {
            try audioSession.setActive(true, options: [])
            isSessionActive = true
            audioLog.info("✅ Audio session activated")
        } catch {
            audioLog.error("❌ Failed to activate session: \(error.localizedDescription)")
            throw AudioCoordinatorError.sessionActivationFailed(error.localizedDescription)
        }
    }
    
    /// Deactivates the audio session
    func deactivateSession(notifyOthers: Bool = true) {
        guard isSessionActive else { return }
        
        do {
            let options: AVAudioSession.SetActiveOptions = notifyOthers ? [.notifyOthersOnDeactivation] : []
            try audioSession.setActive(false, options: options)
            isSessionActive = false
            audioLog.info("✅ Audio session deactivated")
        } catch {
            audioLog.warning("⚠️ Failed to deactivate session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Permissions
    
    /// Whether microphone permission is granted
    var hasMicrophonePermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }
    
    /// Whether speech recognition is authorized
    var hasSpeechRecognitionPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// Requests microphone permission
    func requestMicrophonePermission() async -> Bool {
        audioLog.info("🎙️ Requesting microphone permission")
        let granted = await AVAudioApplication.requestRecordPermission()
        audioLog.info("🎙️ Microphone permission: \(granted ? "granted" : "denied")")
        return granted
    }
    
    /// Requests speech recognition permission
    func requestSpeechRecognitionPermission() async -> Bool {
        audioLog.info("🗣️ Requesting speech recognition permission")
        
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let granted = status == .authorized
                audioLog.info("🗣️ Speech recognition permission: \(granted ? "granted" : "denied")")
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - TTS Operations
    
    /// Plays text-to-speech
    /// - Parameters:
    ///   - text: The text to speak
    ///   - rate: Speech rate (0.0 - 1.0, default 0.5)
    ///   - pitch: Pitch multiplier (0.5 - 2.0, default 1.0)
    /// - Throws: AudioCoordinatorError if TTS fails
    func playTTS(
        _ text: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0
    ) async throws {
        audioLog.info("📊 playTTS called: \"\(text.prefix(50))...\"")
        
        // Check state
        guard state == .idle else {
            audioLog.warning("⚠️ Cannot play TTS - current state: \(self.state)")
            throw AudioCoordinatorError.alreadyInUse(currentState: state.description)
        }
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Configure session
        try configureForPlayback()
        try activateSession()
        
        // Update state
        state = .playingTTS
        
        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        currentUtterance = utterance
        totalWordCount = text.split(separator: " ").count
        wordsSpoken = 0
        
        // Wait for completion
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ttsCompletion = continuation
            synthesizer.speak(utterance)
        }
        
        // Clean up
        currentUtterance = nil
        ttsCompletion = nil
        state = .idle
        deactivateSession()
    }
    
    /// Stops any current TTS playback
    func stopTTS() {
        audioLog.info("📇 stopTTS called")
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Resume completion if waiting
        ttsCompletion?.resume(returning: ())
        ttsCompletion = nil
        currentUtterance = nil
        
        if state == .playingTTS || state == .playingTTSThenListen {
            state = .idle
            deactivateSession()
        }
    }
    
    // MARK: - Speech Recognition Operations
    
    /// Starts listening for speech
    /// - Parameter contextualPhrases: Phrases to boost recognition accuracy (e.g., affirmation text)
    func startListening(contextualPhrases: [String] = []) async throws {
        audioLog.info("👂 startListening called with \(contextualPhrases.count) contextual phrases")
        
        // Check state
        guard state == .idle else {
            audioLog.warning("⚠️ Cannot start listening - current state: \(self.state)")
            throw AudioCoordinatorError.alreadyInUse(currentState: state.description)
        }
        
        // Check permissions
        guard hasMicrophonePermission else {
            audioLog.error("❌ Microphone permission denied")
            throw AudioCoordinatorError.microphonePermissionDenied
        }
        
        guard hasSpeechRecognitionPermission else {
            audioLog.error("❌ Speech recognition permission denied")
            throw AudioCoordinatorError.speechRecognitionPermissionDenied
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            audioLog.error("❌ Speech recognizer not available")
            throw AudioCoordinatorError.ttsNotAvailable
        }
        
        // Configure session for recording
        try configureForRecording()
        try activateSession()
        
        // Create and configure recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false // Allow cloud for better accuracy
        
        // Add contextual phrases to boost recognition
        if !contextualPhrases.isEmpty {
            // Extract individual words from phrases
            var words = Set<String>()
            for phrase in contextualPhrases {
                let phraseWords = phrase.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                words.formUnion(phraseWords)
            }
            // Limit to 100 as per Apple docs
            let limitedWords = Array(words.prefix(100))
            request.contextualStrings = limitedWords
            audioLog.info("📝 Added \(limitedWords.count) contextual strings")
        }
        
        if #available(iOS 17.0, *) {
            request.addsPunctuation = false // We don't need punctuation for word matching
        }
        
        recognitionRequest = request
        currentTranscription = ""
        
        // Create audio engine for recording
        let engine = AVAudioEngine()
        recordingEngine = engine
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 else {
            audioLog.error("❌ Invalid recording format")
            throw AudioCoordinatorError.engineStartFailed("Invalid recording format")
        }
        
        audioLog.info("🎤 Recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) ch")
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }
        
        // Start engine
        do {
            try engine.start()
            state = .listening
            eventContinuation?.yield(.listeningStarted)
            audioLog.info("✅ Recording engine started")
        } catch {
            inputNode.removeTap(onBus: 0)
            recordingEngine = nil
            recognitionRequest = nil
            throw AudioCoordinatorError.engineStartFailed(error.localizedDescription)
        }
    }
    
    /// Stops listening and returns final transcription
    /// - Returns: Final transcription text, or nil if none
    func stopListening() -> String? {
        audioLog.info("🛑 stopListening called")
        
        guard state == .listening else {
            audioLog.debug("Not in listening state, returning current transcription")
            return currentTranscription.isEmpty ? nil : currentTranscription
        }
        
        // Stop recording engine
        if let engine = recordingEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        recordingEngine = nil
        
        // End recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // Finish transcription stream
        transcriptionContinuation?.finish()
        
        // Update state
        state = .idle
        eventContinuation?.yield(.listeningStopped)
        deactivateSession()
        
        let finalText = currentTranscription
        audioLog.info("📜 Final transcription: \"\(finalText.prefix(100))...\"")
        
        return finalText.isEmpty ? nil : finalText
    }
    
    /// Handles recognition results
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            let nsError = error as NSError
            
            // Ignore cancellation errors
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                audioLog.debug("Recognition cancelled (expected)")
                return
            }
            
            audioLog.error("❌ Recognition error: \(error.localizedDescription)")
            return
        }
        
        guard let result = result else { return }
        
        let text = result.bestTranscription.formattedString
        currentTranscription = text
        
        audioLog.debug("📝 Transcription (\(result.isFinal ? "final" : "partial")): \"\(text.prefix(50))...\"")
        
        // Yield to stream
        transcriptionContinuation?.yield(text)
        eventContinuation?.yield(.transcriptionReceived(text))
        
        if result.isFinal {
            transcriptionContinuation?.finish()
        }
    }
    
    // MARK: - Binaural Operations
    
    /// Starts binaural beats with the given preset
    /// - Parameter preset: Binaural preset to use
    func startBinaural(preset: BinauralPreset) {
        audioLog.info("🎵 Starting binaural: \(preset.rawValue)")
        
        guard preset != .off else {
            stopBinaural()
            return
        }
        
        // Initialize generator if needed
        if binauralGenerator == nil {
            binauralGenerator = StereoBinauralGenerator()
        }
        
        binauralGenerator?.start(preset: preset)
        currentBinauralPreset = preset
    }
    
    /// Stops binaural beats
    func stopBinaural() {
        audioLog.info("📇 Stopping binaural")
        binauralGenerator?.stop()
        currentBinauralPreset = .off
    }
    
    /// Changes binaural preset
    func changeBinauralPreset(_ preset: BinauralPreset) {
        audioLog.info("🎵 Changing binaural to: \(preset.rawValue)")
        
        if preset == .off {
            stopBinaural()
        } else {
            binauralGenerator?.changePreset(preset)
            currentBinauralPreset = preset
        }
    }
    
    // MARK: - Current Route Info (AudioRouteProviding)
    
    /// Current audio output route description
    var currentRoute: String {
        audioSession.currentRoute.outputs
            .map { $0.portName }
            .joined(separator: ", ")
    }
    
    /// Whether headphones are connected
    var headphonesConnected: Bool {
        audioSession.currentRoute.outputs.contains { output in
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
                .contains(output.portType)
        }
    }
    
    /// Current hardware sample rate
    var sampleRate: Double {
        audioSession.sampleRate
    }
    
    // MARK: - State Helpers
    
    /// Extracts the root (non-interrupted) state from a potentially nested interrupted state.
    ///
    /// This prevents memory growth from recursive `.interrupted(was: .interrupted(was: ...))` chains.
    ///
    /// - Parameter state: The state to extract the root from
    /// - Returns: The innermost non-interrupted state
    private func extractRootState(from state: AudioCoordinatorState) -> AudioCoordinatorState {
        switch state {
        case .interrupted(let previousState):
            // Recursively extract until we find a non-interrupted state
            return extractRootState(from: previousState)
        default:
            return state
        }
    }
    
    // MARK: - Notification Handlers
    
    /// Handles audio session interruptions
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            audioLog.warning("⚠️ Could not parse interruption notification")
            return
        }
        
        switch type {
        case .began:
            audioLog.warning("⚠️ INTERRUPTION BEGAN")
            
            // Check interruption reason using the modern API (iOS 14.5+)
            if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
               let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
                switch reason {
                case .appWasSuspended:
                    audioLog.debug("Ignoring app-was-suspended interruption")
                    return
                case .builtInMicMuted:
                    audioLog.debug("Built-in mic was muted")
                case .default:
                    audioLog.debug("Default interruption reason")
                case .routeDisconnected:
                    audioLog.debug("Route was disconnected")
                @unknown default:
                    audioLog.debug("Unknown interruption reason")
                }
            }
            
            // FIX: Extract the ROOT state to prevent nested interrupted states
            // If we're already interrupted, we want to preserve the ORIGINAL state,
            // not create a recursive chain like interrupted(was: interrupted(was: interrupted(...)))
            let rootState = extractRootState(from: state)
            
            // Only update stateBeforeInterruption if we're not already interrupted
            // This preserves the original state through multiple interruptions
            if stateBeforeInterruption == nil {
                stateBeforeInterruption = rootState
            }
            
            isSessionActive = false
            
            // Stop current operations gracefully
            switch rootState {
            case .playingTTS, .playingTTSThenListen:
                synthesizer.pauseSpeaking(at: .word)
                
            case .listening:
                // Pause recording but keep request alive
                recordingEngine?.pause()
                
            default:
                break
            }
            
            // Always use the root state for the interrupted wrapper
            state = .interrupted(previousState: rootState)
            eventContinuation?.yield(.interruptionBegan)
            
        case .ended:
            audioLog.info("✅ INTERRUPTION ENDED")
            
            let shouldResume: Bool
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            } else {
                shouldResume = false
            }
            
            audioLog.info("Should resume: \(shouldResume)")
            
            eventContinuation?.yield(.interruptionEnded(shouldResume: shouldResume))
            
            if shouldResume {
                recoverFromInterruption()
            } else {
                // Cannot resume - clean up
                cleanupAfterInterruption()
            }
            
        @unknown default:
            audioLog.warning("⚠️ Unknown interruption type")
        }
    }
    
    /// Handles audio route changes
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        audioLog.info("🔀 Route change: \(String(describing: reason))")
        
        switch reason {
        case .oldDeviceUnavailable:
            // Device disconnected (e.g., headphones unplugged)
            if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
               let output = previousRoute.outputs.first {
                audioLog.warning("⚠️ Device disconnected: \(output.portName)")
                eventContinuation?.yield(.routeChanged(.deviceDisconnected(output.portName)))
                
                // Pause playback if we were playing through headphones
                if state == .playingTTS {
                    synthesizer.pauseSpeaking(at: .word)
                }
            }
            
        case .newDeviceAvailable:
            let output = audioSession.currentRoute.outputs.first?.portName ?? "Unknown"
            audioLog.info("🎧 Device connected: \(output)")
            eventContinuation?.yield(.routeChanged(.deviceConnected(output)))
            
        case .categoryChange:
            audioLog.info("📂 Category changed")
            eventContinuation?.yield(.routeChanged(.categoryChanged))
            
        case .override, .routeConfigurationChange:
            audioLog.debug("Route configuration changed")
            eventContinuation?.yield(.routeChanged(.configurationChanged))
            
        default:
            break
        }
    }
    
    /// Handles audio engine configuration changes
    private func handleConfigurationChange(_ notification: Notification) {
        audioLog.warning("⚠️ AUDIO ENGINE CONFIGURATION CHANGED")
        
        // This is critical - the engine may have been stopped by iOS
        // We need to reconfigure and restart
        
        switch state {
        case .listening:
            audioLog.info("🔄 Reconfiguring recording engine")
            
            // The recording engine may need to be restarted
            if let engine = recordingEngine, !engine.isRunning {
                do {
                    try engine.start()
                    audioLog.info("✅ Recording engine restarted")
                } catch {
                    audioLog.error("❌ Failed to restart recording engine: \(error)")
                    // Fall through to cleanup
                    _ = stopListening()
                    state = .error(.engineStartFailed(error.localizedDescription))
                }
            }
            
        case .playingTTS, .playingTTSThenListen:
            // TTS should handle its own configuration changes via AVSpeechSynthesizerDelegate
            audioLog.debug("TTS active, letting synthesizer handle configuration change")
            
        default:
            break
        }
        
        eventContinuation?.yield(.routeChanged(.configurationChanged))
    }
    
    /// Handles media services reset
    private func handleMediaServicesReset(_ notification: Notification) {
        audioLog.error("🔴 MEDIA SERVICES WERE RESET - Rebuilding audio system")
        
        // This is rare but critical - ALL audio objects are orphaned
        // We must recreate everything
        
        state = .mediaReset
        
        // Clean up orphaned objects
        recordingEngine = nil
        playbackEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        currentUtterance = nil
        ttsCompletion = nil
        binauralGenerator = nil
        
        // Reset session state
        isSessionActive = false
        stateBeforeInterruption = nil
        
        // Notify UI
        eventContinuation?.yield(.errorOccurred(.mediaServerReset))
        
        // Return to idle
        state = .idle
        
        audioLog.info("✅ Audio system rebuilt after media reset")
    }
    
    /// Handles media services lost
    private func handleMediaServicesLost(_ notification: Notification) {
        audioLog.error("🔴 MEDIA SERVICES LOST")
        
        // Media server is unavailable - wait for reset notification
        state = .mediaReset
    }
    
    // MARK: - Recovery
    
    /// Attempts to recover from an interruption
    private func recoverFromInterruption() {
        audioLog.info("🔄 Attempting recovery from interruption")
        
        state = .recovering
        
        guard let previousState = stateBeforeInterruption else {
            audioLog.warning("No previous state to recover")
            state = .idle
            return
        }
        
        do {
            // Reactivate session
            try activateSession()
            
            switch previousState {
            case .playingTTS, .playingTTSThenListen:
                // Resume TTS
                synthesizer.continueSpeaking()
                state = previousState
                audioLog.info("✅ TTS resumed")
                
            case .listening:
                // Restart recording engine
                if let engine = recordingEngine {
                    try engine.start()
                    state = .listening
                    audioLog.info("✅ Recording resumed")
                } else {
                    // Engine was lost, go to idle
                    state = .idle
                }
                
            default:
                state = .idle
            }
            
        } catch {
            audioLog.error("❌ Recovery failed: \(error)")
            cleanupAfterInterruption()
        }
        
        stateBeforeInterruption = nil
    }
    
    /// Cleans up after an unrecoverable interruption
    private func cleanupAfterInterruption() {
        audioLog.info("🧹 Cleaning up after interruption")
        
        // Stop TTS
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        ttsCompletion?.resume(throwing: AudioCoordinatorError.interruptionNotRecoverable)
        ttsCompletion = nil
        currentUtterance = nil
        
        // Stop recording
        if let engine = recordingEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        recordingEngine = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        transcriptionContinuation?.finish()
        
        state = .idle
        stateBeforeInterruption = nil
    }
    
    // MARK: - Debug Info
    
    /// Returns debug information about current state
    var debugInfo: String {
        """
        AudioCoordinator Debug Info:
        - State: \(state)
        - Session Active: \(isSessionActive)
        - TTS Speaking: \(synthesizer.isSpeaking)
        - Recording Engine Running: \(recordingEngine?.isRunning ?? false)
        - Speech Recognizer Available: \(speechRecognizer?.isAvailable ?? false)
        - Has Mic Permission: \(hasMicrophonePermission)
        - Has Speech Permission: \(hasSpeechRecognitionPermission)
        - Current Route: \(currentRoute)
        - Headphones Connected: \(headphonesConnected)
        - Binaural Preset: \(currentBinauralPreset.rawValue)
        """
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioCoordinator: AVSpeechSynthesizerDelegate {
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            audioLog.info("🗣️ TTS started")
            eventContinuation?.yield(.ttsStarted)
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            audioLog.info("🗣️ TTS finished")
            eventContinuation?.yield(.ttsFinished)
            
            ttsCompletion?.resume(returning: ())
            ttsCompletion = nil
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            audioLog.info("🗣️ TTS cancelled")
            
            ttsCompletion?.resume(returning: ())
            ttsCompletion = nil
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            wordsSpoken += 1
            let progress = Float(wordsSpoken) / Float(max(totalWordCount, 1))
            let word = (utterance.speechString as NSString).substring(with: characterRange)
            
            audioLog.debug("🗣️ Speaking word: \(word) (\(Int(progress * 100))%)")
            eventContinuation?.yield(.ttsProgress(word: word, progress: progress))
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            audioLog.info("🗣️ TTS paused")
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            audioLog.info("🗣️ TTS continued")
        }
    }
}
