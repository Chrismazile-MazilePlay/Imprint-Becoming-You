//
//  MockAudioService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Audio Service

/// Mock implementation of audio service for previews and testing.
///
/// Simulates audio engine operations without actual audio output.
/// Uses `@MainActor` isolation consistent with the protocol.
@MainActor
final class MockAudioService: AudioServiceProtocol {

    // MARK: - State

    var isRunning: Bool = false
    var playbackVolume: Float = 1.0

    // MARK: - Background Music State

    private(set) var isBackgroundMusicPlaying: Bool = false
    private(set) var currentMusicCategory: MusicCategory?

    // MARK: - Configuration

    /// Simulated playback delay
    var playbackDelay: Duration = .seconds(1)

    /// Whether to simulate errors
    var shouldSimulateError: Bool = false

    // MARK: - AudioServiceProtocol - Engine Control

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

    // MARK: - AudioServiceProtocol - Background Music

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

    // MARK: - AudioServiceProtocol - Playback

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

    // MARK: - AudioServiceProtocol - Volume

    func setPlaybackVolume(_ volume: Float) async {
        playbackVolume = max(0, min(1, volume))
    }
}
