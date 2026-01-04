//
//  SpeechAnalysisServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
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
///
/// ## Usage
/// ```swift
/// let speech: SpeechAnalysisServiceProtocol = SpeechAnalysisService()
///
/// // Request permissions
/// await speech.requestMicrophonePermission()
/// await speech.requestSpeechRecognitionPermission()
///
/// // Start analysis
/// try await speech.startAnalysis(
///     forAffirmation: "I am confident and capable",
///     calibrationData: userCalibration
/// )
///
/// // Monitor real-time scores
/// for await score in speech.realtimeScoreStream {
///     updateUI(score: score)
/// }
///
/// // Stop and get final result
/// let record = await speech.stopAnalysis()
/// ```
///
/// ## Related Types
/// - `CalibrationData` - Defined in Domain/Models/UserProfile.swift
/// - `ResonanceRecord` - Defined in Domain/Models/ResonanceRecord.swift
protocol SpeechAnalysisServiceProtocol: AnyObject, Sendable {
    
    // MARK: - State
    
    /// Whether speech analysis is currently active
    var isAnalyzing: Bool { get }
    
    /// Whether microphone permission has been granted
    var hasMicrophonePermission: Bool { get async }
    
    /// Whether speech recognition permission has been granted
    var hasSpeechRecognitionPermission: Bool { get async }
    
    // MARK: - Permissions
    
    /// Requests microphone permission from the user
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestMicrophonePermission() async -> Bool
    
    /// Requests speech recognition permission from the user
    /// - Returns: Whether permission was granted
    @discardableResult
    func requestSpeechRecognitionPermission() async -> Bool
    
    // MARK: - Analysis Control
    
    /// Starts analyzing speech for the given affirmation
    /// - Parameters:
    ///   - affirmationText: The expected text to match against
    ///   - calibrationData: User's calibration data for personalized scoring
    /// - Throws: `AppError.microphoneAccessDenied` or `AppError.speechRecognitionDenied`
    func startAnalysis(
        forAffirmation affirmationText: String,
        calibrationData: CalibrationData?
    ) async throws
    
    /// Stops the current analysis and returns the final score
    /// - Returns: The computed resonance record, or nil if no analysis was active
    func stopAnalysis() async -> ResonanceRecord?
    
    /// Cancels the current analysis without computing a score
    func cancelAnalysis() async
    
    // MARK: - Real-time Updates
    
    /// Stream of real-time resonance scores during analysis (0.0 - 1.0)
    var realtimeScoreStream: AsyncStream<Float> { get }
    
    /// Stream of recognized text during analysis
    var recognizedTextStream: AsyncStream<String> { get }
    
    /// Stream of silence detection events
    /// Emits `true` when silence exceeds threshold, `false` when speech resumes
    var silenceDetectedStream: AsyncStream<Bool> { get }
    
    // MARK: - Calibration
    
    /// Performs voice calibration with the given sample affirmations
    /// - Parameter sampleAffirmations: Texts the user will read for calibration
    /// - Returns: Calibration data based on the user's vocal characteristics
    /// - Throws: `AppError.calibrationFailed` if calibration cannot complete
    func performCalibration(
        with sampleAffirmations: [String]
    ) async throws -> CalibrationData
}

// MARK: - Speech Analysis Delegate

/// Delegate for receiving speech analysis events.
///
/// Implement this protocol to receive callbacks about analysis progress,
/// recognition results, and completion.
protocol SpeechAnalysisDelegate: AnyObject {
    /// Called when real-time resonance score updates
    /// - Parameter score: Current score (0.0 - 1.0)
    func speechAnalysisDidUpdateScore(_ score: Float)
    
    /// Called when text is recognized
    /// - Parameter text: The recognized text so far
    func speechAnalysisDidRecognizeText(_ text: String)
    
    /// Called when silence is detected (user stopped speaking)
    func speechAnalysisDidDetectSilence()
    
    /// Called when analysis completes successfully
    /// - Parameter record: The final resonance record
    func speechAnalysisDidComplete(with record: ResonanceRecord)
    
    /// Called when an error occurs during analysis
    /// - Parameter error: The error that occurred
    func speechAnalysisDidFail(with error: AppError)
}

// NOTE: CalibrationData is defined in Domain/Models/UserProfile.swift
// NOTE: ResonanceRecord is defined in Domain/Models/ResonanceRecord.swift
