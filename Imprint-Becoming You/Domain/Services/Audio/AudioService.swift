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

/// Thin facade that owns the playback `AVAudioEngine` and coordinates sub-services.
///
/// ## Architecture
/// ```
/// AudioService (thin facade)
/// ├── AudioSessionController (sole AVAudioSession owner)
/// ├── BackgroundMusicService  (looping music via AVAudioPlayerNode)
/// └── AudioPlayerService      (TTS playback via AVAudioPlayerNode)
/// ```
///
/// ## Responsibilities
/// - Create and own the playback `AVAudioEngine`
/// - Attach `BackgroundMusicService` and `AudioPlayerService` to the engine
/// - Coordinate engine start/stop with `AudioSessionController`
/// - Wire session controller callbacks (interruption, engine restart)
/// - Delegate all background music and playback calls to sub-services
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

    /// The playback audio engine. All music and TTS routes through this engine.
    private let audioEngine: AVAudioEngine

    /// Centralized audio session controller — sole owner of `AVAudioSession`.
    let sessionController: any AudioSessionControllerProtocol

    /// Background music player (attached to the playback engine).
    private let backgroundMusicService: BackgroundMusicService

    /// Audio file player for TTS (attached to the playback engine).
    private let audioPlayer: AudioPlayerService

    /// Whether the audio engine is currently running.
    private(set) var isRunning: Bool = false

    /// The engine-attached audio player for TTS playback.
    var audioPlayerService: any AudioPlayerServiceProtocol {
        audioPlayer
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

        audioServiceLog.info("AudioService initialized")
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

    /// Configures the audio session, attaches sub-services, and starts the engine.
    ///
    /// 1. Calls `sessionController.configure()` to set `.playAndRecord` permanently
    /// 2. Attaches `BackgroundMusicService` and `AudioPlayerService` to the engine
    /// 3. Starts the engine
    /// 4. Registers the engine with the session controller for lifecycle coordination
    /// 5. Wires interruption and engine-restart callbacks
    ///
    /// - Throws: `AppError` if session configuration or engine startup fails.
    func start() async throws {
        guard !isRunning else {
            audioServiceLog.debug("Engine already running")
            return
        }

        audioServiceLog.info("Starting audio engine...")

        // 1. Configure audio session (permanent .playAndRecord)
        do {
            try await sessionController.configure()
        } catch {
            audioServiceLog.error("Session configuration failed: \(error.localizedDescription)")
            throw AppError.audioSessionConfigurationFailed(reason: error.localizedDescription)
        }

        // 2. Attach sub-services to engine
        backgroundMusicService.attachTo(engine: audioEngine)
        await audioPlayer.attachTo(engine: audioEngine)

        // 3. Start the engine
        do {
            try audioEngine.start()
            isRunning = true
            audioServiceLog.info("Audio engine started")
        } catch {
            audioServiceLog.error("Engine start failed: \(error.localizedDescription)")
            throw AppError.audioEngineInitializationFailed(reason: error.localizedDescription)
        }

        // 4. Register engine with session controller for restart coordination
        sessionController.registerEngine(audioEngine)

        // 5. Wire callbacks
        sessionController.onEngineRestarted = { [weak self] in
            audioServiceLog.info("Engine restarted — rescheduling music")
            self?.backgroundMusicService.rescheduleCurrentTrack()
        }

        sessionController.onInterruptionBegan = { [weak self] in
            audioServiceLog.info("Interruption began — pausing music")
            self?.backgroundMusicService.pause()
        }

        sessionController.onInterruptionEnded = { [weak self] shouldResume in
            audioServiceLog.info("Interruption ended (shouldResume: \(shouldResume))")
            if shouldResume {
                self?.backgroundMusicService.resume()
            }
        }
    }

    /// Stops the audio engine and deactivates the audio session.
    func stop() async {
        guard isRunning else { return }

        audioServiceLog.info("Stopping audio engine...")

        // Stop sub-services
        backgroundMusicService.stop()
        await audioPlayer.stop()

        // Detach sub-services from engine
        backgroundMusicService.detachFrom(engine: audioEngine)
        await audioPlayer.detachFrom(engine: audioEngine)

        // Stop engine
        audioEngine.stop()
        isRunning = false

        // Deactivate session
        sessionController.deactivateSession(notifyOthers: true)

        audioServiceLog.info("Audio engine stopped")
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
    /// - Parameter category: The music category to play.
    func playBackgroundMusic(category: MusicCategory) async {
        audioServiceLog.info("Playing background music: \(category.rawValue)")

        // Ensure engine is running before scheduling on the player node
        if !isRunning {
            do {
                try await start()
            } catch {
                audioServiceLog.error("Failed to start engine for background music: \(error.localizedDescription)")
                return
            }
        }

        backgroundMusicService.play(category: category)
    }

    /// Stops background music playback.
    func stopBackgroundMusic() {
        audioServiceLog.info("Stopping background music")
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
    ///
    /// - Parameter volume: Volume level (0.0–1.0).
    func setBackgroundMusicVolume(_ volume: Float) {
        backgroundMusicService.setVolume(volume)
    }

    // MARK: - Audio Playback

    /// Plays a cached audio file.
    ///
    /// - Parameter fileName: Name of the cached file.
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails.
    func playAudioFile(named fileName: String) async throws {
        audioServiceLog.info("Playing file: \(fileName)")

        if !isRunning {
            try await start()
        }

        try await audioPlayer.playFile(named: fileName)
    }

    /// Plays audio data directly.
    ///
    /// - Parameter data: Audio data to play.
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails.
    func playAudioData(_ data: Data) async throws {
        audioServiceLog.info("Playing audio data (\(data.count) bytes)")

        if !isRunning {
            try await start()
        }

        try await audioPlayer.playData(data)
    }

    /// Stops audio playback.
    func stopPlayback() async {
        audioServiceLog.info("Stopping playback")
        await audioPlayer.stop()
    }

    /// Pauses audio playback.
    func pausePlayback() async {
        audioServiceLog.info("Pausing playback")
        await audioPlayer.pause()
    }

    /// Resumes paused playback.
    func resumePlayback() async {
        audioServiceLog.info("Resuming playback")
        await audioPlayer.resume()
    }

    // MARK: - Volume Control

    /// Sets the main output volume.
    ///
    /// - Parameter volume: Volume level (0.0–1.0).
    func setMainVolume(_ volume: Float) {
        mainVolume = max(0, min(1, volume))
        audioEngine.mainMixerNode.outputVolume = mainVolume
    }

    /// Sets the playback volume.
    ///
    /// - Parameter volume: Volume level (0.0–1.0).
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

    /// Current playback progress (0.0–1.0).
    var playbackProgress: Double {
        get async {
            await audioPlayer.progress
        }
    }
}

// MARK: - Preview Support

extension AudioService {
    /// Creates a no-op audio service for previews.
    static var preview: AudioService {
        AudioService()
    }
}
