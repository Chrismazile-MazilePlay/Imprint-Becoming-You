//
//  AudioServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Audio Service Protocol

/// Protocol defining audio playback and background music capabilities.
///
/// All methods are `@MainActor` isolated because:
/// 1. Audio playback callbacks affect UI state
/// 2. Background music controls are driven by user interaction
/// 3. Interruption handling updates UI
///
/// Implementations must handle:
/// - AVAudioEngine management
/// - Background music playback
/// - Audio file playback
/// - Audio session interruption handling
///
/// ## Unified Engine Architecture
/// All audio (background music AND TTS) routes through a single `AVAudioEngine`.
/// The `audioPlayerService` property exposes the engine-attached player so that
/// consumers (SessionPlaybackCoordinator, VoiceSettingsView, etc.) play TTS
/// through the same render client as background music — eliminating the
/// dual-render-client HAL contention that causes static/glitch.
///
/// ## Usage
/// ```swift
/// let audio: AudioServiceProtocol = AudioService()
///
/// // Start engine and background music
/// try await audio.start()
/// audio.playBackgroundMusic(category: .focus)
///
/// // Play TTS through the unified engine
/// try await audio.audioPlayerService.playRawPCMData(data, sampleRate: 24000)
///
/// // Adjust volumes
/// audio.setBackgroundMusicVolume(0.2)
/// await audio.setPlaybackVolume(0.8)
/// ```
@MainActor
protocol AudioServiceProtocol: AnyObject {

    // MARK: - Engine State

    /// Whether the audio engine is currently running
    var isRunning: Bool { get }

    /// The engine-attached audio player for TTS playback.
    ///
    /// This is the **same** player node that is connected to the shared
    /// `AVAudioEngine`. Consumers must use this instance (not create
    /// standalone players) to ensure all audio routes through one engine.
    var audioPlayerService: any AudioPlayerServiceProtocol { get }

    // MARK: - Engine Control

    /// Starts the audio engine
    /// - Throws: `AppError.audioEngineInitializationFailed` if engine fails to start
    func start() async throws

    /// Stops the audio engine
    func stop() async

    // MARK: - Background Music

    /// Whether background music is currently playing
    var isBackgroundMusicPlaying: Bool { get }

    /// The currently playing music category (`nil` if stopped)
    var currentMusicCategory: MusicCategory? { get }

    /// Starts playing background music from the specified category.
    ///
    /// Ensures the audio engine is running before playback begins.
    /// - Parameter category: The music category to play
    func playBackgroundMusic(category: MusicCategory) async

    /// Stops background music playback
    func stopBackgroundMusic()

    /// Pauses background music (retains position for resume)
    func pauseBackgroundMusic()

    /// Resumes paused background music
    func resumeBackgroundMusic()

    /// Sets the background music volume
    /// - Parameter volume: Volume level (0.0–1.0)
    func setBackgroundMusicVolume(_ volume: Float)

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
}

// MARK: - Audio Playback Delegate

/// Delegate for receiving audio playback events.
///
/// All methods are `@MainActor` isolated since playback events
/// typically trigger UI updates.
///
/// Implement this protocol to receive callbacks about playback state changes,
/// interruptions, and errors.
@MainActor
protocol AudioPlaybackDelegate: AnyObject {
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
