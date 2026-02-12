//
//  VoiceAnalyticsSummary.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/11/26.
//

import Foundation

// MARK: - Voice Analytics Summary

/// Accumulated voice analytics data from `SFVoiceAnalytics`.
///
/// Holds per-frame pitch, jitter, shimmer, and voicing values extracted
/// from `SFTranscriptionSegment.voiceAnalytics` during speech recognition.
/// Rebuilt from scratch on each recognition callback because
/// `SFSpeechRecognitionResult.bestTranscription.segments` provides
/// the **full** segment list (cumulative), not incremental deltas.
///
/// ## Metrics
/// - **Pitch**: Fundamental frequency (Hz) per frame
/// - **Jitter**: Frame-to-frame pitch variation (%), measures vocal control
/// - **Shimmer**: Frame-to-frame amplitude variation (dB), measures breath support
/// - **Voicing**: Ratio of voiced frames, measures speaking clarity
///
/// ## Usage
/// ```swift
/// var summary = VoiceAnalyticsSummary()
/// summary.accumulate(pitch: [180, 185], jitter: [1.2, 1.5],
///                    shimmer: [0.8, 0.9], voicing: [0.9, 0.85])
/// print(summary.pitchCV)     // Coefficient of variation
/// print(summary.meanJitter)  // Average jitter percentage
/// ```
struct VoiceAnalyticsSummary: Sendable, Equatable {

    // MARK: - Stored Properties

    /// Accumulated pitch values (Hz) across all segments
    private(set) var pitchValues: [Float] = []

    /// Accumulated jitter values (%) across all segments
    private(set) var jitterValues: [Float] = []

    /// Accumulated shimmer values (dB) across all segments
    private(set) var shimmerValues: [Float] = []

    /// Accumulated voicing values (0.0-1.0) across all segments
    private(set) var voicingValues: [Float] = []

    /// Number of transcription segments processed
    private(set) var segmentCount: Int = 0

    // MARK: - Accumulation

    /// Replaces all accumulated data with new values from recognition segments.
    ///
    /// Called on every recognition callback with data from **all** segments
    /// in `bestTranscription.segments`. This is a full replacement (not append)
    /// because Apple provides cumulative segment arrays.
    ///
    /// - Parameters:
    ///   - pitch: Pitch frame values (Hz) from all segments
    ///   - jitter: Jitter frame values (%) from all segments
    ///   - shimmer: Shimmer frame values (dB) from all segments
    ///   - voicing: Voicing frame values (0.0-1.0) from all segments
    ///   - segments: Total number of segments processed
    mutating func rebuild(
        pitch: [Float],
        jitter: [Float],
        shimmer: [Float],
        voicing: [Float],
        segments: Int
    ) {
        pitchValues = pitch
        jitterValues = jitter
        shimmerValues = shimmer
        voicingValues = voicing
        segmentCount = segments
    }

    // MARK: - Computed Statistics

    /// Whether enough data has been collected for meaningful scoring.
    ///
    /// Requires at least 5 pitch frames and 5 voicing frames to avoid
    /// noise-dominated scores from very short utterances.
    var hasEnoughData: Bool {
        pitchValues.count >= 5 && voicingValues.count >= 5
    }

    /// Average jitter across all frames (%).
    ///
    /// Normal conversational speech: 0.5–3%.
    /// Lower values indicate more controlled, steady voicing.
    var meanJitter: Float {
        guard !jitterValues.isEmpty else { return 0 }
        return jitterValues.reduce(0, +) / Float(jitterValues.count)
    }

    /// Average shimmer across all frames (dB).
    ///
    /// Normal conversational speech: 0.5–2.0 dB.
    /// Lower values indicate better breath support and vocal control.
    var meanShimmer: Float {
        guard !shimmerValues.isEmpty else { return 0 }
        return shimmerValues.reduce(0, +) / Float(shimmerValues.count)
    }

    /// Average voicing ratio across all frames (0.0–1.0).
    ///
    /// Higher values indicate more clearly articulated speech
    /// with less breathy or whispered content.
    var meanVoicing: Float {
        guard !voicingValues.isEmpty else { return 0 }
        return voicingValues.reduce(0, +) / Float(voicingValues.count)
    }

    /// Coefficient of variation of pitch (stdDev / mean).
    ///
    /// Measures vocal expressiveness:
    /// - Very low (< 0.05): Monotone, flat delivery
    /// - Optimal (0.08–0.25): Natural, expressive speech
    /// - High (> 0.35): Erratic, unstable pitch
    var pitchCV: Float {
        guard pitchValues.count >= 2 else { return 0 }

        let mean = pitchValues.reduce(0, +) / Float(pitchValues.count)
        guard mean > 0 else { return 0 }

        let variance = pitchValues.reduce(Float(0)) { sum, value in
            let diff = value - mean
            return sum + diff * diff
        } / Float(pitchValues.count)

        let stdDev = sqrt(variance)
        return stdDev / mean
    }
}
