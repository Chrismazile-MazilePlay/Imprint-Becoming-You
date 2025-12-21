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
///
/// ## Architecture
/// ```
/// SpeechAnalysisService (Coordinator)
/// ├── AudioInputManager (microphone)
/// ├── SpeechRecognitionService (transcription)
/// ├── ResonanceScoreCalculator (scoring)
/// └── VoiceCalibrationService (calibration)
/// ```
///
/// ## Usage
/// ```swift
/// let service = SpeechAnalysisService()
/// try await service.startAnalysis(forAffirmation: "I am confident")
/// for await score in service.realtimeScoreStream {
///     updateUI(score)
/// }
/// let result = await service.stopAnalysis()
/// ```
final class SpeechAnalysisService: SpeechAnalysisServiceProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Audio input manager for microphone capture
    private let audioInputManager: AudioInputManager
    
    /// Speech recognition service
    private let speechRecognitionService: SpeechRecognitionService
    
    /// Voice calibration service
    private let calibrationService: VoiceCalibrationService
    
    /// Current resonance score calculator
    private var scoreCalculator: ResonanceScoreCalculator?
    
    /// Audio session manager
    private let sessionManager: AudioSessionManager
    
    /// Whether analysis is currently active
    private(set) var isAnalyzing: Bool = false
    
    /// Current affirmation being analyzed
    private var currentAffirmation: String = ""
    
    /// Current session mode
    private var currentSessionMode: SessionMode = .readThenSpeak
    
    /// Analysis task
    private var analysisTask: Task<Void, Never>?
    
    /// Silence detection timer
    private var silenceStartTime: Date?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Stream Continuations
    
    private var scoreContinuation: AsyncStream<Float>.Continuation?
    private var textContinuation: AsyncStream<String>.Continuation?
    private var silenceContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Streams
    
    /// Stream of real-time resonance scores
    lazy var realtimeScoreStream: AsyncStream<Float> = {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.scoreContinuation = continuation
            self?.lock.unlock()
        }
    }()
    
    /// Stream of recognized text
    lazy var recognizedTextStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.textContinuation = continuation
            self?.lock.unlock()
        }
    }()
    
    /// Stream of silence detection events
    lazy var silenceDetectedStream: AsyncStream<Bool> = {
        AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.silenceContinuation = continuation
            self?.lock.unlock()
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
        guard !isAnalyzing else { return }
        
        // Check permissions
        guard await hasMicrophonePermission else {
            throw AppError.microphoneAccessDenied
        }
        
        guard await hasSpeechRecognitionPermission else {
            throw AppError.speechRecognitionDenied
        }
        
        // Setup
        lock.lock()
        currentAffirmation = affirmationText
        scoreCalculator = ResonanceScoreCalculator(calibrationData: calibrationData)
        scoreCalculator?.startSession()
        silenceStartTime = nil
        isAnalyzing = true
        lock.unlock()
        
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
        guard isAnalyzing else { return nil }
        
        // Stop analysis task
        analysisTask?.cancel()
        analysisTask = nil
        
        // Get final transcription
        let finalText = await speechRecognitionService.stopRecognition()
        
        // Stop audio capture
        await audioInputManager.stopCapture()
        
        // Calculate text accuracy
        lock.lock()
        if let text = finalText, !text.isEmpty {
            let accuracy = TextAccuracyCalculator.calculate(
                expected: currentAffirmation,
                recognized: text
            )
            scoreCalculator?.setTextAccuracy(accuracy)
        }
        
        // Compute final score
        let result = scoreCalculator?.computeFinalScore(sessionMode: currentSessionMode)
        
        // Clean up
        isAnalyzing = false
        scoreCalculator = nil
        
        // Finish streams
        scoreContinuation?.finish()
        textContinuation?.finish()
        silenceContinuation?.finish()
        lock.unlock()
        
        return result
    }
    
    /// Cancels analysis without computing a score
    func cancelAnalysis() async {
        guard isAnalyzing else { return }
        
        // Stop analysis task
        analysisTask?.cancel()
        analysisTask = nil
        
        // Stop components
        await speechRecognitionService.cancelRecognition()
        await audioInputManager.stopCapture()
        
        // Clean up
        lock.lock()
        isAnalyzing = false
        scoreCalculator = nil
        
        scoreContinuation?.finish()
        textContinuation?.finish()
        silenceContinuation?.finish()
        lock.unlock()
    }
    
    // MARK: - Calibration
    
    /// Performs voice calibration
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        // Check permissions first
        guard await hasMicrophonePermission else {
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
        lock.lock()
        defer { lock.unlock() }
        
        guard let calculator = scoreCalculator else { return }
        
        // Add RMS sample
        calculator.addRMSSample(buffer.rmsLevel)
        
        // Detect and add pitch
        let pitch = PitchDetector.detectPitch(
            samples: buffer.samples,
            sampleRate: buffer.sampleRate
        )
        calculator.addPitchSample(pitch)
        
        // Append to speech recognition
        await speechRecognitionService.appendAudioSamples(
            buffer.samples,
            sampleRate: buffer.sampleRate
        )
        
        // Check for silence
        checkSilence(buffer: buffer)
        
        // Compute and emit real-time score
        let realtimeScore = calculator.computeRealtimeScore()
        scoreContinuation?.yield(realtimeScore)
    }
    
    /// Processes a transcription result
    private func processTranscription(_ result: TranscriptionResult) async {
        lock.lock()
        defer { lock.unlock() }
        
        // Emit recognized text
        textContinuation?.yield(result.text)
        
        // Update text accuracy in real-time (partial)
        if !result.text.isEmpty {
            let accuracy = TextAccuracyCalculator.calculate(
                expected: currentAffirmation,
                recognized: result.text
            )
            scoreCalculator?.setTextAccuracy(accuracy)
        }
    }
    
    /// Checks for silence and emits events
    private func checkSilence(buffer: AudioAnalysisBuffer) {
        let silenceThreshold = Constants.Session.silenceThreshold
        
        if !buffer.containsSpeech {
            // No speech detected
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if let startTime = silenceStartTime {
                let silenceDuration = Date().timeIntervalSince(startTime)
                if silenceDuration >= silenceThreshold {
                    // Emit silence event
                    silenceContinuation?.yield(true)
                    silenceStartTime = nil // Reset to avoid repeated events
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
