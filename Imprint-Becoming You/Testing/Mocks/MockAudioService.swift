//
//  MockAudioService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import AVFoundation

// MARK: - MockAudioService

/// Mock implementation of `AudioServiceProtocol` for previews and testing.
///
/// Simulates audio engine operations without actual audio output.
/// Uses `@MainActor` isolation consistent with the protocol.
@MainActor
final class MockAudioService: AudioServiceProtocol {

    // MARK: - State

    var isRunning: Bool = false
    var playbackVolume: Float = 1.0

    /// Mock audio player service for testing.
    var audioPlayerService: any AudioPlayerServiceProtocol = MockAudioPlayerService()

    /// Mock session controller for testing.
    let sessionController: any AudioSessionControllerProtocol = MockAudioSessionController()

    // MARK: - Background Music State

    private(set) var isBackgroundMusicPlaying: Bool = false
    private(set) var currentMusicCategory: MusicCategory?
    private(set) var musicPlaybackMode: MusicPlaybackMode = .repeatTrack
    private(set) var currentMusicTrackIndex: Int = 0
    var currentMusicTrackCount: Int { currentMusicCategory?.trackCount ?? 0 }

    // MARK: - Configuration

    /// Simulated playback delay.
    var playbackDelay: Duration = .seconds(1)

    /// Whether to simulate errors.
    var shouldSimulateError: Bool = false

    // MARK: - Engine Control

    func start() async throws {
        if shouldSimulateError {
            throw AppError.audioEngineInitializationFailed(reason: "Simulated error")
        }
        isRunning = true
    }

    func stop() async {
        isRunning = false
        currentMusicCategory = nil
        isBackgroundMusicPlaying = false
    }

    // MARK: - Background Music

    func playBackgroundMusic(category: MusicCategory) async {
        currentMusicCategory = category
        isBackgroundMusicPlaying = true
    }

    func stopBackgroundMusic() {
        currentMusicCategory = nil
        isBackgroundMusicPlaying = false
    }

    func pauseBackgroundMusic() {
        isBackgroundMusicPlaying = false
    }

    func resumeBackgroundMusic() {
        if currentMusicCategory != nil {
            isBackgroundMusicPlaying = true
        }
    }

    func setBackgroundMusicVolume(_ volume: Float) {
        // No-op for mock
    }

    func skipBackgroundMusicForward() {
        guard let category = currentMusicCategory else { return }
        currentMusicTrackIndex = (currentMusicTrackIndex + 1) % category.trackCount
    }

    func skipBackgroundMusicBackward() {
        guard let category = currentMusicCategory else { return }
        currentMusicTrackIndex = (currentMusicTrackIndex - 1 + category.trackCount) % category.trackCount
    }

    func setBackgroundMusicPlaybackMode(_ mode: MusicPlaybackMode) {
        musicPlaybackMode = mode
    }

    // MARK: - Audio Playback

    func playAudioFile(named fileName: String) async throws {
        if shouldSimulateError {
            throw AppError.audioPlaybackFailed(reason: "Simulated error")
        }
        try await Task.sleep(for: playbackDelay)
    }

    func playAudioData(_ data: Data) async throws {
        if shouldSimulateError {
            throw AppError.audioPlaybackFailed(reason: "Simulated error")
        }
        try await Task.sleep(for: playbackDelay)
    }

    func stopPlayback() async {
        // No-op for mock
    }

    func pausePlayback() async {
        // No-op for mock
    }

    func resumePlayback() async {
        // No-op for mock
    }

    // MARK: - Volume Control

    func setPlaybackVolume(_ volume: Float) async {
        playbackVolume = max(0, min(1, volume))
    }
}
