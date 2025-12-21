//
//  AudioServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation

// MARK: - Audio Service Protocol

/// Protocol defining audio playback and binaural beat generation capabilities.
///
/// Implementations must handle:
/// - AVAudioEngine management
/// - Binaural beat generation
/// - Audio file playback
/// - Audio session interruption handling
protocol AudioServiceProtocol: AnyObject, Sendable {
    
    // MARK: - Engine State
    
    /// Whether the audio engine is currently running
    var isRunning: Bool { get }
    
    /// Current binaural preset (or nil if disabled)
    var currentBinauralPreset: BinauralPreset? { get }
    
    // MARK: - Engine Control
    
    /// Starts the audio engine
    /// - Throws: `AppError.audioEngineInitializationFailed` if engine fails to start
    func start() async throws
    
    /// Stops the audio engine
    func stop() async
    
    // MARK: - Binaural Beats
    
    /// Starts playing binaural beats with the specified preset
    /// - Parameter preset: The binaural preset to use
    /// - Throws: `AppError.binauralGenerationFailed` if beats cannot be generated
    func startBinauralBeats(preset: BinauralPreset) async throws
    
    /// Stops binaural beat playback
    func stopBinauralBeats() async
    
    /// Changes the binaural preset without stopping playback
    /// - Parameter preset: The new preset to use
    func changeBinauralPreset(_ preset: BinauralPreset) async
    
    // MARK: - Audio Playback
    
    /// Plays an audio file from the cache
    /// - Parameter fileName: Name of the cached audio file
    /// - Throws: `AppError.audioPlaybackFailed` if file cannot be played
    func playAudioFile(named fileName: String) async throws
    
    /// Plays audio data directly
    /// - Parameter data: Audio data to play
    /// - Throws: `AppError.audioPlaybackFailed` if data cannot be played
    func playAudioData(_ data: Data) async throws
    
    /// Stops current audio playback
    func stopPlayback() async
    
    /// Pauses current audio playback
    func pausePlayback() async
    
    /// Resumes paused audio playback
    func resumePlayback() async
    
    // MARK: - Volume Control
    
    /// Current playback volume (0.0 - 1.0)
    var playbackVolume: Float { get }
    
    /// Sets the playback volume
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setPlaybackVolume(_ volume: Float) async
    
    /// Current binaural beats volume (0.0 - 1.0)
    var binauralVolume: Float { get }
    
    /// Sets the binaural beats volume
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setBinauralVolume(_ volume: Float) async
}

// MARK: - Audio Playback Delegate

/// Delegate for receiving audio playback events
protocol AudioPlaybackDelegate: AnyObject {
    /// Called when playback completes
    func audioPlaybackDidComplete()
    
    /// Called when playback is interrupted (e.g., phone call)
    func audioPlaybackWasInterrupted()
    
    /// Called when playback can resume after interruption
    func audioPlaybackCanResume()
    
    /// Called when an error occurs during playback
    func audioPlaybackDidFail(with error: AppError)
}

// MARK: - Mock Implementation

/// Mock audio service for previews and testing
final class MockAudioService: AudioServiceProtocol, @unchecked Sendable {
    var isRunning: Bool = false
    var currentBinauralPreset: BinauralPreset?
    var playbackVolume: Float = 1.0
    var binauralVolume: Float = Constants.Audio.binauralVolume
    
    func start() async throws {
        isRunning = true
    }
    
    func stop() async {
        isRunning = false
    }
    
    func startBinauralBeats(preset: BinauralPreset) async throws {
        currentBinauralPreset = preset
    }
    
    func stopBinauralBeats() async {
        currentBinauralPreset = nil
    }
    
    func changeBinauralPreset(_ preset: BinauralPreset) async {
        currentBinauralPreset = preset
    }
    
    func playAudioFile(named fileName: String) async throws {
        // Simulate playback delay
        try await Task.sleep(for: .seconds(1))
    }
    
    func playAudioData(_ data: Data) async throws {
        try await Task.sleep(for: .seconds(1))
    }
    
    func stopPlayback() async {}
    func pausePlayback() async {}
    func resumePlayback() async {}
    
    func setPlaybackVolume(_ volume: Float) async {
        playbackVolume = volume
    }
    
    func setBinauralVolume(_ volume: Float) async {
        binauralVolume = volume
    }
}

// MARK: - Placeholder Implementation

/// Placeholder implementation until real service is built
final class AudioService: AudioServiceProtocol, @unchecked Sendable {
    var isRunning: Bool = false
    var currentBinauralPreset: BinauralPreset?
    var playbackVolume: Float = 1.0
    var binauralVolume: Float = Constants.Audio.binauralVolume
    
    func start() async throws {
        // TODO: Implement AVAudioEngine setup in Phase 1
        isRunning = true
    }
    
    func stop() async {
        isRunning = false
    }
    
    func startBinauralBeats(preset: BinauralPreset) async throws {
        currentBinauralPreset = preset
    }
    
    func stopBinauralBeats() async {
        currentBinauralPreset = nil
    }
    
    func changeBinauralPreset(_ preset: BinauralPreset) async {
        currentBinauralPreset = preset
    }
    
    func playAudioFile(named fileName: String) async throws {
        // TODO: Implement in Phase 1
    }
    
    func playAudioData(_ data: Data) async throws {
        // TODO: Implement in Phase 1
    }
    
    func stopPlayback() async {}
    func pausePlayback() async {}
    func resumePlayback() async {}
    
    func setPlaybackVolume(_ volume: Float) async {
        playbackVolume = volume
    }
    
    func setBinauralVolume(_ volume: Float) async {
        binauralVolume = volume
    }
}
