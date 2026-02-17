//
//  AudioServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import AVFoundation

// MARK: - AudioServiceProtocol

/// Consumer-facing interface for the audio facade.
///
/// `AudioService` is a thin facade that owns the playback `AVAudioEngine`
/// and coordinates sub-services (background music, TTS playback).
///
/// All methods are `@MainActor` isolated because:
/// 1. Audio playback state drives UI
/// 2. Background music controls are UI-driven
/// 3. Interruption handling updates UI state
///
/// ## Architecture
/// ```
/// AudioService (thin facade)
/// ├── AudioSessionController (sole AVAudioSession owner)
/// ├── BackgroundMusicService  (looping music via AVAudioPlayerNode)
/// └── AudioPlayerService      (TTS playback via AVAudioPlayerNode)
/// ```
///
/// ## Usage
/// ```swift
/// let audio: AudioServiceProtocol = AudioService()
///
/// // Start engine and background music
/// try await audio.start()
/// audio.playBackgroundMusic(category: .focus)
///
/// // Play TTS through the engine-attached player
/// try await audio.audioPlayerService.playRawPCMData(data, sampleRate: 24000)
/// ```
@MainActor
protocol AudioServiceProtocol: AnyObject {

    // MARK: - Engine State

    /// Whether the audio engine is currently running.
    var isRunning: Bool { get }

    /// The engine-attached audio player for TTS playback.
    ///
    /// This is the **same** player node connected to the shared
    /// `AVAudioEngine`. Consumers must use this instance (not create
    /// standalone players) to ensure all audio routes through one engine.
    var audioPlayerService: any AudioPlayerServiceProtocol { get }

    /// The centralized audio session controller.
    ///
    /// All audio session configuration **must** go through this
    /// controller — no component may call `AVAudioSession.setCategory()`
    /// directly.
    var sessionController: any AudioSessionControllerProtocol { get }

    // MARK: - Engine Control

    /// Configures the audio session, attaches sub-services, and starts the engine.
    ///
    /// - Throws: `AppError.audioSessionConfigurationFailed` or
    ///   `AppError.audioEngineInitializationFailed` if startup fails.
    func start() async throws

    /// Stops the audio engine and deactivates the audio session.
    func stop() async

    // MARK: - Background Music

    /// Whether background music is currently playing.
    var isBackgroundMusicPlaying: Bool { get }

    /// The currently playing music category (`nil` if stopped).
    var currentMusicCategory: MusicCategory? { get }

    /// Starts playing background music from the specified category.
    ///
    /// Ensures the audio engine is running before playback begins.
    /// - Parameter category: The music category to play.
    func playBackgroundMusic(category: MusicCategory) async

    /// Stops background music playback.
    func stopBackgroundMusic()

    /// Pauses background music (retains position for resume).
    func pauseBackgroundMusic()

    /// Resumes paused background music.
    func resumeBackgroundMusic()

    /// Sets the background music volume.
    ///
    /// - Parameter volume: Volume level (0.0–1.0).
    func setBackgroundMusicVolume(_ volume: Float)

    /// The current background music playback mode.
    var musicPlaybackMode: MusicPlaybackMode { get }

    /// The current track index within the active music category.
    var currentMusicTrackIndex: Int { get }

    /// The total number of tracks in the current music category (0 if stopped).
    var currentMusicTrackCount: Int { get }

    /// Skips to the next background music track.
    func skipBackgroundMusicForward()

    /// Skips to the previous background music track.
    func skipBackgroundMusicBackward()

    /// Sets the background music playback mode.
    ///
    /// - Parameter mode: The desired playback mode.
    func setBackgroundMusicPlaybackMode(_ mode: MusicPlaybackMode)

    // MARK: - Audio Playback

    /// Plays an audio file from the cache.
    ///
    /// - Parameter fileName: Name of the cached audio file.
    /// - Throws: `AppError.audioPlaybackFailed` if file cannot be played.
    func playAudioFile(named fileName: String) async throws

    /// Plays audio data directly.
    ///
    /// - Parameter data: Audio data to play.
    /// - Throws: `AppError.audioPlaybackFailed` if data cannot be played.
    func playAudioData(_ data: Data) async throws

    /// Stops current audio playback.
    func stopPlayback() async

    /// Pauses current audio playback.
    func pausePlayback() async

    /// Resumes paused audio playback.
    func resumePlayback() async

    // MARK: - Volume Control

    /// Current playback volume (0.0–1.0).
    var playbackVolume: Float { get }

    /// Sets the playback volume.
    ///
    /// - Parameter volume: Volume level (0.0–1.0).
    func setPlaybackVolume(_ volume: Float) async
}
