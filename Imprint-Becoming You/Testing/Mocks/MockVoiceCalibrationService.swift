//
//  MockVoiceCalibrationService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - Mock Voice Calibration Service

/// Test double for `VoiceCalibrationServiceProtocol`.
///
/// Records method calls and provides configurable behavior for unit tests.
/// Returns stub calibration data by default.
///
/// ## Usage
/// ```swift
/// let mock = MockVoiceCalibrationService()
/// let data = try await mock.performCalibration(
///     with: ["I am confident", "I am worthy"]
/// )
/// XCTAssertEqual(mock.performCalibrationCallCount, 1)
/// ```
@MainActor
final class MockVoiceCalibrationService: VoiceCalibrationServiceProtocol {

    // MARK: - Call Tracking

    /// Number of times `performCalibration(with:)` was called
    private(set) var performCalibrationCallCount: Int = 0

    /// Last phrases passed to `performCalibration(with:)`
    private(set) var lastCalibrationPhrases: [String]?

    /// Number of times `cancelCalibration()` was called
    private(set) var cancelCalibrationCallCount: Int = 0

    // MARK: - Stubs

    /// Stub return value for `performCalibration(with:)`
    var stubCalibrationData: CalibrationData = CalibrationData(
        baselineRMS: 0.15,
        pitchMin: 100,
        pitchMax: 300,
        volumeMin: -40,
        volumeMax: -10
    )

    /// Error to throw from `performCalibration(with:)` (nil = success)
    var stubError: Error?

    /// Stub value for `isCalibrating`
    var stubIsCalibrating: Bool = false

    /// Stub value for `progress`
    var stubProgress: Float = 0

    /// Stub value for `currentPhraseIndex`
    var stubCurrentPhraseIndex: Int = 0

    /// Stub value for `totalPhrases`
    var stubTotalPhrases: Int = 0

    // MARK: - VoiceCalibrationServiceProtocol

    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        performCalibrationCallCount += 1
        lastCalibrationPhrases = sampleAffirmations
        if let error = stubError { throw error }
        return stubCalibrationData
    }

    func cancelCalibration() {
        cancelCalibrationCallCount += 1
        stubIsCalibrating = false
    }

    var isCalibrating: Bool { stubIsCalibrating }
    var progress: Float { stubProgress }
    var currentPhraseIndex: Int { stubCurrentPhraseIndex }
    var totalPhrases: Int { stubTotalPhrases }

    /// Stream of calibration progress updates (empty by default)
    private(set) lazy var progressStream: AsyncStream<CalibrationProgress> = {
        AsyncStream { continuation in
            continuation.finish()
        }
    }()

    // MARK: - Reset

    /// Resets all tracked calls and stubs to defaults.
    func reset() {
        performCalibrationCallCount = 0
        lastCalibrationPhrases = nil
        cancelCalibrationCallCount = 0
        stubError = nil
        stubIsCalibrating = false
        stubProgress = 0
        stubCurrentPhraseIndex = 0
        stubTotalPhrases = 0
    }
}
