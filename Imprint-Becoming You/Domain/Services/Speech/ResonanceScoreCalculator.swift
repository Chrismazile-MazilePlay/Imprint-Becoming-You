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
/// - **Vocal Projection (40%)**: RMS energy + spectral centroid (brightness)
/// - **Expressiveness (35%)**: Pitch variation + range utilization (rewards natural variation)
/// - **Text Accuracy (25%)**: How well the spoken text matches the affirmation
///
/// ## Scoring Philosophy
/// The weighting prioritizes *how* you say something over *what* you say.
/// All vocal metrics are Z-score normalized against the user's personal
/// calibration baseline using sigmoid mapping, so a naturally quiet speaker
/// who projects confidently scores the same as a naturally loud speaker.
///
/// ## Usage
/// ```swift
/// let calculator = ResonanceScoreCalculator(calibrationData: calibration)
/// calculator.startSession()
/// calculator.addRMSSample(0.3)
/// calculator.addPitchSample(180)
/// calculator.addSpectralCentroidSample(1800)
/// calculator.setTextAccuracy(0.95)
/// let record = calculator.computeFinalScore(sessionMode: .readThenSpeak)
/// ```
final class ResonanceScoreCalculator: @unchecked Sendable {

    // MARK: - Properties

    /// Collected RMS samples (unsmoothed, from audio buffer)
    private var rmsSamples: [Float] = []

    /// Collected pitch samples (Hz, voiced segments only)
    private var pitchSamples: [Float] = []

    /// Collected spectral centroid samples (Hz)
    private var spectralCentroidSamples: [Float] = []

    /// Text accuracy from speech recognition (0.0 - 1.0)
    private var textAccuracy: Float = 0

    /// User's calibration data for personalized scoring
    private let calibrationData: CalibrationData

    /// Start time of analysis
    private var startTime: Date?

    /// Lock for thread safety
    private let lock = NSLock()

    /// Minimum RMS samples needed for valid calculation
    private let minimumSamples = 10

    // MARK: - Initialization

    /// Creates a new calculator with calibration data.
    ///
    /// - Parameter calibrationData: User's calibration baseline.
    ///   Defaults to `CalibrationData.uncalibrated` if nil.
    init(calibrationData: CalibrationData? = nil) {
        self.calibrationData = calibrationData ?? .uncalibrated
    }

    // MARK: - Sample Collection

    /// Starts a new analysis session. Clears all previous samples.
    func startSession() {
        lock.lock()
        defer { lock.unlock() }

        rmsSamples.removeAll(keepingCapacity: true)
        pitchSamples.removeAll(keepingCapacity: true)
        spectralCentroidSamples.removeAll(keepingCapacity: true)
        textAccuracy = 0
        startTime = Date()
    }

    /// Adds an RMS sample to the analysis.
    /// - Parameter rms: Unsmoothed RMS level (0.0 - 1.0)
    func addRMSSample(_ rms: Float) {
        lock.lock()
        defer { lock.unlock() }
        rmsSamples.append(rms)
    }

    /// Adds a pitch sample to the analysis.
    /// - Parameter pitch: Pitch in Hz (0 if unvoiced — will be filtered)
    func addPitchSample(_ pitch: Float) {
        lock.lock()
        defer { lock.unlock() }

        // Only track voiced segments
        if pitch > 0 {
            pitchSamples.append(pitch)
        }
    }

    /// Adds a spectral centroid sample to the analysis.
    /// - Parameter centroid: Spectral centroid in Hz (0 if invalid — will be filtered)
    func addSpectralCentroidSample(_ centroid: Float) {
        lock.lock()
        defer { lock.unlock() }

        if centroid > 0 {
            spectralCentroidSamples.append(centroid)
        }
    }

    /// Adds RMS, pitch, and spectral centroid samples together.
    /// - Parameters:
    ///   - rms: RMS level
    ///   - pitch: Pitch in Hz
    ///   - spectralCentroid: Spectral centroid in Hz
    func addSample(rms: Float, pitch: Float, spectralCentroid: Float) {
        lock.lock()
        defer { lock.unlock() }

        rmsSamples.append(rms)
        if pitch > 0 { pitchSamples.append(pitch) }
        if spectralCentroid > 0 { spectralCentroidSamples.append(spectralCentroid) }
    }

    /// Sets the text accuracy from speech recognition.
    /// - Parameter accuracy: Accuracy value (0.0 - 1.0)
    func setTextAccuracy(_ accuracy: Float) {
        lock.lock()
        defer { lock.unlock() }
        textAccuracy = max(0, min(1, accuracy))
    }

    // MARK: - Score Computation

    /// Computes the final resonance score from all collected samples.
    ///
    /// - Parameter sessionMode: The session mode used during this recording
    /// - Returns: Complete resonance record, or `nil` if insufficient data (< 10 RMS samples)
    func computeFinalScore(sessionMode: SessionMode) -> ResonanceRecord? {
        lock.lock()
        defer { lock.unlock() }

        guard rmsSamples.count >= minimumSamples else {
            return nil
        }

        let vocalProjection = computeVocalProjectionScore()
        let expressiveness = computeExpressivenessScore()
        let textScore = textAccuracy

        // Weighted combination
        let overallScore =
            (vocalProjection * Constants.ResonanceScoring.vocalEnergyWeight) +
            (expressiveness * Constants.ResonanceScoring.pitchStabilityWeight) +
            (textScore * Constants.ResonanceScoring.textAccuracyWeight)

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        return ResonanceRecord(
            overallScore: overallScore,
            textAccuracy: textScore,
            vocalEnergy: vocalProjection,
            pitchStability: expressiveness,
            duration: duration,
            sessionMode: sessionMode
        )
    }

    /// Computes a real-time score estimate during active analysis.
    ///
    /// Uses only vocal projection and expressiveness (text accuracy
    /// is not yet available during capture).
    /// - Returns: Current estimated score (0.0 - 1.0)
    func computeRealtimeScore() -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard rmsSamples.count >= 5 else { return 0 }

        let vocalProjection = computeVocalProjectionScore()
        let expressiveness = computeExpressivenessScore()

        // Proportional weights (excluding text accuracy)
        let projWeight = Constants.ResonanceScoring.vocalEnergyWeight
        let exprWeight = Constants.ResonanceScoring.pitchStabilityWeight
        let totalWeight = projWeight + exprWeight

        return (vocalProjection * projWeight + expressiveness * exprWeight) / totalWeight
    }

    // MARK: - Component Calculations

    /// Computes Vocal Projection score from RMS + spectral centroid.
    ///
    /// Combines:
    /// - **RMS energy (60%)**: Volume relative to personal baseline
    /// - **Spectral centroid (40%)**: Speech brightness — projected vs. mumbled
    ///
    /// Both are sigmoid-normalized against calibration, making the score
    /// robust to iOS AGC and microphone distance variations.
    private func computeVocalProjectionScore() -> Float {
        guard !rmsSamples.isEmpty else { return 0.5 }

        // Mean RMS via vDSP
        var meanRMS: Float = 0
        vDSP_meanv(rmsSamples, 1, &meanRMS, vDSP_Length(rmsSamples.count))

        // Sigmoid normalize against personal baseline
        let rmsScore = sigmoidNormalize(
            value: meanRMS,
            baseline: calibrationData.baselineRMS,
            scale: calibrationData.rmsStdDev
        )

        // Spectral centroid component
        let spectralScore: Float
        if spectralCentroidSamples.count >= 5 {
            var meanCentroid: Float = 0
            vDSP_meanv(spectralCentroidSamples, 1, &meanCentroid, vDSP_Length(spectralCentroidSamples.count))

            spectralScore = sigmoidNormalize(
                value: meanCentroid,
                baseline: calibrationData.baselineSpectralCentroid,
                scale: calibrationData.spectralCentroidStdDev
            )
        } else {
            // Insufficient spectral data — use neutral score
            spectralScore = 0.5
        }

        // Weighted combination: RMS 60%, spectral 40%
        return rmsScore * 0.6 + spectralScore * 0.4
    }

    /// Computes Expressiveness score from pitch variation + range.
    ///
    /// **REWARDS pitch variation** — confident, enthusiastic speech has
    /// natural melodic variation. Monotone speech scores lower.
    ///
    /// Combines:
    /// - **Pitch CV (60%)**: Coefficient of variation — higher than baseline = more expressive
    /// - **Range utilization (40%)**: How much of natural pitch range is used
    private func computeExpressivenessScore() -> Float {
        guard pitchSamples.count >= 5 else {
            // Insufficient pitch data — return neutral score
            return 0.5
        }

        // Calculate pitch mean and standard deviation via vDSP
        var pitchMean: Float = 0
        var pitchStdDev: Float = 0
        vDSP_normalize(pitchSamples, 1, nil, 1, &pitchMean, &pitchStdDev, vDSP_Length(pitchSamples.count))

        guard pitchMean > 0 else { return 0.5 }

        // Coefficient of variation (relative variability)
        let pitchCV = pitchStdDev / pitchMean

        // Sigmoid normalize: higher CV than baseline = higher score (REWARDS variation)
        let cvScore = sigmoidNormalize(
            value: pitchCV,
            baseline: calibrationData.baselinePitchCV,
            scale: 0.05 // ~1 stddev in CV corresponds to meaningful variation change
        )

        // Pitch range utilization
        var minPitch: Float = 0
        var maxPitch: Float = 0
        vDSP_minv(pitchSamples, 1, &minPitch, vDSP_Length(pitchSamples.count))
        vDSP_maxv(pitchSamples, 1, &maxPitch, vDSP_Length(pitchSamples.count))

        let rangeScore: Float
        if minPitch > 0 && maxPitch > minPitch {
            // Convert to semitones: 12 * log2(max/min)
            let rangeSemitones = 12.0 * log2(maxPitch / minPitch)
            let baselineRange = calibrationData.baselinePitchRangeSemitones

            // Score as utilization ratio (capped at 1.0)
            rangeScore = baselineRange > 0 ? min(1.0, rangeSemitones / baselineRange) : 0.5
        } else {
            rangeScore = 0.0
        }

        // Weighted combination: CV 60%, range 40%
        return cvScore * 0.6 + rangeScore * 0.4
    }

    // MARK: - Normalization

    /// Normalizes a value against a personal baseline using sigmoid mapping.
    ///
    /// The sigmoid function maps the Z-score to [0, 1]:
    /// - `value == baseline` → 0.5
    /// - `value > baseline` → 0.5 to ~1.0 (above average)
    /// - `value < baseline` → ~0.0 to 0.5 (below average)
    ///
    /// - Parameters:
    ///   - value: The measured value
    ///   - baseline: The user's calibrated baseline (maps to 0.5)
    ///   - scale: Standard deviation for Z-score (controls sensitivity)
    /// - Returns: Normalized score (0.0 - 1.0)
    private func sigmoidNormalize(value: Float, baseline: Float, scale: Float) -> Float {
        guard scale > 0 else { return 0.5 }
        let z = (value - baseline) / scale
        // Gentle sigmoid: steepness factor 1.5 provides good discrimination
        // without being too aggressive at the extremes
        return 1.0 / (1.0 + exp(-z * 1.5))
    }

    // MARK: - Statistics

    /// Current RMS sample count
    var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rmsSamples.count
    }

    /// Whether enough samples have been collected for scoring
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

/// Calculates text accuracy between expected and recognized text.
///
/// Uses a combination of word-level matching (70%) and character-level
/// Levenshtein similarity (30%) for robust accuracy measurement.
struct TextAccuracyCalculator {

    /// Calculates accuracy between expected and recognized text.
    /// - Parameters:
    ///   - expected: The affirmation text
    ///   - recognized: The speech recognition result
    /// - Returns: Accuracy score (0.0 - 1.0)
    static func calculate(expected: String, recognized: String) -> Float {
        let expectedWords = normalizeText(expected)
        let recognizedWords = normalizeText(recognized)

        guard !expectedWords.isEmpty else { return 0 }
        guard !recognizedWords.isEmpty else { return 0 }

        let cleanExpected = expected.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRecognized = recognized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanExpected.isEmpty, !cleanRecognized.isEmpty else { return 0 }

        // Word-level accuracy (70%)
        let matchedWords = countMatchedWords(expected: expectedWords, recognized: recognizedWords)
        let wordAccuracy = Float(matchedWords) / Float(expectedWords.count)

        // Character-level similarity via Levenshtein (30%)
        let charSimilarity = calculateSimilarity(cleanExpected, cleanRecognized)

        return (wordAccuracy * 0.7) + (charSimilarity * 0.3)
    }

    /// Normalizes text for comparison by lowercasing, stripping punctuation, and splitting.
    private static func normalizeText(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .punctuationCharacters)
            .joined()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    /// Counts matched words using a multiset approach.
    ///
    /// Properly handles duplicate words — each occurrence counts independently.
    private static func countMatchedWords(expected: [String], recognized: [String]) -> Int {
        var recognizedCounts: [String: Int] = [:]
        for word in recognized {
            recognizedCounts[word, default: 0] += 1
        }

        var matched = 0
        for word in expected {
            if let count = recognizedCounts[word], count > 0 {
                matched += 1
                recognizedCounts[word] = count - 1
            }
        }

        return matched
    }

    /// Calculates string similarity using Levenshtein distance.
    private static func calculateSimilarity(_ s1: String, _ s2: String) -> Float {
        let distance = levenshteinDistance(Array(s1), Array(s2))
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Float(distance) / Float(maxLength))
    }

    /// Computes Levenshtein edit distance using O(mn) dynamic programming.
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
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - Completion Evaluation

    /// Result of evaluating affirmation completion.
    struct CompletionResult: Sendable {
        /// Did user say enough words to be considered complete?
        let isComplete: Bool
        /// How accurate were the words that were said (0.0 - 1.0)
        let accuracy: Float
        /// Percentage of expected words that were spoken (0.0 - 1.0)
        let wordsCovered: Float
        /// Number of words matched
        let matchedWordCount: Int
        /// Total expected words
        let expectedWordCount: Int
    }

    /// Evaluates whether user completed the affirmation and how accurately.
    /// - Parameters:
    ///   - expected: The affirmation text to speak
    ///   - recognized: The speech recognition result
    ///   - completionThreshold: Minimum word coverage to be considered complete (default 75%)
    /// - Returns: Completion result with accuracy and coverage details
    static func evaluateCompletion(
        expected: String,
        recognized: String,
        completionThreshold: Float = 0.75
    ) -> CompletionResult {
        let expectedWords = normalizeText(expected)
        let recognizedWords = normalizeText(recognized)

        guard !expectedWords.isEmpty else {
            return CompletionResult(
                isComplete: true,
                accuracy: 1.0,
                wordsCovered: 1.0,
                matchedWordCount: 0,
                expectedWordCount: 0
            )
        }

        guard !recognizedWords.isEmpty else {
            return CompletionResult(
                isComplete: false,
                accuracy: 0.0,
                wordsCovered: 0.0,
                matchedWordCount: 0,
                expectedWordCount: expectedWords.count
            )
        }

        let matchedCount = countMatchedWords(expected: expectedWords, recognized: recognizedWords)
        let wordsCovered = Float(matchedCount) / Float(expectedWords.count)
        let accuracy = calculate(expected: expected, recognized: recognized)
        let isComplete = wordsCovered >= completionThreshold

        return CompletionResult(
            isComplete: isComplete,
            accuracy: accuracy,
            wordsCovered: wordsCovered,
            matchedWordCount: matchedCount,
            expectedWordCount: expectedWords.count
        )
    }
}

// MARK: - Pitch Detector

/// Detects fundamental pitch from audio samples using FFT-based autocorrelation.
///
/// Uses `vDSP` for high-performance autocorrelation via the Wiener-Khinchin
/// theorem: autocorrelation = IFFT(|FFT(signal)|²).
/// This is O(n log n) vs. the naive O(n²) approach.
///
/// ## Frequency Range
/// Detects pitch between 50 Hz (low bass voice) and 500 Hz (high soprano),
/// covering the full range of adult speech fundamental frequencies.
struct PitchDetector {

    /// Minimum detectable frequency (Hz)
    static let minFrequency: Float = 50

    /// Maximum detectable frequency (Hz)
    static let maxFrequency: Float = 500

    /// Detects the fundamental pitch from audio samples.
    ///
    /// - Parameters:
    ///   - samples: Audio PCM samples (Float)
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: Detected pitch in Hz, or 0 if unvoiced/insufficient data
    static func detectPitch(samples: [Float], sampleRate: Double) -> Float {
        let frameSize = samples.count
        guard frameSize >= 256 else { return 0 }

        // Compute autocorrelation via FFT (Wiener-Khinchin theorem)
        let autocorr = fftAutocorrelation(samples)

        // Determine lag range for expected pitch frequencies
        let minLag = Int(Float(sampleRate) / maxFrequency)
        let maxLag = min(Int(Float(sampleRate) / minFrequency), autocorr.count / 2)

        guard minLag < maxLag, maxLag <= autocorr.count else { return 0 }

        // Find peak in autocorrelation within valid lag range
        var maxValue: Float = 0
        var bestLag = 0

        for lag in minLag..<maxLag {
            if autocorr[lag] > maxValue {
                maxValue = autocorr[lag]
                bestLag = lag
            }
        }

        // Voiced detection: peak must be significant relative to zero-lag
        let threshold: Float = 0.3
        guard autocorr[0] > 0, maxValue > threshold * autocorr[0] else {
            return 0
        }

        // Convert lag to frequency
        let pitch = Float(sampleRate) / Float(bestLag)

        // Validate pitch range
        guard pitch >= minFrequency, pitch <= maxFrequency else {
            return 0
        }

        return pitch
    }

    /// Computes autocorrelation using FFT (Wiener-Khinchin theorem).
    ///
    /// Steps: zero-pad → FFT → power spectrum → IFFT → real part
    /// Complexity: O(n log n) vs O(n²) for naive autocorrelation.
    private static func fftAutocorrelation(_ samples: [Float]) -> [Float] {
        let n = samples.count

        // Find next power of 2 for zero-padded length (2N for linear autocorrelation)
        let fftLength = 1 << Int(ceil(log2(Double(n * 2))))
        let log2n = vDSP_Length(log2(Double(fftLength)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            // Fallback to naive autocorrelation if FFT setup fails
            return naiveAutocorrelation(samples)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfN = fftLength / 2

        // Prepare input: zero-padded signal in split complex format
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        // Pack samples into split complex (interleaved real/imag)
        // For real-valued input, we pack pairs into real and imag
        for i in 0..<min(n, fftLength) {
            if i % 2 == 0 {
                realPart[i / 2] = samples[i]
            } else {
                imagPart[i / 2] = samples[i]
            }
        }

        // Perform FFT-based autocorrelation in-place using withUnsafeMutableBufferPointer
        // to satisfy Swift's pointer lifetime requirements.
        // Wiener-Khinchin theorem: autocorrelation = IFFT(|FFT(x)|²)
        let result: [Float] = realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Forward FFT (in-place)
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute power spectrum |X(f)|² in-place.
                //
                // vDSP_fft_zrip uses a special packed format for index 0:
                //   realp[0] = DC component (real-valued)
                //   imagp[0] = Nyquist component (real-valued)
                // These are NOT a complex pair — they must be squared independently.
                realBuf[0] = realBuf[0] * realBuf[0]
                imagBuf[0] = imagBuf[0] * imagBuf[0]

                // Bins 1..<halfN are standard complex: |X[k]|² = real² + imag²
                for k in 1..<halfN {
                    let r = realBuf[k]
                    let im = imagBuf[k]
                    realBuf[k] = r * r + im * im
                    imagBuf[k] = 0  // Power spectrum is real for non-DC/Nyquist bins
                }

                // Inverse FFT (in-place) → autocorrelation
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_INVERSE))

                // Unpack from split complex back to real values and scale.
                // vDSP_fft_zrip inverse output uses the same packed format:
                //   result[2k] = realp[k], result[2k+1] = imagp[k]
                let scale = 1.0 / Float(2 * fftLength)
                var out = [Float](repeating: 0, count: n)

                for i in 0..<min(n, halfN) {
                    if i % 2 == 0 {
                        out[i] = realBuf[i / 2] * scale
                    } else {
                        out[i] = imagBuf[i / 2] * scale
                    }
                }

                return out
            }
        }

        return result
    }

    /// Fallback naive autocorrelation if FFT setup fails.
    /// O(n²) complexity — only used as safety net.
    private static func naiveAutocorrelation(_ samples: [Float]) -> [Float] {
        let n = samples.count
        var result = [Float](repeating: 0, count: n)

        for lag in 0..<n {
            var sum: Float = 0
            vDSP_dotpr(
                samples, 1,
                [Float](samples[lag...]), 1,
                &sum,
                vDSP_Length(n - lag)
            )
            result[lag] = sum
        }

        return result
    }
}

// MARK: - Spectral Analyzer

/// Computes spectral features from audio samples using vDSP FFT.
///
/// The spectral centroid represents the "center of mass" of the frequency
/// spectrum — higher values indicate brighter, more projected speech.
/// This metric is robust to iOS AGC because it measures *where* energy
/// is distributed in the spectrum, not *how much* total energy there is.
struct SpectralAnalyzer {

    /// Minimum samples required for spectral analysis.
    /// FFT needs at least 512 samples for meaningful frequency resolution.
    static let minimumSamples = 512

    /// Computes spectral centroid from audio samples.
    ///
    /// The spectral centroid is the weighted average of frequencies:
    /// `Σ(freq_i × magnitude_i) / Σ(magnitude_i)`
    ///
    /// - Parameters:
    ///   - samples: Audio PCM samples (Float)
    ///   - sampleRate: Sample rate in Hz
    /// - Returns: Spectral centroid in Hz, or 0 if insufficient data
    static func spectralCentroid(samples: [Float], sampleRate: Double) -> Float {
        guard samples.count >= minimumSamples else { return 0 }

        // Use power-of-2 length for FFT efficiency
        let fftLength = 1 << Int(floor(log2(Double(samples.count))))
        let log2n = vDSP_Length(log2(Double(fftLength)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return 0
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfN = fftLength / 2

        // Apply Hann window to reduce spectral leakage
        var windowedSamples = [Float](repeating: 0, count: fftLength)
        var window = [Float](repeating: 0, count: fftLength)
        vDSP_hann_window(&window, vDSP_Length(fftLength), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftLength))

        // Pack into split complex format for real FFT
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        for i in 0..<fftLength {
            if i % 2 == 0 {
                realPart[i / 2] = windowedSamples[i]
            } else {
                imagPart[i / 2] = windowedSamples[i]
            }
        }

        // Perform FFT and spectral centroid using withUnsafeMutableBufferPointer
        // to satisfy Swift's pointer lifetime requirements
        let centroid: Float = realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitude spectrum
                var magnitudes = [Float](repeating: 0, count: halfN)
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                // Compute spectral centroid: Σ(freq * mag) / Σ(mag)
                let frequencyResolution = Float(sampleRate) / Float(fftLength)
                var weightedSum: Float = 0
                var magnitudeSum: Float = 0

                for i in 1..<halfN { // Skip DC bin (i=0)
                    let frequency = Float(i) * frequencyResolution
                    weightedSum += frequency * magnitudes[i]
                    magnitudeSum += magnitudes[i]
                }

                guard magnitudeSum > 0 else { return Float(0) }
                return weightedSum / magnitudeSum
            }
        }

        return centroid
    }
}
