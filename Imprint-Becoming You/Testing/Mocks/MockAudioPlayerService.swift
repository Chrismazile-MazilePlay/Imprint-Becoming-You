//
//  MockAudioPlayerService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/6/26.
//

import Foundation

// MARK: - Mock Audio Player Service

/// Test double for `AudioPlayerServiceProtocol`.
///
/// Records method calls and provides configurable behavior for unit tests.
/// All methods are synchronous no-ops by default — override properties
/// to simulate specific playback states.
///
/// ## Usage
/// ```swift
/// let mock = MockAudioPlayerService()
/// mock.stubIsPlaying = true
/// mock.stubDuration = 3.5
///
/// let coordinator = SessionPlaybackCoordinator(
///     queueService: mockQueue,
///     audioPlayerService: mock,
///     ttsService: mockTTS
/// )
/// ```
@MainActor
final class MockAudioPlayerService: AudioPlayerServiceProtocol, @unchecked Sendable {

    // MARK: - Call Tracking

    /// Last data passed to `playRawPCMData(_:sampleRate:)`
    private(set) var lastPlayedPCMData: Data?

    /// Last sample rate passed to `playRawPCMData(_:sampleRate:)`
    private(set) var lastPlayedSampleRate: Double?

    /// Last data passed to `playData(_:)`
    private(set) var lastPlayedData: Data?

    /// Number of times `immediateStop()` was called
    private(set) var immediateStopCallCount: Int = 0

    /// Number of times `cancelAndStop()` was called
    private(set) var cancelAndStopCallCount: Int = 0

    /// Number of times `stop()` was called
    private(set) var stopCallCount: Int = 0

    /// Number of times `pause()` was called
    private(set) var pauseCallCount: Int = 0

    /// Number of times `resume()` was called
    private(set) var resumeCallCount: Int = 0

    /// Last volume set via `setVolume(_:)`
    private(set) var lastSetVolume: Float?

    // MARK: - Stubs

    /// Stub value for `isPlaying`
    var stubIsPlaying: Bool = false

    /// Stub value for `isPaused`
    var stubIsPaused: Bool = false

    /// Stub value for `currentTime`
    var stubCurrentTime: TimeInterval = 0

    /// Stub value for `duration`
    var stubDuration: TimeInterval = 0

    /// Stub value for `progress`
    var stubProgress: Double = 0

    /// Error to throw from playback methods (nil = success)
    var stubError: Error?

    // MARK: - AudioPlayerServiceProtocol

    func playRawPCMData(_ data: Data, sampleRate: Double) async throws {
        lastPlayedPCMData = data
        lastPlayedSampleRate = sampleRate
        if let error = stubError { throw error }
    }

    func playData(_ data: Data) async throws {
        lastPlayedData = data
        if let error = stubError { throw error }
    }

    nonisolated func immediateStop() {
        // Track on MainActor since this is a mock
        Task { @MainActor in
            self.immediateStopCallCount += 1
        }
    }

    func cancelAndStop() {
        cancelAndStopCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }

    func setVolume(_ newVolume: Float) {
        lastSetVolume = newVolume
    }

    var isPlaying: Bool { stubIsPlaying }
    var isPaused: Bool { stubIsPaused }
    var currentTime: TimeInterval { stubCurrentTime }
    var duration: TimeInterval { stubDuration }
    var progress: Double { stubProgress }

    // MARK: - Reset

    /// Resets all tracked calls and stubs to defaults.
    func reset() {
        lastPlayedPCMData = nil
        lastPlayedSampleRate = nil
        lastPlayedData = nil
        immediateStopCallCount = 0
        cancelAndStopCallCount = 0
        stopCallCount = 0
        pauseCallCount = 0
        resumeCallCount = 0
        lastSetVolume = nil
        stubIsPlaying = false
        stubIsPaused = false
        stubCurrentTime = 0
        stubDuration = 0
        stubProgress = 0
        stubError = nil
    }
}
