//
//  VoiceAnalyticsScoreCalculator.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/11/26.
//

import Foundation

// MARK: - Voice Analytics Score Calculator

/// Computes resonance scores from `VoiceAnalyticsSummary` data.
///
/// Stateless calculator that produces a `ScoreResult` from Apple's
/// `SFVoiceAnalytics` metrics. Pure arithmetic, synchronous, < 1ms.
///
/// ## Scoring Model (4 Components)
///
/// | Component | Weight | Source | What It Captures |
/// |-----------|--------|--------|-----------------|
/// | Text Accuracy | 15% | `TextAccuracyCalculator` | Did you say the right words? |
/// | Vocal Steadiness | 35% | Jitter + Shimmer | Confident, controlled voice |
/// | Pitch Expression | 25% | Pitch CV | Expressive delivery |
/// | Speaking Clarity | 25% | Voicing ratio | Clear articulation |
///
/// ## Thresholds
/// Based on speech science literature for conversational speech:
/// - **Jitter**: Normal 0.5–4% (Teixeira & Fernandes, 2014)
/// - **Shimmer**: Normal 0.3–2.5 dB (Farrús et al., 2007)
/// - **Pitch CV**: Optimal 0.08–0.25 for expressive speech
/// - **Voicing**: 30–85% for clear articulation
///
/// ## Fallback Behavior
/// When `VoiceAnalyticsSummary.hasEnoughData` is `false` (very short
/// utterances, < 5 frames), all components default to the text accuracy
/// value. This preserves scoring continuity for one-word affirmations.
///
/// ## Usage
/// ```swift
/// let result = VoiceAnalyticsScoreCalculator.computeScore(
///     textAccuracy: 0.92,
///     voiceAnalytics: summary,
///     duration: 3.5,
///     mode: .readThenSpeak,
///     recognizedText: "I am confident"
/// )
/// ```
enum VoiceAnalyticsScoreCalculator {

    // MARK: - Public API

    /// Computes a resonance score from text accuracy and voice analytics.
    ///
    /// - Parameters:
    ///   - textAccuracy: Text matching score (0.0–1.0) from `TextAccuracyCalculator`
    ///   - voiceAnalytics: Accumulated voice analytics from speech recognition
    ///   - duration: Duration of the spoken affirmation (seconds)
    ///   - mode: Session mode used during recording
    ///   - recognizedText: Final recognized text from speech recognition
    /// - Returns: Complete `ScoreResult` ready for persistence and display
    static func computeScore(
        textAccuracy: Float,
        voiceAnalytics: VoiceAnalyticsSummary,
        duration: TimeInterval,
        mode: SessionMode,
        recognizedText: String
    ) -> ScoreResult {

        let vocalSteadiness: Double
        let pitchExpression: Double
        let speakingClarity: Double

        if voiceAnalytics.hasEnoughData {
            vocalSteadiness = computeVocalSteadiness(
                jitter: voiceAnalytics.meanJitter,
                shimmer: voiceAnalytics.meanShimmer
            )
            pitchExpression = computePitchExpression(pitchCV: voiceAnalytics.pitchCV)
            speakingClarity = computeSpeakingClarity(voicingRatio: voiceAnalytics.meanVoicing)
        } else {
            // Fallback: not enough voice data, use text accuracy for all components
            let fallback = Double(textAccuracy)
            vocalSteadiness = fallback
            pitchExpression = fallback
            speakingClarity = fallback

            AppLogger.debug(
                "Voice analytics fallback (insufficient data)",
                category: .practice,
                context: [
                    "pitchFrames": voiceAnalytics.pitchValues.count,
                    "voicingFrames": voiceAnalytics.voicingValues.count
                ]
            )
        }

        // Weighted composite score
        let textWeight = Double(Constants.ResonanceScoring.textAccuracyWeight)
        let steadinessWeight = Double(Constants.ResonanceScoring.vocalSteadinessWeight)
        let expressionWeight = Double(Constants.ResonanceScoring.pitchExpressionWeight)
        let clarityWeight = Double(Constants.ResonanceScoring.speakingClarityWeight)

        let compositeScore =
            (Double(textAccuracy) * textWeight) +
            (vocalSteadiness * steadinessWeight) +
            (pitchExpression * expressionWeight) +
            (speakingClarity * clarityWeight)

        // Store in existing fields (no SwiftData migration needed):
        // - vocalEnergy → Vocal Steadiness
        // - pitchStability → Pitch Expression
        // - Speaking Clarity folds into composite score only
        let components = ScoreComponents(
            textAccuracy: Double(textAccuracy),
            vocalEnergy: vocalSteadiness,
            pitchStability: pitchExpression
        )

        AppLogger.debug(
            "Score calculated",
            category: .practice,
            context: [
                "hasVoiceAnalytics": voiceAnalytics.hasEnoughData,
                "textAccuracy": Int(textAccuracy * 100),
                "vocalSteadiness": Int(vocalSteadiness * 100),
                "pitchExpression": Int(pitchExpression * 100),
                "speakingClarity": Int(speakingClarity * 100),
                "composite": Int(compositeScore * 100)
            ]
        )

        return ScoreResult(
            score: compositeScore,
            components: components,
            duration: duration,
            mode: mode,
            recognizedText: recognizedText
        )
    }

    // MARK: - Component Calculations

    /// Computes Vocal Steadiness score from jitter and shimmer.
    ///
    /// Measures vocal control and confidence. Low jitter and shimmer
    /// indicate steady, well-supported voice production.
    ///
    /// - Parameters:
    ///   - jitter: Mean jitter percentage (0.5–4% normal range)
    ///   - shimmer: Mean shimmer in dB (0.3–2.5 dB normal range)
    /// - Returns: Score (0.0–1.0), higher = steadier voice
    private static func computeVocalSteadiness(jitter: Float, shimmer: Float) -> Double {
        // Jitter scoring: lower is better (more controlled)
        // 0.5% = excellent control, 4.0% = upper bound of normal speech
        let jitterScore = clampedLinear(
            value: Double(jitter),
            bestValue: 0.5,
            worstValue: 4.0
        )

        // Shimmer scoring: lower is better (better breath support)
        // 0.3 dB = excellent, 2.5 dB = upper bound of normal speech
        let shimmerScore = clampedLinear(
            value: Double(shimmer),
            bestValue: 0.3,
            worstValue: 2.5
        )

        // Equal weight: both contribute to overall steadiness
        return (jitterScore + shimmerScore) / 2.0
    }

    /// Computes Pitch Expression score from pitch coefficient of variation.
    ///
    /// Measures vocal expressiveness. The scoring function is a bell curve:
    /// too monotone (low CV) and too erratic (high CV) both score low.
    ///
    /// - Parameter pitchCV: Coefficient of variation of pitch
    /// - Returns: Score (0.0–1.0), higher = more naturally expressive
    private static func computePitchExpression(pitchCV: Float) -> Double {
        let cv = Double(pitchCV)

        // Optimal range: 0.08–0.25 (natural, expressive speech)
        // Below 0.05: monotone (boring, disengaged)
        // Above 0.45: erratic (unstable, anxious)
        let optimalLow = 0.08
        let optimalHigh = 0.25
        let monotoneFloor = 0.05
        let erraticCeiling = 0.45

        if cv >= optimalLow && cv <= optimalHigh {
            // In the optimal range — full score
            return 1.0
        } else if cv < optimalLow {
            // Too monotone — penalize linearly toward floor
            return clampedLinear(
                value: monotoneFloor,
                bestValue: cv,
                worstValue: monotoneFloor
            )
        } else {
            // Too erratic — penalize linearly toward ceiling
            return clampedLinear(
                value: cv,
                bestValue: optimalHigh,
                worstValue: erraticCeiling
            )
        }
    }

    /// Computes Speaking Clarity score from voicing ratio.
    ///
    /// Measures how clearly the user articulated. Higher voicing ratio
    /// indicates less mumbling, whispering, or breathy speech.
    ///
    /// - Parameter voicingRatio: Mean voicing ratio (0.0–1.0)
    /// - Returns: Score (0.0–1.0), higher = clearer articulation
    private static func computeSpeakingClarity(voicingRatio: Float) -> Double {
        // Voicing scoring: higher is better (clearer articulation)
        // 30% = mumbling/whispering threshold
        // 85% = clearly articulated speech
        return clampedLinear(
            value: Double(voicingRatio),
            bestValue: 0.85,
            worstValue: 0.30
        )
    }

    // MARK: - Utility

    /// Linear interpolation between best and worst values, clamped to 0.0–1.0.
    ///
    /// Returns 1.0 when `value` equals or exceeds `bestValue`,
    /// 0.0 when `value` equals or falls below `worstValue`,
    /// and linearly interpolates between.
    ///
    /// - Parameters:
    ///   - value: The measured value
    ///   - bestValue: Value that produces score 1.0
    ///   - worstValue: Value that produces score 0.0
    /// - Returns: Clamped score (0.0–1.0)
    private static func clampedLinear(value: Double, bestValue: Double, worstValue: Double) -> Double {
        guard bestValue != worstValue else { return 1.0 }

        let score: Double
        if bestValue < worstValue {
            // Lower is better (e.g., jitter, shimmer)
            score = (worstValue - value) / (worstValue - bestValue)
        } else {
            // Higher is better (e.g., voicing ratio)
            score = (value - worstValue) / (bestValue - worstValue)
        }

        return min(1.0, max(0.0, score))
    }
}
