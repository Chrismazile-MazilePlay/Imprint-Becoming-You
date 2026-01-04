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
final class MockAudioService: AudioServiceProtocol, @unchecked Sendable {
    
    // MARK: - State
    
    var isRunning: Bool = false
    var currentBinauralPreset: BinauralPreset?
    var playbackVolume: Float = 1.0
    var binauralVolume: Float = Constants.Audio.binauralVolume
    
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
        currentBinauralPreset = nil
    }
    
    // MARK: - AudioServiceProtocol - Binaural Beats
    
    func startBinauralBeats(preset: BinauralPreset) async throws {
        if shouldSimulateError {
            throw AppError.binauralGenerationFailed(reason: "Simulated error")
        }
        currentBinauralPreset = preset
    }
    
    func stopBinauralBeats() async {
        currentBinauralPreset = nil
    }
    
    func changeBinauralPreset(_ preset: BinauralPreset) async {
        currentBinauralPreset = preset
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
    
    func setBinauralVolume(_ volume: Float) async {
        binauralVolume = max(0, min(1, volume))
    }
}
