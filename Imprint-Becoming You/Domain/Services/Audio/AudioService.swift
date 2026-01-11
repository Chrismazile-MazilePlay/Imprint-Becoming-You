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
/// This service integrates:
/// - AVAudioEngine for low-latency audio processing
/// - Binaural beat generation for focus/relax/sleep modes
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
/// ├── BinauralBeatGenerator (tone generation)
/// ├── AudioPlayerService (file playback)
/// └── AVAudioEngine (core engine)
/// ```
///
/// ## Usage
/// ```swift
/// let audio = AudioService()
/// try await audio.start()
/// await audio.startBinauralBeats(preset: .focus)
/// try await audio.playAudioFile(named: "affirmation.mp3")
/// ```
final class AudioService: AudioServiceProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The core audio engine
    private let audioEngine: AVAudioEngine
    
    /// Session provider (protocol-based dependency)
    private let sessionProvider: any AudioSessionProviding & AudioInterruptionHandling
    
    /// Binaural beat generator
    private let binauralGenerator: StereoBinauralGenerator
    
    /// Audio file player
    private let audioPlayer: AudioPlayerService
    
    /// Whether the audio engine is running
    private(set) var isRunning: Bool = false
    
    /// Current binaural preset
    private(set) var currentBinauralPreset: BinauralPreset? = nil
    
    /// Main mixer volume
    private var mainVolume: Float = 1.0
    
    /// Binaural beats volume (public for protocol conformance)
    var binauralVolume: Float = Constants.Audio.binauralVolume
    
    /// Playback volume (public for protocol conformance)
    var playbackVolume: Float = 1.0
    
    /// Playback delegate
    weak var playbackDelegate: AudioPlaybackDelegate?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Task for monitoring events
    private var eventMonitorTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Creates a new AudioService with default components
    /// - Parameter sessionProvider: Provider for audio session operations (defaults to AudioCoordinator.shared)
    @MainActor
    init(sessionProvider: (any AudioSessionProviding & AudioInterruptionHandling)? = nil) {
        self.audioEngine = AVAudioEngine()
        self.sessionProvider = sessionProvider ?? AudioCoordinator.shared
        self.binauralGenerator = StereoBinauralGenerator()
        self.audioPlayer = AudioPlayerService()
        
        audioServiceLog.info("✅ AudioService initialized")
    }
    
    /// Creates an AudioService with injected dependencies (for testing)
    init(
        sessionProvider: any AudioSessionProviding & AudioInterruptionHandling,
        binauralGenerator: StereoBinauralGenerator,
        audioPlayer: AudioPlayerService
    ) {
        self.audioEngine = AVAudioEngine()
        self.sessionProvider = sessionProvider
        self.binauralGenerator = binauralGenerator
        self.audioPlayer = audioPlayer
    }
    
    deinit {
        eventMonitorTask?.cancel()
    }
    
    // MARK: - Engine Lifecycle
    
    /// Starts the audio engine
    /// - Throws: `AppError` if engine fails to start
    @MainActor
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
        try binauralGenerator.attachTo(engine: audioEngine)
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
    @MainActor
    func stop() async {
        guard isRunning else { return }
        
        audioServiceLog.info("🛑 Stopping audio engine...")
        
        // Stop components
        binauralGenerator.stop()
        await audioPlayer.stop()
        
        // Stop engine
        audioEngine.stop()
        isRunning = false
        currentBinauralPreset = nil
        
        // Deactivate session
        sessionProvider.deactivateSession(notifyOthers: true)
        
        // Cancel event monitoring
        eventMonitorTask?.cancel()
        eventMonitorTask = nil
        
        audioServiceLog.info("✅ Audio engine stopped")
    }
    
    // MARK: - Binaural Beats
    
    /// Starts binaural beats with the specified preset
    /// - Parameter preset: The binaural preset to use
    /// - Throws: `AppError` if engine fails to start
    @MainActor
    func startBinauralBeats(preset: BinauralPreset) async throws {
        guard preset != .off else {
            await stopBinauralBeats()
            return
        }
        
        audioServiceLog.info("🎵 Starting binaural: \(preset.rawValue)")
        
        // Ensure engine is running
        if !isRunning {
            try await start()
        }
        
        binauralGenerator.setVolume(binauralVolume)
        binauralGenerator.start(preset: preset)
        currentBinauralPreset = preset
    }
    
    /// Stops binaural beats
    func stopBinauralBeats() async {
        audioServiceLog.info("🔇 Stopping binaural")
        binauralGenerator.stop()
        currentBinauralPreset = nil
    }
    
    /// Changes the binaural preset without stopping
    /// - Parameter preset: The new preset
    func changeBinauralPreset(_ preset: BinauralPreset) async {
        if preset == .off {
            await stopBinauralBeats()
            return
        }
        
        audioServiceLog.info("🎵 Changing binaural to: \(preset.rawValue)")
        binauralGenerator.changePreset(preset)
        currentBinauralPreset = preset
    }
    
    // MARK: - Audio Playback
    
    /// Plays a cached audio file
    /// - Parameter fileName: Name of the cached file
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    @MainActor
    func playAudioFile(named fileName: String) async throws {
        audioServiceLog.info("▶️ Playing file: \(fileName)")
        
        // Ensure engine is running
        if !isRunning {
            try await start()
        }
        
        // Lower binaural volume during playback for clarity
        if currentBinauralPreset != nil {
            binauralGenerator.setVolume(binauralVolume * 0.3)
        }
        
        do {
            try await audioPlayer.playFile(named: fileName)
        } catch {
            // Restore binaural volume
            if currentBinauralPreset != nil {
                binauralGenerator.setVolume(binauralVolume)
            }
            throw error
        }
        
        // Restore binaural volume
        if currentBinauralPreset != nil {
            binauralGenerator.setVolume(binauralVolume)
        }
        
        playbackDelegate?.audioPlaybackDidComplete()
    }
    
    /// Plays audio data directly
    /// - Parameter data: Audio data to play
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    @MainActor
    func playAudioData(_ data: Data) async throws {
        audioServiceLog.info("▶️ Playing audio data (\(data.count) bytes)")
        
        // Ensure engine is running
        if !isRunning {
            try await start()
        }
        
        // Lower binaural volume during playback
        if currentBinauralPreset != nil {
            binauralGenerator.setVolume(binauralVolume * 0.3)
        }
        
        do {
            try await audioPlayer.playData(data)
        } catch {
            if currentBinauralPreset != nil {
                binauralGenerator.setVolume(binauralVolume)
            }
            throw error
        }
        
        // Restore binaural volume
        if currentBinauralPreset != nil {
            binauralGenerator.setVolume(binauralVolume)
        }
        
        playbackDelegate?.audioPlaybackDidComplete()
    }
    
    /// Stops audio playback
    func stopPlayback() async {
        audioServiceLog.info("⏹️ Stopping playback")
        await audioPlayer.stop()
        
        // Restore binaural volume
        if currentBinauralPreset != nil {
            binauralGenerator.setVolume(binauralVolume)
        }
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
    
    /// Sets the binaural beats volume
    /// - Parameter volume: Volume level (0.0 - 1.0)
    func setBinauralVolume(_ volume: Float) async {
        binauralVolume = max(0, min(1, volume))
        
        // Only apply if not currently ducked for playback
        let isCurrentlyPlaying = await audioPlayer.isPlaying
        if !isCurrentlyPlaying {
            binauralGenerator.setVolume(binauralVolume)
        }
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
    @MainActor
    private func startEventMonitoring() {
        eventMonitorTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await event in self.sessionProvider.eventStream {
                await self.handleEvent(event)
            }
        }
    }
    
    /// Handles audio coordinator events
    @MainActor
    private func handleEvent(_ event: AudioCoordinatorEvent) async {
        switch event {
        case .interruptionBegan:
            audioServiceLog.info("⚠️ Handling interruption began")
            await audioPlayer.pause()
            binauralGenerator.stop()
            
        case .interruptionEnded(let shouldResume):
            audioServiceLog.info("✅ Handling interruption ended (shouldResume: \(shouldResume))")
            if shouldResume {
                // Resume binaural beats if they were playing
                if let preset = currentBinauralPreset {
                    binauralGenerator.start(preset: preset)
                }
                
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
    @MainActor
    static var preview: AudioService {
        AudioService()
    }
}
