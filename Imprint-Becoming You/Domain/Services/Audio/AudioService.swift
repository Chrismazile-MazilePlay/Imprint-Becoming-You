//
//  AudioService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import Combine
import os.log

// MARK: - Logger

private let audioServiceLog = Logger(subsystem: "com.imprint.audio", category: "AudioService")

// MARK: - AudioService

/// Main audio service that coordinates all audio functionality.
///
/// This service is `@MainActor` isolated because:
/// 1. Audio playback state affects UI
/// 2. Background music controls are UI-driven
/// 3. Callback delegates update UI
///
/// This service integrates:
/// - AVAudioEngine for low-latency audio processing
/// - Background music playback via `BackgroundMusicService`
/// - Cached audio playback for TTS files
/// - Audio session management via AudioCoordinator
///
/// ## SOLID Compliance
/// - **SRP**: Coordinates audio playback components
/// - **OCP**: Works with any FullAudioSessionProviding implementation
/// - **LSP**: Fully implements AudioServiceProtocol
/// - **ISP**: AudioServiceProtocol is focused on playback
/// - **DIP**: Depends on protocols, not concrete implementations
///
/// ## Architecture
/// ```
/// AudioService
/// ├── AudioCoordinator (session lifecycle via protocol)
/// ├── BackgroundMusicService (looping music playback)
/// ├── AudioPlayerService (TTS file playback)
/// └── AVAudioEngine (core engine)
/// ```
///
/// ## Usage
/// ```swift
/// let audio = AudioService()
/// try await audio.start()
/// audio.playBackgroundMusic(category: .focus)
/// try await audio.playAudioFile(named: "affirmation.mp3")
/// ```
@MainActor
final class AudioService: AudioServiceProtocol {

    // MARK: - Properties

    /// The core audio engine
    private let audioEngine: AVAudioEngine

    /// Session provider (protocol-based dependency)
    private let sessionProvider: any AudioSessionProviding & AudioInterruptionHandling

    /// Background music player
    private let backgroundMusicService: BackgroundMusicService

    /// Audio file player
    private let audioPlayer: AudioPlayerService

    /// Whether the audio engine is running
    private(set) var isRunning: Bool = false

    /// The engine-attached audio player for TTS playback.
    ///
    /// Exposed via `AudioServiceProtocol` so `DependencyContainer` can wire
    /// the same instance into `SessionPlaybackCoordinator` and other consumers.
    /// This ensures all TTS audio routes through the shared `AVAudioEngine`.
    var audioPlayerService: any AudioPlayerServiceProtocol {
        audioPlayer
    }

    /// Main mixer volume
    private var mainVolume: Float = 1.0

    /// Playback volume (public for protocol conformance)
    var playbackVolume: Float = 1.0

    /// Playback delegate
    weak var playbackDelegate: AudioPlaybackDelegate?

    /// Task for monitoring events
    private var eventMonitorTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new AudioService with default components
    /// - Parameter sessionProvider: Provider for audio session operations (defaults to AudioCoordinator.shared)
    init(sessionProvider: (any AudioSessionProviding & AudioInterruptionHandling)? = nil) {
        self.audioEngine = AVAudioEngine()
        self.sessionProvider = sessionProvider ?? AudioCoordinator.shared
        self.backgroundMusicService = BackgroundMusicService()
        self.audioPlayer = AudioPlayerService()

        audioServiceLog.info("✅ AudioService initialized")
    }

    /// Creates an AudioService with injected dependencies (for testing)
    init(
        sessionProvider: any AudioSessionProviding & AudioInterruptionHandling,
        backgroundMusicService: BackgroundMusicService,
        audioPlayer: AudioPlayerService
    ) {
        self.audioEngine = AVAudioEngine()
        self.sessionProvider = sessionProvider
        self.backgroundMusicService = backgroundMusicService
        self.audioPlayer = audioPlayer
    }

    deinit {
        eventMonitorTask?.cancel()
    }

    // MARK: - Engine Lifecycle

    /// Starts the audio engine
    /// - Throws: `AppError` if engine fails to start
    func start() async throws {
        guard !isRunning else {
            audioServiceLog.debug("Engine already running")
            return
        }

        audioServiceLog.info("🚀 Starting audio engine...")

        // Configure audio session via provider
        do {
            try sessionProvider.configureForPlayback()
            try sessionProvider.activateSession()
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

        // Start monitoring events
        startEventMonitoring()
    }

    /// Stops the audio engine
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
        sessionProvider.deactivateSession(notifyOthers: true)

        // Cancel event monitoring
        eventMonitorTask?.cancel()
        eventMonitorTask = nil

        audioServiceLog.info("✅ Audio engine stopped")
    }

    // MARK: - Background Music

    /// Whether background music is currently playing
    var isBackgroundMusicPlaying: Bool {
        backgroundMusicService.isPlaying
    }

    /// The currently playing music category (`nil` if stopped)
    var currentMusicCategory: MusicCategory? {
        backgroundMusicService.currentCategory
    }

    /// Starts playing background music from the specified category.
    ///
    /// Ensures the audio engine is running before playback begins.
    /// If the engine isn't started yet (e.g., user selects music from the
    /// home screen before any TTS playback), this method starts it first.
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

    /// Stops background music playback
    func stopBackgroundMusic() {
        audioServiceLog.info("🔇 Stopping background music")
        backgroundMusicService.stop()
    }

    /// Pauses background music (retains position for resume)
    func pauseBackgroundMusic() {
        backgroundMusicService.pause()
    }

    /// Resumes paused background music
    func resumeBackgroundMusic() {
        backgroundMusicService.resume()
    }

    /// Sets the background music volume
    /// - Parameter volume: Volume level (0.0–1.0)
    func setBackgroundMusicVolume(_ volume: Float) {
        backgroundMusicService.setVolume(volume)
    }

    // MARK: - Audio Playback

    /// Plays a cached audio file
    /// - Parameter fileName: Name of the cached file
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playAudioFile(named fileName: String) async throws {
        audioServiceLog.info("▶️ Playing file: \(fileName)")

        // Ensure engine is running
        if !isRunning {
            try await start()
        }

        do {
            try await audioPlayer.playFile(named: fileName)
        } catch {
            throw error
        }

        playbackDelegate?.audioPlaybackDidComplete()
    }

    /// Plays audio data directly
    /// - Parameter data: Audio data to play
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playAudioData(_ data: Data) async throws {
        audioServiceLog.info("▶️ Playing audio data (\(data.count) bytes)")

        // Ensure engine is running
        if !isRunning {
            try await start()
        }

        do {
            try await audioPlayer.playData(data)
        } catch {
            throw error
        }

        playbackDelegate?.audioPlaybackDidComplete()
    }

    /// Stops audio playback
    func stopPlayback() async {
        audioServiceLog.info("⏹️ Stopping playback")
        await audioPlayer.stop()
    }

    /// Pauses audio playback
    func pausePlayback() async {
        audioServiceLog.info("⏸️ Pausing playback")
        await audioPlayer.pause()
    }

    /// Resumes paused playback
    func resumePlayback() async {
        audioServiceLog.info("▶️ Resuming playback")
        await audioPlayer.resume()
    }

    // MARK: - Volume Control

    /// Sets the main output volume
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setMainVolume(_ volume: Float) {
        mainVolume = max(0, min(1, volume))
        audioEngine.mainMixerNode.outputVolume = mainVolume
    }

    /// Sets the playback volume
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setPlaybackVolume(_ volume: Float) async {
        playbackVolume = max(0, min(1, volume))
        await audioPlayer.setVolume(playbackVolume)
    }

    // MARK: - Playback Info

    /// Whether audio is currently playing
    var isPlaying: Bool {
        get async {
            await audioPlayer.isPlaying
        }
    }

    /// Current playback progress (0.0 - 1.0)
    var playbackProgress: Double {
        get async {
            await audioPlayer.progress
        }
    }

    // MARK: - Private Methods

    /// Starts monitoring for audio events
    private func startEventMonitoring() {
        eventMonitorTask = Task { [weak self] in
            guard let self = self else { return }

            for await event in self.sessionProvider.eventStream {
                await self.handleEvent(event)
            }
        }
    }

    /// Handles audio coordinator events
    private func handleEvent(_ event: AudioCoordinatorEvent) async {
        switch event {
        case .interruptionBegan:
            audioServiceLog.info("⚠️ Handling interruption began")
            await audioPlayer.pause()
            backgroundMusicService.pause()

        case .interruptionEnded(let shouldResume):
            audioServiceLog.info("✅ Handling interruption ended (shouldResume: \(shouldResume))")
            if shouldResume {
                // Resume background music if it was playing
                backgroundMusicService.resume()

                // Resume audio playback if it was paused
                await audioPlayer.resume()
            }

        case .routeChanged(let change):
            audioServiceLog.info("🔀 Route changed: \(String(describing: change))")
            // Handle route changes if needed

        case .stateChanged(let newState):
            audioServiceLog.debug("📊 Audio state: \(String(describing: newState))")

        case .errorOccurred(let error):
            audioServiceLog.error("❌ Audio error: \(String(describing: error))")

        default:
            // Ignore other events
            break
        }
    }
}

// MARK: - Preview/Mock Support

extension AudioService {
    /// Creates a no-op audio service for previews
    static var preview: AudioService {
        AudioService()
    }
}
