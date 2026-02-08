//
//  VoiceCalibrationService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import AVFoundation
import Accelerate
import os.log

// MARK: - Logger

private let calibrationLog = Logger(subsystem: "com.imprint.audio", category: "VoiceCalibration")

// MARK: - VoiceCalibrationService

/// Captures baseline voice measurements during onboarding using speech recognition.
///
/// Uses `SpeechCaptureService` for both speech recognition and raw audio capture.
/// This is the same battle-tested pipeline used in practice mode's listening flow.
///
/// ## Calibration Process
/// 1. Microphone capture starts once and stays on throughout
/// 2. System shows each phrase and listens for the user to speak it
/// 3. When speech recognition confirms the phrase was spoken (≥75% word coverage),
///    the system auto-advances to the next phrase
/// 4. After all 5 phrases, baseline voice metrics are computed
/// 5. Results are stored in `UserProfile.calibrationData`
///
/// ## Voice Metrics Captured
/// - Baseline volume (RMS) with standard deviation
/// - Pitch range (min/max Hz), mean, coefficient of variation, semitone range
/// - Spectral centroid with standard deviation
/// - Speaking volume range (dB)
///
/// ## Usage
/// ```swift
/// let captureService = SpeechCaptureService()
/// let calibrationService = VoiceCalibrationService(speechCaptureService: captureService)
/// let data = try await calibrationService.performCalibration(
///     with: VoiceCalibrationService.defaultCalibrationPhrases
/// )
/// ```
@MainActor
final class VoiceCalibrationService: VoiceCalibrationServiceProtocol {

    // MARK: - Properties

    /// Speech capture service for microphone + speech recognition
    private let speechCaptureService: any SpeechCaptureServiceProtocol

    /// Collected RMS samples across all calibration utterances
    private var allRMSSamples: [Float] = []

    /// Collected pitch samples across all calibration utterances
    private var allPitchSamples: [Float] = []

    /// Collected dB levels across all calibration utterances
    private var allDecibelSamples: [Float] = []

    /// Collected spectral centroid samples across all calibration utterances (Hz)
    private var allSpectralCentroidSamples: [Float] = []

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

    /// Per-phrase timeout (seconds) — auto-advances if user doesn't speak
    private let phraseTimeout: TimeInterval = 15.0

    /// Word coverage threshold for phrase completion (0.0 - 1.0)
    private let completionThreshold: Float = 0.75

    // MARK: - Initialization

    /// Creates a new calibration service
    /// - Parameter speechCaptureService: Speech capture service for audio + recognition
    init(speechCaptureService: any SpeechCaptureServiceProtocol) {
        self.speechCaptureService = speechCaptureService
        calibrationLog.info("✅ VoiceCalibrationService initialized")
    }

    // MARK: - Calibration

    /// Performs voice calibration with sample affirmations.
    ///
    /// Starts microphone capture once and keeps it running through all phrases.
    /// Each phrase auto-advances when speech recognition confirms the user has
    /// spoken it (≥75% word coverage), or after a 15-second timeout.
    ///
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
        allSpectralCentroidSamples.removeAll()
        currentPhraseIndex = 0
        totalPhrases = sampleAffirmations.count
        progress = 0
        isCalibrating = true

        defer {
            isCalibrating = false
            speechCaptureService.stopCapture()
            progressContinuation?.finish()
        }

        // Request permissions before starting capture.
        // SpeechCaptureService.startCapture() checks permissions internally, but
        // throws raw SpeechCaptureError codes. By requesting here, we ensure the
        // system permission dialogs are shown and provide user-friendly error messages.
        let hasMic = await speechCaptureService.requestMicrophonePermission()
        guard hasMic else {
            throw AppError.microphoneAccessDenied
        }

        let hasSpeech = await speechCaptureService.requestSpeechRecognitionPermission()
        guard hasSpeech else {
            throw AppError.calibrationFailed(
                reason: "Speech recognition permission is required for voice calibration"
            )
        }

        // Start capture ONCE — mic stays on for all phrases
        try await speechCaptureService.startCapture()

        // Process each affirmation with speech-driven advancement
        for (index, affirmation) in sampleAffirmations.enumerated() {
            currentPhraseIndex = index
            progress = Float(index) / Float(totalPhrases)

            calibrationLog.info("📝 Calibrating phrase \(index + 1)/\(self.totalPhrases): \"\(affirmation.prefix(30))...\"")

            // Emit recording state for this phrase
            progressContinuation?.yield(CalibrationProgress(
                currentPhrase: affirmation,
                phraseIndex: index,
                totalPhrases: totalPhrases,
                progress: progress,
                state: .recording
            ))

            // Listen for this phrase (blocks until spoken or timeout)
            try await listenForPhrase(affirmation)

            // Reset recognition between phrases (mic stays on)
            if index < sampleAffirmations.count - 1 {
                // Brief processing state between phrases
                progressContinuation?.yield(CalibrationProgress(
                    currentPhrase: affirmation,
                    phraseIndex: index,
                    totalPhrases: totalPhrases,
                    progress: Float(index + 1) / Float(totalPhrases),
                    state: .processing
                ))

                try speechCaptureService.resetRecognition()

                // Small delay for UI transition between phrases
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        // Compute calibration data from collected samples
        progress = 1.0
        let calibrationData = computeCalibrationData()

        calibrationLog.info("✅ Calibration complete - RMS: \(calibrationData.baselineRMS), Pitch: \(calibrationData.pitchMin)-\(calibrationData.pitchMax) Hz")

        // Emit completion
        progressContinuation?.yield(CalibrationProgress(
            currentPhrase: "",
            phraseIndex: totalPhrases,
            totalPhrases: totalPhrases,
            progress: 1.0,
            state: .complete
        ))

        return calibrationData
    }

    /// Listens for a single phrase using speech recognition and collects audio samples.
    ///
    /// Blocks until either:
    /// 1. Speech recognition confirms the phrase was spoken (≥75% word coverage)
    /// 2. The per-phrase timeout (15s) expires
    /// 3. An error occurs
    ///
    /// While listening, collects RMS, pitch, spectral centroid, and dB samples
    /// from the raw audio buffers for baseline profiling.
    ///
    /// - Parameter phrase: The expected phrase text
    /// - Throws: `AppError.calibrationFailed` on capture errors
    private func listenForPhrase(_ phrase: String) async throws {
        let startTime = Date()

        for await update in speechCaptureService.captureStream {
            // Check for cancellation
            guard isCalibrating else { return }

            switch update {
            case .transcription(let text, _):
                // Check if user has spoken enough of the phrase
                let result = TextAccuracyCalculator.evaluateCompletion(
                    expected: phrase,
                    recognized: text,
                    completionThreshold: completionThreshold
                )

                if result.isComplete {
                    calibrationLog.info("✅ Phrase detected: \(Int(result.wordsCovered * 100))% coverage")
                    return
                }

            case .audioBuffer(let samples, let sampleRate, let rmsLevel):
                // Collect RMS
                allRMSSamples.append(rmsLevel)

                // Compute dB from RMS
                let dB: Float = rmsLevel > 0 ? 20 * log10(rmsLevel) : -160
                allDecibelSamples.append(dB)

                // Detect and collect pitch
                let pitch = PitchDetector.detectPitch(
                    samples: samples,
                    sampleRate: sampleRate
                )
                if pitch > 0 {
                    allPitchSamples.append(pitch)
                }

                // Compute and collect spectral centroid
                let centroid = SpectralAnalyzer.spectralCentroid(
                    samples: samples,
                    sampleRate: sampleRate
                )
                if centroid > 0 {
                    allSpectralCentroidSamples.append(centroid)
                }

            case .audioLevel(let level):
                // Emit progress with live audio level for UI mic visualization
                progressContinuation?.yield(CalibrationProgress(
                    currentPhrase: phrase,
                    phraseIndex: currentPhraseIndex,
                    totalPhrases: totalPhrases,
                    progress: progress,
                    state: .recording,
                    audioLevel: level
                ))

                // Check timeout — auto-advance if user doesn't speak
                if Date().timeIntervalSince(startTime) >= phraseTimeout {
                    calibrationLog.info("⏱️ Phrase timed out after \(self.phraseTimeout)s, advancing")
                    return
                }

            case .error(let err):
                calibrationLog.error("❌ Capture error during calibration: \(String(describing: err))")
                throw AppError.calibrationFailed(reason: "\(err)")

            case .stopped:
                // Capture stopped unexpectedly
                calibrationLog.warning("⚠️ Capture stopped during calibration")
                return

            case .silenceDetected, .started:
                break
            }
        }
    }

    /// Computes calibration data from all collected samples.
    ///
    /// Calculates baseline metrics for personalized resonance scoring:
    /// - RMS: median + standard deviation
    /// - Pitch: mean, 10th/90th percentile, coefficient of variation, range in semitones
    /// - Spectral centroid: median + standard deviation
    /// - Volume: 10th/90th percentile dB
    private func computeCalibrationData() -> CalibrationData {

        // MARK: RMS Energy

        let sortedRMS = allRMSSamples.sorted()
        let baselineRMS: Float
        let rmsStdDev: Float
        if sortedRMS.isEmpty {
            baselineRMS = Constants.ResonanceScoring.defaultBaselineRMS
            rmsStdDev = Constants.ResonanceScoring.defaultRMSStdDev
        } else {
            baselineRMS = sortedRMS[sortedRMS.count / 2] // median
            var mean: Float = 0
            var stdDev: Float = 0
            vDSP_normalize(allRMSSamples, 1, nil, 1, &mean, &stdDev, vDSP_Length(allRMSSamples.count))
            rmsStdDev = max(stdDev, 0.01) // Floor to prevent zero-division in Z-score
        }

        // MARK: Pitch

        let pitchMeanHz: Float
        let pitchMin: Float
        let pitchMax: Float
        let baselinePitchCV: Float
        let baselinePitchRangeSemitones: Float

        if allPitchSamples.isEmpty {
            pitchMeanHz = Constants.ResonanceScoring.defaultPitchMeanHz
            pitchMin = 100
            pitchMax = 300
            baselinePitchCV = Constants.ResonanceScoring.defaultPitchCV
            baselinePitchRangeSemitones = Constants.ResonanceScoring.defaultPitchRangeSemitones
        } else {
            // Mean and standard deviation via vDSP
            var pMean: Float = 0
            var pStdDev: Float = 0
            vDSP_normalize(allPitchSamples, 1, nil, 1, &pMean, &pStdDev, vDSP_Length(allPitchSamples.count))

            pitchMeanHz = pMean

            // 10th/90th percentile for range
            let sortedPitch = allPitchSamples.sorted()
            let lowIndex = sortedPitch.count / 10
            let highIndex = (sortedPitch.count * 9) / 10
            pitchMin = sortedPitch[max(0, lowIndex)]
            pitchMax = sortedPitch[min(sortedPitch.count - 1, highIndex)]

            // Coefficient of variation
            baselinePitchCV = pMean > 0 ? (pStdDev / pMean) : Constants.ResonanceScoring.defaultPitchCV

            // Range in semitones: 12 * log2(max / min)
            if pitchMin > 0 && pitchMax > pitchMin {
                baselinePitchRangeSemitones = 12.0 * log2(pitchMax / pitchMin)
            } else {
                baselinePitchRangeSemitones = Constants.ResonanceScoring.defaultPitchRangeSemitones
            }
        }

        // MARK: Spectral Centroid

        let baselineSpectralCentroid: Float
        let spectralCentroidStdDev: Float

        if allSpectralCentroidSamples.isEmpty {
            baselineSpectralCentroid = Constants.ResonanceScoring.defaultSpectralCentroid
            spectralCentroidStdDev = Constants.ResonanceScoring.defaultSpectralCentroidStdDev
        } else {
            let sortedCentroid = allSpectralCentroidSamples.sorted()
            baselineSpectralCentroid = sortedCentroid[sortedCentroid.count / 2] // median

            var cMean: Float = 0
            var cStdDev: Float = 0
            vDSP_normalize(allSpectralCentroidSamples, 1, nil, 1, &cMean, &cStdDev, vDSP_Length(allSpectralCentroidSamples.count))
            spectralCentroidStdDev = max(cStdDev, 10.0) // Floor to prevent zero-division
        }

        // MARK: Volume (dB)

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
            rmsStdDev: rmsStdDev,
            pitchMeanHz: pitchMeanHz,
            pitchMin: pitchMin,
            pitchMax: pitchMax,
            baselinePitchCV: baselinePitchCV,
            baselinePitchRangeSemitones: baselinePitchRangeSemitones,
            baselineSpectralCentroid: baselineSpectralCentroid,
            spectralCentroidStdDev: spectralCentroidStdDev,
            volumeMin: volumeMin,
            volumeMax: volumeMax
        )
    }

    /// Cancels an in-progress calibration
    func cancelCalibration() {
        guard isCalibrating else { return }

        calibrationLog.info("❌ Calibration cancelled")

        speechCaptureService.cancelCapture()
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

    /// Real-time audio level (0.0 - 1.0) for microphone visualization
    let audioLevel: Float

    /// Creates a calibration progress update.
    /// - Parameters:
    ///   - currentPhrase: The phrase being calibrated
    ///   - phraseIndex: Index of the current phrase (0-based)
    ///   - totalPhrases: Total number of phrases
    ///   - progress: Overall progress (0.0 - 1.0)
    ///   - state: Current calibration state
    ///   - audioLevel: Real-time audio level (0.0 - 1.0), defaults to 0
    init(
        currentPhrase: String,
        phraseIndex: Int,
        totalPhrases: Int,
        progress: Float,
        state: CalibrationState,
        audioLevel: Float = 0
    ) {
        self.currentPhrase = currentPhrase
        self.phraseIndex = phraseIndex
        self.totalPhrases = totalPhrases
        self.progress = progress
        self.state = state
        self.audioLevel = audioLevel
    }
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

    /// Default calibration phrases designed for full vocal range profiling.
    ///
    /// Five phrases targeting comprehensive phonetic coverage:
    /// - **Vowel coverage**: /iː/, /ɪ/, /ɛ/, /æ/, /ɑː/, /ɔː/, /ɔɪ/, /oʊ/, /ʊ/, /uː/, /ʌ/, /aɪ/
    /// - **Consonant coverage**: Plosives, fricatives, nasals, and liquids
    /// - **Progressive length**: 5→6→7→7→7 words for natural pitch contour
    /// - **Prosody variation**: Flat declarative → moderate → rising → emphatic
    static let defaultCalibrationPhrases: [String] = [
        "I am strong and whole.",                            // Baseline pitch — /ɑ/, /ɔ/, /oʊ/
        "My heart knows peace and joy.",                     // Open vowels — /ɑː/, /oʊ/, /iː/, /ɔɪ/
        "Every challenge brings me growth and wisdom.",      // Varied consonants — plosives, fricatives
        "I choose to rise above my fears.",                  // Rising intonation — /aɪ/, /ʌ/, /ɪ/
        "Today I step forward with unstoppable courage."     // Emphatic projection — dynamic range
    ]

    /// Short calibration phrases for quick setup
    static let quickCalibrationPhrases: [String] = [
        "I am strong.",
        "I am worthy.",
        "I am capable."
    ]
}
