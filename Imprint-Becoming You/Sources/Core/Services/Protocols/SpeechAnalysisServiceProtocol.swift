//
//  SpeechAnalysisServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation

// MARK: - Speech Analysis Service Protocol

/// Protocol defining speech recognition and resonance scoring capabilities.
///
/// Implementations must handle:
/// - Microphone input processing
/// - Speech-to-text recognition
/// - RMS energy calculation
/// - Pitch analysis
/// - Resonance score computation
protocol SpeechAnalysisServiceProtocol: AnyObject, Sendable {
    
    // MARK: - State
    
    /// Whether speech analysis is currently active
    var isAnalyzing: Bool { get }
    
    /// Whether microphone permission has been granted
    var hasMicrophonePermission: Bool { get async }
    
    /// Whether speech recognition permission has been granted
    var hasSpeechRecognitionPermission: Bool { get async }
    
    // MARK: - Permissions
    
    /// Requests microphone permission
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestMicrophonePermission() async -> Bool
    
    /// Requests speech recognition permission
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestSpeechRecognitionPermission() async -> Bool
    
    // MARK: - Analysis Control
    
    /// Starts analyzing speech for the given affirmation
    /// - Parameters:
    ///   - affirmationText: The expected text to match against
    ///   - calibrationData: User's calibration data for personalized scoring
    /// - Throws: `AppError.speechRecognitionFailed` if analysis cannot start
    func startAnalysis(
        forAffirmation affirmationText: String,
        calibrationData: CalibrationData?
    ) async throws
    
    /// Stops the current analysis and returns the final score
    /// - Returns: The computed resonance record
    func stopAnalysis() async -> ResonanceRecord?
    
    /// Cancels the current analysis without computing a score
    func cancelAnalysis() async
    
    // MARK: - Real-time Updates
    
    /// Stream of real-time resonance scores during analysis
    var realtimeScoreStream: AsyncStream<Float> { get }
    
    /// Stream of recognized text during analysis
    var recognizedTextStream: AsyncStream<String> { get }
    
    /// Stream of silence detection events
    var silenceDetectedStream: AsyncStream<Bool> { get }
    
    // MARK: - Calibration
    
    /// Performs voice calibration with the given sample affirmations
    /// - Parameter sampleAffirmations: Texts the user will read for calibration
    /// - Returns: Calibration data based on the samples
    /// - Throws: `AppError.calibrationFailed` if calibration fails
    func performCalibration(
        with sampleAffirmations: [String]
    ) async throws -> CalibrationData
}

// MARK: - Speech Analysis Delegate

/// Delegate for receiving speech analysis events
protocol SpeechAnalysisDelegate: AnyObject {
    /// Called when real-time resonance score updates
    func speechAnalysisDidUpdateScore(_ score: Float)
    
    /// Called when text is recognized
    func speechAnalysisDidRecognizeText(_ text: String)
    
    /// Called when silence is detected
    func speechAnalysisDidDetectSilence()
    
    /// Called when analysis completes
    func speechAnalysisDidComplete(with record: ResonanceRecord)
    
    /// Called when an error occurs
    func speechAnalysisDidFail(with error: AppError)
}

// MARK: - Mock Implementation

/// Mock speech analysis service for previews and testing
final class MockSpeechAnalysisService: SpeechAnalysisServiceProtocol, @unchecked Sendable {
    var isAnalyzing: Bool = false
    
    var hasMicrophonePermission: Bool {
        get async { true }
    }
    
    var hasSpeechRecognitionPermission: Bool {
        get async { true }
    }
    
    // Continuation for score stream
    private var scoreContinuation: AsyncStream<Float>.Continuation?
    private var textContinuation: AsyncStream<String>.Continuation?
    private var silenceContinuation: AsyncStream<Bool>.Continuation?
    
    lazy var realtimeScoreStream: AsyncStream<Float> = {
        AsyncStream { continuation in
            self.scoreContinuation = continuation
        }
    }()
    
    lazy var recognizedTextStream: AsyncStream<String> = {
        AsyncStream { continuation in
            self.textContinuation = continuation
        }
    }()
    
    lazy var silenceDetectedStream: AsyncStream<Bool> = {
        AsyncStream { continuation in
            self.silenceContinuation = continuation
        }
    }()
    
    func requestMicrophonePermission() async -> Bool {
        true
    }
    
    func requestSpeechRecognitionPermission() async -> Bool {
        true
    }
    
    func startAnalysis(
        forAffirmation affirmationText: String,
        calibrationData: CalibrationData?
    ) async throws {
        isAnalyzing = true
        
        // Simulate real-time score updates
        Task {
            for _ in 1...5 {
                try await Task.sleep(for: .milliseconds(500))
                let score = Float.random(in: 0.5...0.9)
                scoreContinuation?.yield(score)
            }
        }
    }
    
    func stopAnalysis() async -> ResonanceRecord? {
        isAnalyzing = false
        return ResonanceRecord(
            overallScore: Float.random(in: 0.6...0.95),
            textAccuracy: Float.random(in: 0.7...1.0),
            vocalEnergy: Float.random(in: 0.5...0.95),
            pitchStability: Float.random(in: 0.6...0.9),
            duration: 3.5,
            sessionMode: .readThenSpeak
        )
    }
    
    func cancelAnalysis() async {
        isAnalyzing = false
    }
    
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        // Simulate calibration time
        try await Task.sleep(for: .seconds(2))
        
        return CalibrationData(
            baselineRMS: 0.3,
            pitchMin: 85,
            pitchMax: 255,
            volumeMin: -30,
            volumeMax: -10
        )
    }
}

// MARK: - Production Implementation

// The production SpeechAnalysisService is implemented in:
// Sources/Core/Services/Speech/SpeechAnalysisService.swift
//
// Supporting components:
// - AudioInputManager.swift (microphone capture)
// - SpeechRecognitionService.swift (Apple Speech framework)
// - ResonanceScoreCalculator.swift (scoring calculations)
// - VoiceCalibrationService.swift (baseline measurement)
