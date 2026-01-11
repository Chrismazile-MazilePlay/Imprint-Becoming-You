//
//  SpeechAnalysisService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import Speech
import AVFoundation
import os.log

// MARK: - Logger

private let speechLog = Logger(subsystem: "com.imprint.audio", category: "SpeechAnalysisService")

// MARK: - SpeechAnalysisService

/// Main service coordinating speech recognition and resonance scoring.
///
/// ## SOLID Compliance
/// - **SRP**: Coordinates speech analysis components
/// - **OCP**: Works with any AudioPermissionProviding implementation
/// - **DIP**: Depends on protocols, not concrete implementations
///
/// Integrates:
/// - `AudioInputManager` for microphone capture
/// - `SpeechRecognitionService` for transcription
/// - `ResonanceScoreCalculator` for scoring (includes TextAccuracyCalculator)
/// - `VoiceCalibrationService` for calibration
@MainActor
final class SpeechAnalysisService: SpeechAnalysisServiceProtocol {
    
    // MARK: - Properties
    
    /// Audio input manager for microphone capture
    private let audioInputManager: AudioInputManager
    
    /// Speech recognition service
    private let speechRecognitionService: SpeechRecognitionService
    
    /// Voice calibration service
    private let calibrationService: VoiceCalibrationService
    
    /// Permission provider (protocol-based dependency)
    private let permissionProvider: any AudioPermissionProviding
    
    /// Current resonance score calculator
    private var scoreCalculator: ResonanceScoreCalculator?
    
    /// Current affirmation being analyzed
    private var currentAffirmation: String = ""
    
    /// Current session mode
    private var currentSessionMode: SessionMode = .readThenSpeak
    
    /// Silence detection start time
    private var silenceStartTime: Date?
    
    /// Analysis task
    private var analysisTask: Task<Void, Never>?
    
    /// Whether analysis is currently active
    private(set) var isAnalyzing: Bool = false
    
    // MARK: - Stream Continuations
    
    private var scoreContinuation: AsyncStream<Float>.Continuation?
    private var textContinuation: AsyncStream<String>.Continuation?
    private var silenceContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Streams
    
    /// Stream of real-time resonance scores
    private(set) lazy var realtimeScoreStream: AsyncStream<Float> = {
        AsyncStream { [weak self] continuation in
            self?.scoreContinuation = continuation
        }
    }()
    
    /// Stream of recognized text
    private(set) lazy var recognizedTextStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.textContinuation = continuation
        }
    }()
    
    /// Stream of silence detection events
    private(set) lazy var silenceDetectedStream: AsyncStream<Bool> = {
        AsyncStream { [weak self] continuation in
            self?.silenceContinuation = continuation
        }
    }()
    
    // MARK: - Initialization
    
    /// Creates a new speech analysis service
    /// - Parameter permissionProvider: Provider for audio permissions (defaults to AudioCoordinator.shared)
    init(permissionProvider: (any AudioPermissionProviding)? = nil) {
        let provider = permissionProvider ?? AudioCoordinator.shared
        self.permissionProvider = provider
        
        // Create AudioInputManager with the same provider if it conforms to session protocols
        if let fullProvider = provider as? (any AudioSessionProviding & AudioPermissionProviding) {
            self.audioInputManager = AudioInputManager(sessionProvider: fullProvider)
        } else {
            self.audioInputManager = AudioInputManager()
        }
        
        self.speechRecognitionService = SpeechRecognitionService()
        self.calibrationService = VoiceCalibrationService(audioInputManager: audioInputManager)
        
        speechLog.info("✅ SpeechAnalysisService initialized")
    }
    
    /// Creates a speech analysis service with injected dependencies (for testing)
    init(
        audioInputManager: AudioInputManager,
        speechRecognitionService: SpeechRecognitionService,
        calibrationService: VoiceCalibrationService,
        permissionProvider: any AudioPermissionProviding
    ) {
        self.audioInputManager = audioInputManager
        self.speechRecognitionService = speechRecognitionService
        self.calibrationService = calibrationService
        self.permissionProvider = permissionProvider
    }
    
    // MARK: - Permissions
    
    /// Whether microphone permission has been granted
    var hasMicrophonePermission: Bool {
        permissionProvider.hasMicrophonePermission
    }
    
    /// Whether speech recognition permission has been granted
    var hasSpeechRecognitionPermission: Bool {
        permissionProvider.hasSpeechRecognitionPermission
    }
    
    /// Requests microphone permission
    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        speechLog.info("🎤 Requesting microphone permission")
        return await permissionProvider.requestMicrophonePermission()
    }
    
    /// Requests speech recognition permission
    @discardableResult
    func requestSpeechRecognitionPermission() async -> Bool {
        speechLog.info("🗣️ Requesting speech recognition permission")
        return await permissionProvider.requestSpeechRecognitionPermission()
    }
    
    // MARK: - Analysis Control
    
    /// Starts analyzing speech for the given affirmation
    func startAnalysis(
        forAffirmation affirmationText: String,
        calibrationData: CalibrationData?
    ) async throws {
        guard !isAnalyzing else {
            speechLog.warning("⚠️ Already analyzing, ignoring startAnalysis")
            return
        }
        
        speechLog.info("🎬 Starting analysis for: \"\(affirmationText.prefix(30))...\"")
        
        // Check permissions
        guard hasMicrophonePermission else {
            speechLog.error("❌ Microphone permission denied")
            throw AppError.microphoneAccessDenied
        }
        
        guard hasSpeechRecognitionPermission else {
            speechLog.error("❌ Speech recognition permission denied")
            throw AppError.speechRecognitionDenied
        }
        
        // Setup state
        currentAffirmation = affirmationText
        scoreCalculator = ResonanceScoreCalculator(calibrationData: calibrationData)
        scoreCalculator?.startSession()
        silenceStartTime = nil
        isAnalyzing = true
        
        // Start components
        try await audioInputManager.startCapture()
        try await speechRecognitionService.startRecognition()
        
        speechLog.info("✅ Analysis started")
        
        // Start analysis task
        analysisTask = Task { [weak self] in
            await self?.runAnalysisLoop()
        }
    }
    
    /// Stops analysis and returns final score
    func stopAnalysis() async -> ResonanceRecord? {
        guard isAnalyzing else {
            speechLog.warning("⚠️ Not analyzing, ignoring stopAnalysis")
            return nil
        }
        
        speechLog.info("🛑 Stopping analysis")
        
        // Stop analysis task
        analysisTask?.cancel()
        analysisTask = nil
        
        // Get final transcription
        let finalText = await speechRecognitionService.stopRecognition()
        
        // Stop audio capture
        audioInputManager.stopCapture()
        
        // Calculate text accuracy and compute final score
        var result: ResonanceRecord?
        
        if let text = finalText, !text.isEmpty {
            speechLog.info("📜 Final transcription: \"\(text.prefix(100))...\"")
            
            // Uses TextAccuracyCalculator from ResonanceScoreCalculator.swift
            let accuracy = TextAccuracyCalculator.calculate(
                expected: currentAffirmation,
                recognized: text
            )
            scoreCalculator?.setTextAccuracy(accuracy)
        }
        
        // Compute final score
        result = scoreCalculator?.computeFinalScore(sessionMode: currentSessionMode)
        
        if let r = result {
            speechLog.info("📊 Final score: \(Int(r.overallScore * 100))%")
        }
        
        // Clean up
        isAnalyzing = false
        scoreCalculator = nil
        
        // Finish streams
        scoreContinuation?.finish()
        textContinuation?.finish()
        silenceContinuation?.finish()
        
        return result
    }
    
    /// Cancels analysis without computing a score
    func cancelAnalysis() async {
        guard isAnalyzing else { return }
        
        speechLog.info("❌ Cancelling analysis")
        
        // Stop analysis task
        analysisTask?.cancel()
        analysisTask = nil
        
        // Stop components
        await speechRecognitionService.cancelRecognition()
        audioInputManager.stopCapture()
        
        // Clean up state
        isAnalyzing = false
        scoreCalculator = nil
        
        scoreContinuation?.finish()
        textContinuation?.finish()
        silenceContinuation?.finish()
    }
    
    // MARK: - Calibration
    
    /// Performs voice calibration
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        speechLog.info("🎤 Starting voice calibration")
        
        // Check permissions first
        guard hasMicrophonePermission else {
            throw AppError.microphoneAccessDenied
        }
        
        return try await calibrationService.performCalibration(with: sampleAffirmations)
    }
    
    // MARK: - Private Methods
    
    /// Main analysis loop
    private func runAnalysisLoop() async {
        speechLog.debug("🔄 Analysis loop started")
        
        // Process audio buffers
        let bufferTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await buffer in self.audioInputManager.audioBufferStream {
                guard !Task.isCancelled else { break }
                self.processAudioBuffer(buffer)
            }
        }
        
        // Process transcription results
        let transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await result in await self.speechRecognitionService.transcriptionStream {
                guard !Task.isCancelled else { break }
                self.processTranscription(result)
            }
        }
        
        // Wait for both tasks
        await bufferTask.value
        await transcriptionTask.value
        
        speechLog.debug("🔄 Analysis loop ended")
    }
    
    /// Processes an audio buffer
    private func processAudioBuffer(_ buffer: AudioAnalysisBuffer) {
        guard isAnalyzing, let calc = scoreCalculator else { return }
        
        // Add RMS sample
        calc.addRMSSample(buffer.rmsLevel)
        
        // Detect and add pitch
        let pitch = PitchDetector.detectPitch(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate
        )
        calc.addPitchSample(pitch)
        
        // Append to speech recognition
        Task {
            await speechRecognitionService.appendAudioSamples(
                buffer.samples,
                sampleRate: buffer.sampleRate
            )
        }
        
        // Check for silence and emit events
        checkAndEmitSilence(containsSpeech: buffer.containsSpeech)
        
        // Compute and emit real-time score
        let realtimeScore = calc.computeRealtimeScore()
        emitScore(realtimeScore)
    }
    
    /// Checks for silence and emits events if needed
    private func checkAndEmitSilence(containsSpeech: Bool) {
        let silenceThreshold = Constants.Session.silenceThreshold
        
        if !containsSpeech {
            // No speech detected
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if let startTime = silenceStartTime {
                let silenceDuration = Date().timeIntervalSince(startTime)
                if silenceDuration >= silenceThreshold {
                    silenceContinuation?.yield(true)
                    silenceStartTime = nil
                }
            }
        } else {
            // Speech detected - reset silence timer
            if silenceStartTime != nil {
                silenceContinuation?.yield(false)
                silenceStartTime = nil
            }
        }
    }
    
    /// Emits a score to the stream
    private func emitScore(_ score: Float) {
        scoreContinuation?.yield(score)
    }
    
    /// Emits text to the stream
    private func emitText(_ text: String) {
        textContinuation?.yield(text)
    }
    
    /// Processes a transcription result
    private func processTranscription(_ result: TranscriptionResult) {
        guard isAnalyzing else { return }
        
        // Emit recognized text
        emitText(result.text)
        
        speechLog.debug("📝 Transcription (\(result.isFinal ? "final" : "partial")): \"\(result.text.prefix(50))...\"")
        
        // Update text accuracy in real-time (partial)
        // Uses TextAccuracyCalculator from ResonanceScoreCalculator.swift
        if !result.text.isEmpty, let calc = scoreCalculator {
            let accuracy = TextAccuracyCalculator.calculate(
                expected: currentAffirmation,
                recognized: result.text
            )
            calc.setTextAccuracy(accuracy)
        }
    }
}

// NOTE: TextAccuracyCalculator is defined in ResonanceScoreCalculator.swift
// This service uses that canonical definition.
