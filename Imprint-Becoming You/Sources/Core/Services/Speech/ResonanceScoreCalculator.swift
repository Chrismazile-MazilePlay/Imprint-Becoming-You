//
//  ResonanceScoreCalculator.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import Accelerate

// MARK: - ResonanceScoreCalculator

/// Calculates resonance scores from speech analysis data.
///
/// The resonance score is computed from three components:
/// - **Vocal Energy (60%)**: How confidently and loudly the user speaks
/// - **Pitch Stability (30%)**: Consistency of pitch throughout utterance
/// - **Text Accuracy (10%)**: How well the spoken text matches the affirmation
///
/// ## Scoring Philosophy
/// The weighting prioritizes *how* you say something over *what* you say,
/// based on neuroplasticity research showing emotional conviction matters
/// more than perfect recitation.
///
/// ## Usage
/// ```swift
/// let calculator = ResonanceScoreCalculator()
/// calculator.addSample(rms: 0.3, pitch: 180)
/// calculator.setTextAccuracy(0.95)
/// let score = calculator.computeFinalScore()
/// ```
final class ResonanceScoreCalculator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Collected RMS samples
    private var rmsSamples: [Float] = []
    
    /// Collected pitch samples (in Hz)
    private var pitchSamples: [Float] = []
    
    /// Text accuracy from speech recognition
    private var textAccuracy: Float = 0
    
    /// User's calibration data for personalized scoring
    private var calibrationData: CalibrationData?
    
    /// Start time of analysis
    private var startTime: Date?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Minimum samples needed for valid calculation
    private let minimumSamples = 10
    
    // MARK: - Initialization
    
    /// Creates a new calculator
    /// - Parameter calibrationData: Optional calibration data for personalized scoring
    init(calibrationData: CalibrationData? = nil) {
        self.calibrationData = calibrationData
    }
    
    // MARK: - Sample Collection
    
    /// Starts a new analysis session
    func startSession() {
        lock.lock()
        defer { lock.unlock() }
        
        rmsSamples.removeAll()
        pitchSamples.removeAll()
        textAccuracy = 0
        startTime = Date()
    }
    
    /// Adds an RMS sample to the analysis
    /// - Parameter rms: RMS level (0.0 - 1.0)
    func addRMSSample(_ rms: Float) {
        lock.lock()
        defer { lock.unlock() }
        rmsSamples.append(rms)
    }
    
    /// Adds a pitch sample to the analysis
    /// - Parameter pitch: Pitch in Hz (0 if unvoiced)
    func addPitchSample(_ pitch: Float) {
        lock.lock()
        defer { lock.unlock() }
        
        // Only track voiced segments (pitch > 0)
        if pitch > 0 {
            pitchSamples.append(pitch)
        }
    }
    
    /// Adds both RMS and pitch samples
    /// - Parameters:
    ///   - rms: RMS level
    ///   - pitch: Pitch in Hz
    func addSample(rms: Float, pitch: Float) {
        lock.lock()
        defer { lock.unlock() }
        
        rmsSamples.append(rms)
        if pitch > 0 {
            pitchSamples.append(pitch)
        }
    }
    
    /// Sets the text accuracy from speech recognition
    /// - Parameter accuracy: Accuracy value (0.0 - 1.0)
    func setTextAccuracy(_ accuracy: Float) {
        lock.lock()
        defer { lock.unlock() }
        textAccuracy = max(0, min(1, accuracy))
    }
    
    // MARK: - Score Computation
    
    /// Computes the final resonance score
    /// - Returns: Complete resonance record, or nil if insufficient data
    func computeFinalScore(sessionMode: SessionMode) -> ResonanceRecord? {
        lock.lock()
        defer { lock.unlock() }
        
        guard rmsSamples.count >= minimumSamples else {
            return nil
        }
        
        let vocalEnergy = computeVocalEnergyScore()
        let pitchStability = computePitchStabilityScore()
        let textScore = textAccuracy
        
        // Weighted combination
        let overallScore =
            (vocalEnergy * Constants.ResonanceScoring.vocalEnergyWeight) +
            (pitchStability * Constants.ResonanceScoring.pitchStabilityWeight) +
            (textScore * Constants.ResonanceScoring.textAccuracyWeight)
        
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return ResonanceRecord(
            overallScore: overallScore,
            textAccuracy: textScore,
            vocalEnergy: vocalEnergy,
            pitchStability: pitchStability,
            duration: duration,
            sessionMode: sessionMode
        )
    }
    
    /// Computes real-time score during analysis
    /// - Returns: Current estimated score
    func computeRealtimeScore() -> Float {
        lock.lock()
        defer { lock.unlock() }
        
        guard rmsSamples.count >= 5 else { return 0 }
        
        let vocalEnergy = computeVocalEnergyScore()
        let pitchStability = computePitchStabilityScore()
        
        // During real-time, we don't have text accuracy yet
        // Use just vocal energy and pitch stability
        return (vocalEnergy * 0.65) + (pitchStability * 0.35)
    }
    
    // MARK: - Component Calculations
    
    /// Computes vocal energy score from RMS samples
    /// - Returns: Normalized score (0.0 - 1.0)
    private func computeVocalEnergyScore() -> Float {
        guard !rmsSamples.isEmpty else { return 0 }
        
        // Calculate mean RMS
        var meanRMS: Float = 0
        vDSP_meanv(rmsSamples, 1, &meanRMS, vDSP_Length(rmsSamples.count))
        
        // Normalize against calibration or default baseline
        let baseline = calibrationData?.baselineRMS ?? 0.15
        let targetRMS = baseline * 1.5 // Target is 50% above baseline
        
        // Score based on reaching target
        // Exceeding target gives bonus up to 1.0
        let ratio = meanRMS / targetRMS
        let score = min(1.0, ratio)
        
        // Apply curve to reward consistent energy
        return applyScoringCurve(score)
    }
    
    /// Computes pitch stability score from pitch samples
    /// - Returns: Normalized score (0.0 - 1.0)
    private func computePitchStabilityScore() -> Float {
        guard pitchSamples.count >= 5 else {
            // Not enough pitch data - return neutral score
            return 0.7
        }
        
        // Calculate standard deviation of pitch
        var mean: Float = 0
        var stdDev: Float = 0
        vDSP_normalize(pitchSamples, 1, nil, 1, &mean, &stdDev, vDSP_Length(pitchSamples.count))
        
        // Get expected pitch range from calibration
        let expectedRange: Float
        if let calibration = calibrationData {
            expectedRange = calibration.pitchRange
        } else {
            // Default expected range (typical speech variation)
            expectedRange = 50.0 // Hz
        }
        
        // Coefficient of variation (relative to mean)
        let cv = mean > 0 ? (stdDev / mean) : 0
        
        // Target CV for stable speech is around 0.1-0.2
        // Lower is more stable (monotone), higher is more variable
        let targetCV: Float = 0.15
        let maxCV: Float = 0.4
        
        // Score: closer to target is better, too monotone or too variable is worse
        let deviation = abs(cv - targetCV)
        let normalizedDeviation = min(1.0, deviation / (maxCV - targetCV))
        let score = 1.0 - normalizedDeviation
        
        return applyScoringCurve(score)
    }
    
    /// Applies a sigmoid-like curve to make scoring feel natural
    /// - Parameter rawScore: Raw score (0.0 - 1.0)
    /// - Returns: Curved score (0.0 - 1.0)
    private func applyScoringCurve(_ rawScore: Float) -> Float {
        // S-curve that's generous in the middle range
        // Makes it easier to get "good" scores, harder to get "excellent"
        let x = rawScore * 2 - 1 // Map to -1...1
        let curved = (tanh(x * 1.5) + 1) / 2 // Soft S-curve
        return curved
    }
    
    // MARK: - Statistics
    
    /// Current sample count
    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rmsSamples.count
    }
    
    /// Whether enough samples have been collected
    var hasEnoughSamples: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rmsSamples.count >= minimumSamples
    }
    
    /// Current average RMS level
    var averageRMS: Float {
        lock.lock()
        defer { lock.unlock() }
        
        guard !rmsSamples.isEmpty else { return 0 }
        var mean: Float = 0
        vDSP_meanv(rmsSamples, 1, &mean, vDSP_Length(rmsSamples.count))
        return mean
    }
}

// MARK: - Text Accuracy Calculator

/// Calculates text accuracy between expected and recognized text
struct TextAccuracyCalculator {
    
    /// Calculates accuracy between expected and recognized text
    /// - Parameters:
    ///   - expected: The affirmation text
    ///   - recognized: The speech recognition result
    /// - Returns: Accuracy score (0.0 - 1.0)
    static func calculate(expected: String, recognized: String) -> Float {
        let expectedWords = normalizeText(expected)
        let recognizedWords = normalizeText(recognized)
        
        guard !expectedWords.isEmpty else { return 0 }
        
        // Calculate word-level accuracy
        let matchedWords = countMatchedWords(expected: expectedWords, recognized: recognizedWords)
        let wordAccuracy = Float(matchedWords) / Float(expectedWords.count)
        
        // Calculate character-level similarity (Levenshtein-based)
        let charSimilarity = calculateSimilarity(
            expected.lowercased(),
            recognized.lowercased()
        )
        
        // Combine both metrics (word accuracy weighted more)
        return (wordAccuracy * 0.7) + (charSimilarity * 0.3)
    }
    
    /// Normalizes text for comparison
    private static func normalizeText(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .punctuationCharacters)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }
    
    /// Counts matched words using longest common subsequence approach
    private static func countMatchedWords(expected: [String], recognized: [String]) -> Int {
        var matched = 0
        var recognizedSet = Set(recognized)
        
        for word in expected {
            if recognizedSet.contains(word) {
                matched += 1
                recognizedSet.remove(word)
            }
        }
        
        return matched
    }
    
    /// Calculates string similarity using Levenshtein distance
    private static func calculateSimilarity(_ s1: String, _ s2: String) -> Float {
        let distance = levenshteinDistance(Array(s1), Array(s2))
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Float(distance) / Float(maxLength))
    }
    
    /// Computes Levenshtein edit distance
    private static func levenshteinDistance(_ s1: [Character], _ s2: [Character]) -> Int {
        let m = s1.count
        let n = s2.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
}

// MARK: - Pitch Detector

/// Detects pitch from audio samples using autocorrelation
struct PitchDetector {
    
    /// Minimum detectable frequency (Hz)
    static let minFrequency: Float = 50
    
    /// Maximum detectable frequency (Hz)
    static let maxFrequency: Float = 500
    
    /// Detects pitch from audio samples
    /// - Parameters:
    ///   - samples: Audio samples
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: Detected pitch in Hz, or 0 if unvoiced
    static func detectPitch(samples: [Float], sampleRate: Double) -> Float {
        let frameSize = samples.count
        guard frameSize >= 256 else { return 0 }
        
        // Calculate autocorrelation
        let autocorr = autocorrelation(samples)
        
        // Find lag range for expected pitch
        let minLag = Int(Float(sampleRate) / maxFrequency)
        let maxLag = min(Int(Float(sampleRate) / minFrequency), frameSize / 2)
        
        guard minLag < maxLag else { return 0 }
        
        // Find peak in autocorrelation within lag range
        var maxValue: Float = 0
        var bestLag = 0
        
        for lag in minLag..<maxLag {
            if autocorr[lag] > maxValue {
                maxValue = autocorr[lag]
                bestLag = lag
            }
        }
        
        // Check if peak is significant (voiced detection)
        let threshold: Float = 0.3
        guard maxValue > threshold * autocorr[0] else {
            return 0 // Unvoiced
        }
        
        // Convert lag to frequency
        let pitch = Float(sampleRate) / Float(bestLag)
        
        // Validate pitch range
        guard pitch >= minFrequency && pitch <= maxFrequency else {
            return 0
        }
        
        return pitch
    }
    
    /// Computes autocorrelation of samples
    private static func autocorrelation(_ samples: [Float]) -> [Float] {
        let n = samples.count
        var result = [Float](repeating: 0, count: n)
        
        // Simple autocorrelation (could use vDSP for optimization)
        for lag in 0..<n {
            var sum: Float = 0
            for i in 0..<(n - lag) {
                sum += samples[i] * samples[i + lag]
            }
            result[lag] = sum
        }
        
        // Normalize
        if result[0] > 0 {
            let norm = result[0]
            for i in 0..<n {
                result[i] /= norm
            }
        }
        
        return result
    }
}
