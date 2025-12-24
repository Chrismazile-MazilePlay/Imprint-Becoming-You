//
//  SpeechAnalysisService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import Speech
import AVFoundation

// MARK: - SpeechAnalysisService

/// Main service coordinating speech recognition and resonance scoring.
///
/// Integrates:
/// - `AudioInputManager` for microphone capture
/// - `SpeechRecognitionService` for transcription
/// - `ResonanceScoreCalculator` for scoring
/// - `VoiceCalibrationService` for calibration
final class SpeechAnalysisService: SpeechAnalysisServiceProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Audio input manager for microphone capture
    private let audioInputManager: AudioInputManager
    
    /// Speech recognition service
    private let speechRecognitionService: SpeechRecognitionService
    
    /// Voice calibration service
    private let calibrationService: VoiceCalibrationService
    
    /// Audio session manager
    private let sessionManager: AudioSessionManager
    
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
    
    /// Serial queue for thread-safe state access
    private let stateQueue = DispatchQueue(label: "com.imprint.speechanalysis.state")
    
    /// Whether analysis is currently active (thread-safe)
    private var _isAnalyzing: Bool = false
    var isAnalyzing: Bool {
        stateQueue.sync { _isAnalyzing }
    }
    
    // MARK: - Stream Continuations
    
    private var scoreContinuation: AsyncStream<Float>.Continuation?
    private var textContinuation: AsyncStream<String>.Continuation?
    private var silenceContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Streams
    
    /// Stream of real-time resonance scores
    lazy var realtimeScoreStream: AsyncStream<Float> = {
        AsyncStream { [weak self] continuation in
            self?.stateQueue.sync {
                self?.scoreContinuation = continuation
            }
        }
    }()
    
    /// Stream of recognized text
    lazy var recognizedTextStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.stateQueue.sync {
                self?.textContinuation = continuation
            }
        }
    }()
    
    /// Stream of silence detection events
    lazy var silenceDetectedStream: AsyncStream<Bool> = {
        AsyncStream { [weak self] continuation in
            self?.stateQueue.sync {
                self?.silenceContinuation = continuation
            }
        }
    }()
    
    // MARK: - Initialization
    
    /// Creates a new speech analysis service
    init() {
        self.sessionManager = AudioSessionManager.shared
        self.audioInputManager = AudioInputManager(sessionManager: sessionManager)
        self.speechRecognitionService = SpeechRecognitionService()
        self.calibrationService = VoiceCalibrationService(audioInputManager: audioInputManager)
    }
    
    /// Creates a speech analysis service with injected dependencies (for testing)
    init(
        audioInputManager: AudioInputManager,
        speechRecognitionService: SpeechRecognitionService,
        calibrationService: VoiceCalibrationService,
        sessionManager: AudioSessionManager
    ) {
        self.audioInputManager = audioInputManager
        self.speechRecognitionService = speechRecognitionService
        self.calibrationService = calibrationService
        self.sessionManager = sessionManager
    }
    
    // MARK: - Permissions
    
    /// Whether microphone permission has been granted
    var hasMicrophonePermission: Bool {
        get async {
            await sessionManager.hasMicrophonePermission
        }
    }
    
    /// Whether speech recognition permission has been granted
    var hasSpeechRecognitionPermission: Bool {
        get async {
            await speechRecognitionService.isAuthorized
        }
    }
    
    /// Requests microphone permission
    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        await sessionManager.requestMicrophonePermission()
    }
    
    /// Requests speech recognition permission
    @discardableResult
    func requestSpeechRecognitionPermission() async -> Bool {
        await speechRecognitionService.requestAuthorization()
    }
    
    // MARK: - Analysis Control
    
    /// Starts analyzing speech for the given affirmation
    func startAnalysis(
        forAffirmation affirmationText: String,
        calibrationData: CalibrationData?
    ) async throws {
        // Check if already analyzing (thread-safe read)
        let alreadyAnalyzing = stateQueue.sync { _isAnalyzing }
        guard !alreadyAnalyzing else { return }
        
        // Check permissions
        let hasMic = await hasMicrophonePermission
        guard hasMic else {
            throw AppError.microphoneAccessDenied
        }
        
        let hasSpeech = await hasSpeechRecognitionPermission
        guard hasSpeech else {
            throw AppError.speechRecognitionDenied
        }
        
        // Setup state (thread-safe write)
        stateQueue.sync {
            currentAffirmation = affirmationText
            scoreCalculator = ResonanceScoreCalculator(calibrationData: calibrationData)
            scoreCalculator?.startSession()
            silenceStartTime = nil
            _isAnalyzing = true
        }
        
        // Start components
        try await audioInputManager.startCapture()
        try await speechRecognitionService.startRecognition()
        
        // Start analysis task
        analysisTask = Task { [weak self] in
            await self?.runAnalysisLoop()
        }
    }
    
    /// Stops analysis and returns final score
    func stopAnalysis() async -> ResonanceRecord? {
        let wasAnalyzing = stateQueue.sync { _isAnalyzing }
        guard wasAnalyzing else { return nil }
        
        // Stop analysis task
        analysisTask?.cancel()
        analysisTask = nil
        
        // Get final transcription
        let finalText = await speechRecognitionService.stopRecognition()
        
        // Stop audio capture
        await audioInputManager.stopCapture()
        
        // Calculate text accuracy and compute final score
        var result: ResonanceRecord?
        stateQueue.sync {
            if let text = finalText, !text.isEmpty {
                let accuracy = TextAccuracyCalculator.calculate(
                    expected: currentAffirmation,
                    recognized: text
                )
                scoreCalculator?.setTextAccuracy(accuracy)
            }
            
            // Compute final score
            result = scoreCalculator?.computeFinalScore(sessionMode: currentSessionMode)
            
            // Clean up
            _isAnalyzing = false
            scoreCalculator = nil
            
            // Finish streams
            scoreContinuation?.finish()
            textContinuation?.finish()
            silenceContinuation?.finish()
        }
        
        return result
    }
    
    /// Cancels analysis without computing a score
    func cancelAnalysis() async {
        let wasAnalyzing = stateQueue.sync { _isAnalyzing }
        guard wasAnalyzing else { return }
        
        // Stop analysis task
        analysisTask?.cancel()
        analysisTask = nil
        
        // Stop components
        await speechRecognitionService.cancelRecognition()
        await audioInputManager.stopCapture()
        
        // Clean up state
        stateQueue.sync {
            _isAnalyzing = false
            scoreCalculator = nil
            
            scoreContinuation?.finish()
            textContinuation?.finish()
            silenceContinuation?.finish()
        }
    }
    
    // MARK: - Calibration
    
    /// Performs voice calibration
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        // Check permissions first
        let hasMic = await hasMicrophonePermission
        guard hasMic else {
            throw AppError.microphoneAccessDenied
        }
        
        return try await calibrationService.performCalibration(with: sampleAffirmations)
    }
    
    // MARK: - Private Methods
    
    /// Main analysis loop
    private func runAnalysisLoop() async {
        // Process audio buffers
        let bufferTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await buffer in await self.audioInputManager.audioBufferStream {
                guard !Task.isCancelled else { break }
                await self.processAudioBuffer(buffer)
            }
        }
        
        // Process transcription results
        let transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await result in await self.speechRecognitionService.transcriptionStream {
                guard !Task.isCancelled else { break }
                await self.processTranscription(result)
            }
        }
        
        // Wait for both tasks
        await bufferTask.value
        await transcriptionTask.value
    }
    
    /// Processes an audio buffer
    private func processAudioBuffer(_ buffer: AudioAnalysisBuffer) async {
        // Thread-safe state access
        var shouldProcess = false
        var calculator: ResonanceScoreCalculator?
        
        stateQueue.sync {
            shouldProcess = _isAnalyzing
            calculator = scoreCalculator
        }
        
        guard shouldProcess, let calc = calculator else { return }
        
        // Add RMS sample
        calc.addRMSSample(buffer.rmsLevel)
        
        // Detect and add pitch
        let pitch = PitchDetector.detectPitch(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate
        )
        calc.addPitchSample(pitch)
        
        // Append to speech recognition
        await speechRecognitionService.appendAudioSamples(
            buffer.samples,
            sampleRate: buffer.sampleRate
        )
        
        // Check for silence and emit events
        checkAndEmitSilence(containsSpeech: buffer.containsSpeech)
        
        // Compute and emit real-time score
        let realtimeScore = calc.computeRealtimeScore()
        emitScore(realtimeScore)
    }
    
    /// Checks for silence and emits events if needed
    private func checkAndEmitSilence(containsSpeech: Bool) {
        let silenceThreshold = Constants.Session.silenceThreshold
        
        stateQueue.sync {
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
    }
    
    /// Emits a score to the stream
    private func emitScore(_ score: Float) {
        _ = stateQueue.sync {
            scoreContinuation?.yield(score)
        }
    }
    
    /// Emits text to the stream
    private func emitText(_ text: String) {
        _ = stateQueue.sync {
            textContinuation?.yield(text)
        }
    }
    
    /// Processes a transcription result
    private func processTranscription(_ result: TranscriptionResult) async {
        var shouldProcess = false
        var affirmation = ""
        var calculator: ResonanceScoreCalculator?
        
        stateQueue.sync {
            shouldProcess = _isAnalyzing
            affirmation = currentAffirmation
            calculator = scoreCalculator
        }
        
        guard shouldProcess else { return }
        
        // Emit recognized text
        emitText(result.text)
        
        // Update text accuracy in real-time (partial)
        if !result.text.isEmpty, let calc = calculator {
            let accuracy = TextAccuracyCalculator.calculate(
                expected: affirmation,
                recognized: result.text
            )
            calc.setTextAccuracy(accuracy)
        }
    }
}
