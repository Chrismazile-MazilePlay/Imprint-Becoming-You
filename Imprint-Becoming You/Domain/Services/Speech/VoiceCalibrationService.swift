//
//  VoiceCalibrationService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import AVFoundation
import os.log

// MARK: - Logger

private let calibrationLog = Logger(subsystem: "com.imprint.audio", category: "VoiceCalibration")

// MARK: - VoiceCalibrationService

/// Captures baseline voice measurements during onboarding.
///
/// Calibration helps personalize resonance scoring by measuring:
/// - Baseline volume (RMS)
/// - Pitch range (min/max Hz)
/// - Speaking volume range (dB)
///
/// ## Calibration Process
/// 1. User reads 3-5 sample affirmations
/// 2. System captures audio and measures voice characteristics
/// 3. Results are stored in UserProfile.calibrationData
///
/// ## Usage
/// ```swift
/// let service = VoiceCalibrationService()
/// let calibration = try await service.performCalibration(
///     with: ["I am confident", "I am worthy", "I am capable"]
/// )
/// ```
@MainActor
final class VoiceCalibrationService: VoiceCalibrationServiceProtocol {
    
    // MARK: - Properties
    
    /// Audio input manager for microphone capture
    private let audioInputManager: AudioInputManager
    
    /// Collected RMS samples across all calibration utterances
    private var allRMSSamples: [Float] = []
    
    /// Collected pitch samples across all calibration utterances
    private var allPitchSamples: [Float] = []
    
    /// Collected dB levels across all calibration utterances
    private var allDecibelSamples: [Float] = []
    
    /// Whether calibration is in progress
    private(set) var isCalibrating: Bool = false
    
    /// Current calibration progress (0.0 - 1.0)
    private(set) var progress: Float = 0
    
    /// Current phrase being calibrated
    private(set) var currentPhraseIndex: Int = 0
    
    /// Total phrases to calibrate
    private(set) var totalPhrases: Int = 0
    
    /// Continuation for progress updates
    private var progressContinuation: AsyncStream<CalibrationProgress>.Continuation?
    
    /// Stream of calibration progress updates
    private(set) lazy var progressStream: AsyncStream<CalibrationProgress> = {
        AsyncStream { [weak self] continuation in
            self?.progressContinuation = continuation
        }
    }()
    
    // MARK: - Initialization
    
    /// Creates a new calibration service
    /// - Parameter audioInputManager: Audio input manager (defaults to new instance using AudioSessionController)
    init(audioInputManager: AudioInputManager? = nil) {
        self.audioInputManager = audioInputManager ?? AudioInputManager()
        calibrationLog.info("✅ VoiceCalibrationService initialized")
    }
    
    // MARK: - Calibration
    
    /// Performs voice calibration with sample affirmations
    /// - Parameter sampleAffirmations: Texts for user to read during calibration
    /// - Returns: Computed calibration data
    /// - Throws: `AppError.calibrationFailed` if calibration fails
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        guard !isCalibrating else {
            calibrationLog.warning("⚠️ Calibration already in progress")
            throw AppError.calibrationFailed(reason: "Calibration already in progress")
        }
        
        guard !sampleAffirmations.isEmpty else {
            calibrationLog.error("❌ No sample affirmations provided")
            throw AppError.calibrationFailed(reason: "No sample affirmations provided")
        }
        
        calibrationLog.info("🎬 Starting calibration with \(sampleAffirmations.count) phrases")
        
        // Reset state
        allRMSSamples.removeAll()
        allPitchSamples.removeAll()
        allDecibelSamples.removeAll()
        currentPhraseIndex = 0
        totalPhrases = sampleAffirmations.count
        progress = 0
        isCalibrating = true
        
        defer {
            isCalibrating = false
            progressContinuation?.finish()
        }
        
        // Process each affirmation
        for (index, affirmation) in sampleAffirmations.enumerated() {
            currentPhraseIndex = index
            progress = Float(index) / Float(totalPhrases)
            
            calibrationLog.info("📝 Calibrating phrase \(index + 1)/\(self.totalPhrases): \"\(affirmation.prefix(30))...\"")
            
            // Emit progress update
            let progressUpdate = CalibrationProgress(
                currentPhrase: affirmation,
                phraseIndex: index,
                totalPhrases: totalPhrases,
                progress: progress,
                state: .recording
            )
            progressContinuation?.yield(progressUpdate)
            
            // Capture this phrase
            try await capturePhrase(affirmation)
            
            // Small delay between phrases
            if index < sampleAffirmations.count - 1 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        
        // Compute calibration data from collected samples
        progress = 1.0
        let calibrationData = computeCalibrationData()
        
        calibrationLog.info("✅ Calibration complete - RMS: \(calibrationData.baselineRMS), Pitch: \(calibrationData.pitchMin)-\(calibrationData.pitchMax) Hz")
        
        // Emit completion
        let completionUpdate = CalibrationProgress(
            currentPhrase: "",
            phraseIndex: totalPhrases,
            totalPhrases: totalPhrases,
            progress: 1.0,
            state: .complete
        )
        progressContinuation?.yield(completionUpdate)
        
        return calibrationData
    }
    
    /// Captures audio for a single phrase
    /// - Parameter phrase: The phrase being spoken
    private func capturePhrase(_ phrase: String) async throws {
        // Start capturing
        try await audioInputManager.startCapture()
        
        // Collect samples for expected duration
        // Estimate: ~100ms per word + 500ms buffer
        let wordCount = phrase.components(separatedBy: .whitespaces).count
        let estimatedDuration = TimeInterval(wordCount) * 0.4 + 1.0
        let maxDuration: TimeInterval = 10.0 // Safety limit
        let captureDuration = min(estimatedDuration, maxDuration)
        
        let startTime = Date()
        
        // Process audio buffers
        for await buffer in audioInputManager.audioBufferStream {
            // Collect RMS
            allRMSSamples.append(buffer.rmsLevel)
            allDecibelSamples.append(buffer.decibelLevel)
            
            // Detect and collect pitch
            let pitch = PitchDetector.detectPitch(
                samples: buffer.samples,
                sampleRate: buffer.sampleRate
            )
            if pitch > 0 {
                allPitchSamples.append(pitch)
            }
            
            // Check if we've captured enough
            if Date().timeIntervalSince(startTime) >= captureDuration {
                break
            }
        }
        
        // Stop capturing
        audioInputManager.stopCapture()
    }
    
    /// Computes calibration data from collected samples
    private func computeCalibrationData() -> CalibrationData {
        // Calculate baseline RMS (median to reduce outlier impact)
        let sortedRMS = allRMSSamples.sorted()
        let baselineRMS: Float
        if sortedRMS.isEmpty {
            baselineRMS = 0.15 // Default
        } else {
            baselineRMS = sortedRMS[sortedRMS.count / 2]
        }
        
        // Calculate pitch range
        let pitchMin: Float
        let pitchMax: Float
        if allPitchSamples.isEmpty {
            // Default values (typical adult range)
            pitchMin = 100
            pitchMax = 300
        } else {
            // Use 10th and 90th percentiles to reduce outliers
            let sortedPitch = allPitchSamples.sorted()
            let lowIndex = sortedPitch.count / 10
            let highIndex = (sortedPitch.count * 9) / 10
            pitchMin = sortedPitch[max(0, lowIndex)]
            pitchMax = sortedPitch[min(sortedPitch.count - 1, highIndex)]
        }
        
        // Calculate volume range in dB
        let sortedDb = allDecibelSamples.sorted()
        let volumeMin: Float
        let volumeMax: Float
        if sortedDb.isEmpty {
            volumeMin = -40
            volumeMax = -10
        } else {
            let lowIndex = sortedDb.count / 10
            let highIndex = (sortedDb.count * 9) / 10
            volumeMin = sortedDb[max(0, lowIndex)]
            volumeMax = sortedDb[min(sortedDb.count - 1, highIndex)]
        }
        
        return CalibrationData(
            baselineRMS: baselineRMS,
            pitchMin: pitchMin,
            pitchMax: pitchMax,
            volumeMin: volumeMin,
            volumeMax: volumeMax
        )
    }
    
    /// Cancels an in-progress calibration
    func cancelCalibration() {
        guard isCalibrating else { return }
        
        calibrationLog.info("❌ Calibration cancelled")
        
        audioInputManager.stopCapture()
        isCalibrating = false
        
        // Emit cancelled state
        let cancelUpdate = CalibrationProgress(
            currentPhrase: "",
            phraseIndex: currentPhraseIndex,
            totalPhrases: totalPhrases,
            progress: progress,
            state: .cancelled
        )
        progressContinuation?.yield(cancelUpdate)
        progressContinuation?.finish()
    }
}

// MARK: - CalibrationProgress

/// Progress update during voice calibration
struct CalibrationProgress: Sendable {
    
    /// Current phrase being calibrated
    let currentPhrase: String
    
    /// Index of current phrase (0-based)
    let phraseIndex: Int
    
    /// Total number of phrases
    let totalPhrases: Int
    
    /// Overall progress (0.0 - 1.0)
    let progress: Float
    
    /// Current state of calibration
    let state: CalibrationState
}

// MARK: - CalibrationState

/// State of the calibration process
enum CalibrationState: Sendable {
    /// Waiting to start
    case idle
    
    /// Currently recording a phrase
    case recording
    
    /// Processing between phrases
    case processing
    
    /// Calibration complete
    case complete
    
    /// Calibration cancelled
    case cancelled
    
    /// Calibration failed
    case failed(reason: String)
}

// MARK: - Sample Calibration Phrases

extension VoiceCalibrationService {
    
    /// Default sample phrases for calibration
    static let defaultCalibrationPhrases: [String] = [
        "I am confident and capable.",
        "Today I choose to be happy.",
        "I believe in my abilities.",
        "I am worthy of success.",
        "I embrace new challenges with courage."
    ]
    
    /// Short calibration phrases for quick setup
    static let quickCalibrationPhrases: [String] = [
        "I am strong.",
        "I am worthy.",
        "I am capable."
    ]
}
