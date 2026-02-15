//
//  AudioService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import os.log

// MARK: - Logger

private let audioServiceLog = Logger(subsystem: "com.imprint.audio", category: "AudioService")

// MARK: - AudioService

/// Main audio service that coordinates all audio functionality.
///
/// This service is `@MainActor` isolated because:
/// 1. Audio playback state affects UI
/// 2. Background music controls are UI-driven
/// 3. Session controller callbacks update UI state
///
/// ## Architecture
/// ```
/// AudioService
/// ├── AudioSessionController (sole setCategory() owner)
/// ├── BackgroundMusicService (looping music via AVAudioPlayerNode)
/// ├── AudioPlayerService (TTS file playback via AVAudioPlayerNode)
/// └── AVAudioEngine (single shared engine for all audio)
/// ```
///
/// ## Unified Engine
/// All audio — background music, TTS playback, and microphone capture —
/// routes through a single `AVAudioEngine`. The engine is exposed via
/// `sharedEngine` so `SpeechCaptureService` can install an input tap
/// on the engine's `inputNode`.
///
/// ## Session Management
/// Audio session configuration is centralized in `AudioSessionController`.
/// No component may call `AVAudioSession.setCategory()` directly — all
/// transitions go through `sessionController.transition()`.
///
/// ## Usage
/// ```swift
/// let audio = AudioService()
/// try await audio.start()
/// audio.playBackgroundMusic(category: .focus)
/// try await audio.audioPlayerService.playRawPCMData(data, sampleRate: 24000)
/// ```
@MainActor
final class AudioService: AudioServiceProtocol {

    // MARK: - Properties

    /// The single shared audio engine for all audio operations.
    private let audioEngine: AVAudioEngine

    /// Centralized audio session controller — sole owner of `setCategory()`.
    let sessionController: any AudioSessionControllerProtocol

    /// Background music player (attached to shared engine).
    private let backgroundMusicService: BackgroundMusicService

    /// Audio file player (attached to shared engine).
    private let audioPlayer: AudioPlayerService

    /// Whether the audio engine is running.
    private(set) var isRunning: Bool = false

    /// The engine-attached audio player for TTS playback.
    ///
    /// Exposed via `AudioServiceProtocol` so `DependencyContainer` can wire
    /// the same instance into `SessionPlaybackCoordinator` and other consumers.
    var audioPlayerService: any AudioPlayerServiceProtocol {
        audioPlayer
    }

    /// The shared `AVAudioEngine` instance.
    ///
    /// Exposed for `SpeechCaptureService` to install input taps for mic capture.
    var sharedEngine: AVAudioEngine {
        audioEngine
    }

    /// Main mixer volume.
    private var mainVolume: Float = 1.0

    /// Playback volume (public for protocol conformance).
    var playbackVolume: Float = 1.0

    // MARK: - Initialization

    /// Creates a new AudioService with a fresh `AudioSessionController`.
    ///
    /// - Parameter sessionController: Session controller for audio session management
    ///   (defaults to a new `AudioSessionController` instance).
    init(sessionController: (any AudioSessionControllerProtocol)? = nil) {
        self.audioEngine = AVAudioEngine()
        self.sessionController = sessionController ?? AudioSessionController()
        self.backgroundMusicService = BackgroundMusicService()
        self.audioPlayer = AudioPlayerService()

        audioServiceLog.info("✅ AudioService initialized")
    }

    /// Creates an AudioService with injected dependencies (for testing).
    init(
        sessionController: any AudioSessionControllerProtocol,
        backgroundMusicService: BackgroundMusicService,
        audioPlayer: AudioPlayerService
    ) {
        self.audioEngine = AVAudioEngine()
        self.sessionController = sessionController
        self.backgroundMusicService = backgroundMusicService
        self.audioPlayer = audioPlayer
    }

    // MARK: - Engine Lifecycle

    /// Starts the audio engine.
    ///
    /// Configures the audio session for playback, attaches audio components
    /// to the engine, starts the engine, and registers it with the session
    /// controller for lifecycle coordination.
    ///
    /// - Throws: `AppError` if engine fails to start
    func start() async throws {
        guard !isRunning else {
            audioServiceLog.debug("Engine already running")
            return
        }

        audioServiceLog.info("🚀 Starting audio engine...")

        // Configure audio session via controller (no engine management — engine isn't started yet)
        do {
            try await sessionController.transition(
                to: .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers],
                engineAction: .none
            )
        } catch {
            audioServiceLog.error("❌ Session configuration failed: \(error.localizedDescription)")
            throw AppError.audioSessionConfigurationFailed(reason: error.localizedDescription)
        }

        // Attach components to engine
        backgroundMusicService.attachTo(engine: audioEngine)
        await audioPlayer.attachTo(engine: audioEngine)

        // Start the engine
        do {
            try audioEngine.start()
            isRunning = true
            audioServiceLog.info("✅ Audio engine started")
        } catch {
            audioServiceLog.error("❌ Engine start failed: \(error.localizedDescription)")
            throw AppError.audioEngineInitializationFailed(reason: error.localizedDescription)
        }

        // Register engine with session controller for lifecycle coordination
        sessionController.registerEngine(audioEngine)

        // Wire callbacks for engine full-stop restart (reschedule music)
        sessionController.onEngineRestartedAfterFullStop = { [weak self] in
            self?.backgroundMusicService.rescheduleCurrentTrack()
        }

        // Wire interruption callbacks
        sessionController.onInterruptionBegan = { [weak self] in
            audioServiceLog.info("⚠️ Handling interruption began")
            self?.backgroundMusicService.pause()
            // TTS playback interruption is handled by CancellationError from
            // AudioPlayerService's continuation when the engine is paused by iOS.
        }

        sessionController.onInterruptionEnded = { [weak self] shouldResume in
            audioServiceLog.info("✅ Handling interruption ended (shouldResume: \(shouldResume))")
            if shouldResume {
                self?.backgroundMusicService.resume()
            }
        }
    }

    /// Stops the audio engine.
    func stop() async {
        guard isRunning else { return }

        audioServiceLog.info("🛑 Stopping audio engine...")

        // Stop components
        backgroundMusicService.stop()
        await audioPlayer.stop()

        // Detach background music from engine
        backgroundMusicService.detachFrom(engine: audioEngine)

        // Stop engine
        audioEngine.stop()
        isRunning = false

        // Deactivate session
        sessionController.deactivateSession(notifyOthers: true)

        audioServiceLog.info("✅ Audio engine stopped")
    }

    // MARK: - Background Music

    /// Whether background music is currently playing.
    var isBackgroundMusicPlaying: Bool {
        backgroundMusicService.isPlaying
    }

    /// The currently playing music category (`nil` if stopped).
    var currentMusicCategory: MusicCategory? {
        backgroundMusicService.currentCategory
    }

    /// Starts playing background music from the specified category.
    ///
    /// Ensures the audio engine is running before playback begins.
    /// - Parameter category: The music category to play
    func playBackgroundMusic(category: MusicCategory) async {
        audioServiceLog.info("🎵 Playing background music: \(category.rawValue)")

        // Ensure engine is running before scheduling on the player node
        if !isRunning {
            do {
                try await start()
            } catch {
                audioServiceLog.error("❌ Failed to start engine for background music: \(error.localizedDescription)")
                return
            }
        }

        backgroundMusicService.play(category: category)
    }

    /// Stops background music playback.
    func stopBackgroundMusic() {
        audioServiceLog.info("🔇 Stopping background music")
        backgroundMusicService.stop()
    }

    /// Pauses background music (retains position for resume).
    func pauseBackgroundMusic() {
        backgroundMusicService.pause()
    }

    /// Resumes paused background music.
    func resumeBackgroundMusic() {
        backgroundMusicService.resume()
    }

    /// Sets the background music volume.
    /// - Parameter volume: Volume level (0.0–1.0)
    func setBackgroundMusicVolume(_ volume: Float) {
        backgroundMusicService.setVolume(volume)
    }

    // MARK: - Audio Playback

    /// Plays a cached audio file.
    /// - Parameter fileName: Name of the cached file
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playAudioFile(named fileName: String) async throws {
        audioServiceLog.info("▶️ Playing file: \(fileName)")

        // Ensure engine is running
        if !isRunning {
            try await start()
        }

        try await audioPlayer.playFile(named: fileName)
    }

    /// Plays audio data directly.
    /// - Parameter data: Audio data to play
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playAudioData(_ data: Data) async throws {
        audioServiceLog.info("▶️ Playing audio data (\(data.count) bytes)")

        // Ensure engine is running
        if !isRunning {
            try await start()
        }

        try await audioPlayer.playData(data)
    }

    /// Stops audio playback.
    func stopPlayback() async {
        audioServiceLog.info("⏹️ Stopping playback")
        await audioPlayer.stop()
    }

    /// Pauses audio playback.
    func pausePlayback() async {
        audioServiceLog.info("⏸️ Pausing playback")
        await audioPlayer.pause()
    }

    /// Resumes paused playback.
    func resumePlayback() async {
        audioServiceLog.info("▶️ Resuming playback")
        await audioPlayer.resume()
    }

    // MARK: - Volume Control

    /// Sets the main output volume.
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setMainVolume(_ volume: Float) {
        mainVolume = max(0, min(1, volume))
        audioEngine.mainMixerNode.outputVolume = mainVolume
    }

    /// Sets the playback volume.
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setPlaybackVolume(_ volume: Float) async {
        playbackVolume = max(0, min(1, volume))
        await audioPlayer.setVolume(playbackVolume)
    }

    // MARK: - Playback Info

    /// Whether audio is currently playing.
    var isPlaying: Bool {
        get async {
            await audioPlayer.isPlaying
        }
    }

    /// Current playback progress (0.0 - 1.0).
    var playbackProgress: Double {
        get async {
            await audioPlayer.progress
        }
    }
}

// MARK: - Preview/Mock Support

extension AudioService {
    /// Creates a no-op audio service for previews.
    static var preview: AudioService {
        AudioService()
    }
}
