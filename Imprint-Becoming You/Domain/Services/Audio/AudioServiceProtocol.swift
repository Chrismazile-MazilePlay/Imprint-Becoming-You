//
//  AudioServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
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
///
/// ## Usage
/// ```swift
/// let audio: AudioServiceProtocol = AudioService()
///
/// // Start engine and binaural beats
/// try await audio.start()
/// try await audio.startBinauralBeats(preset: .focus)
///
/// // Play TTS audio
/// try await audio.playAudioData(synthesizedData)
///
/// // Adjust volumes
/// await audio.setBinauralVolume(0.2)
/// await audio.setPlaybackVolume(0.8)
/// ```
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

/// Delegate for receiving audio playback events.
///
/// Implement this protocol to receive callbacks about playback state changes,
/// interruptions, and errors.
protocol AudioPlaybackDelegate: AnyObject, Sendable {
    /// Called when playback completes successfully
    func audioPlaybackDidComplete()
    
    /// Called when playback is interrupted (e.g., phone call, alarm)
    func audioPlaybackWasInterrupted()
    
    /// Called when playback can resume after interruption
    func audioPlaybackCanResume()
    
    /// Called when an error occurs during playback
    /// - Parameter error: The error that occurred
    func audioPlaybackDidFail(with error: AppError)
}

// MARK: - Default Delegate Implementation

extension AudioPlaybackDelegate {
    func audioPlaybackDidComplete() {}
    func audioPlaybackWasInterrupted() {}
    func audioPlaybackCanResume() {}
    func audioPlaybackDidFail(with error: AppError) {}
}
