//
//  VoiceCalibrationServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - Voice Calibration Service Protocol

/// Consumer-facing interface for voice calibration during onboarding.
///
/// Extracts the calibration surface area used by `OnboardingViewModel`
/// from the concrete `VoiceCalibrationService`, enabling mock injection
/// for tests.
///
/// ## Responsibilities
/// - Voice calibration with sample affirmations
/// - Progress tracking via `progressStream`
/// - Calibration cancellation
///
/// ## Architecture
/// ```
/// VoiceCalibrationServiceProtocol
/// ├── VoiceCalibrationService (Production)
/// └── MockVoiceCalibrationService (Testing)
/// ```
///
/// ## Note on Static Properties
/// `defaultCalibrationPhrases` and `quickCalibrationPhrases` remain on
/// the concrete `VoiceCalibrationService` class as static properties.
/// They are compile-time constants, not instance behavior, and consumers
/// can reference them directly.
///
/// ## Note on Nested Types
/// `CalibrationProgress` and `CalibrationState` are already top-level
/// types defined alongside `VoiceCalibrationService`, so no extraction
/// is needed.
@MainActor
protocol VoiceCalibrationServiceProtocol: AnyObject {

    /// Performs voice calibration with sample affirmations.
    ///
    /// Captures audio for each phrase, measures voice characteristics
    /// (RMS, pitch, volume), and returns computed calibration data.
    ///
    /// - Parameter sampleAffirmations: Texts for user to read during calibration
    /// - Returns: Computed calibration data for resonance scoring
    /// - Throws: `AppError.calibrationFailed` if calibration fails
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData

    /// Cancels an in-progress calibration.
    ///
    /// Stops audio capture, emits a cancelled state on the progress stream,
    /// and resets internal state.
    func cancelCalibration()

    /// Whether calibration is currently in progress.
    var isCalibrating: Bool { get }

    /// Current calibration progress (0.0 - 1.0).
    var progress: Float { get }

    /// Index of the current phrase being calibrated (0-based).
    var currentPhraseIndex: Int { get }

    /// Total number of phrases to calibrate.
    var totalPhrases: Int { get }

    /// Stream of calibration progress updates.
    var progressStream: AsyncStream<CalibrationProgress> { get }
}
