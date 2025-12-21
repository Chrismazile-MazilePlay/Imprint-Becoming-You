//
//  AudioService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import Combine

// MARK: - AudioService

/// Main audio service that coordinates all audio functionality.
///
/// This service integrates:
/// - AVAudioEngine for low-latency audio processing
/// - Binaural beat generation for focus/relax/sleep modes
/// - Cached audio playback for TTS files
/// - Audio session management for interruptions
///
/// ## Architecture
/// ```
/// AudioService
/// ├── AudioSessionManager (session lifecycle)
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
    
    /// Session manager for audio session lifecycle
    private let sessionManager: AudioSessionManager
    
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
    
    /// Task for monitoring interruptions
    private var interruptionTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Creates a new AudioService with default components
    init() {
        self.audioEngine = AVAudioEngine()
        self.sessionManager = AudioSessionManager.shared
        self.binauralGenerator = StereoBinauralGenerator()
        self.audioPlayer = AudioPlayerService()
    }
    
    /// Creates an AudioService with injected dependencies (for testing)
    init(
        sessionManager: AudioSessionManager,
        binauralGenerator: StereoBinauralGenerator,
        audioPlayer: AudioPlayerService
    ) {
        self.audioEngine = AVAudioEngine()
        self.sessionManager = sessionManager
        self.binauralGenerator = binauralGenerator
        self.audioPlayer = audioPlayer
    }
    
    deinit {
        interruptionTask?.cancel()
    }
    
    // MARK: - Engine Lifecycle
    
    /// Starts the audio engine
    /// - Throws: `AppError` if engine fails to start
    func start() async throws {
        guard !isRunning else { return }
        
        // Configure audio session
        try await sessionManager.configureForPlayback()
        try await sessionManager.activate()
        
        // Attach components to engine
        try binauralGenerator.attachTo(engine: audioEngine)
        await audioPlayer.attachTo(engine: audioEngine)
        
        // Start the engine
        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            throw AppError.audioEngineInitializationFailed(reason: error.localizedDescription)
        }
        
        // Start monitoring interruptions
        startInterruptionMonitoring()
    }
    
    /// Stops the audio engine
    func stop() async {
        guard isRunning else { return }
        
        // Stop components
        binauralGenerator.stop()
        await audioPlayer.stop()
        
        // Stop engine
        audioEngine.stop()
        isRunning = false
        currentBinauralPreset = nil
        
        // Deactivate session
        await sessionManager.deactivate(notifyOthers: true)
        
        // Cancel interruption monitoring
        interruptionTask?.cancel()
        interruptionTask = nil
    }
    
    // MARK: - Binaural Beats
    
    /// Starts binaural beats with the specified preset
    /// - Parameter preset: The binaural preset to use
    /// - Throws: `AppError` if engine fails to start
    func startBinauralBeats(preset: BinauralPreset) async throws {
        guard preset != .off else {
            await stopBinauralBeats()
            return
        }
        
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
        
        binauralGenerator.changePreset(preset)
        currentBinauralPreset = preset
    }
    
    // MARK: - Audio Playback
    
    /// Plays a cached audio file
    /// - Parameter fileName: Name of the cached file
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playAudioFile(named fileName: String) async throws {
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
    func playAudioData(_ data: Data) async throws {
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
        await audioPlayer.stop()
        
        // Restore binaural volume
        if currentBinauralPreset != nil {
            binauralGenerator.setVolume(binauralVolume)
        }
    }
    
    /// Pauses audio playback
    func pausePlayback() async {
        await audioPlayer.pause()
    }
    
    /// Resumes paused playback
    func resumePlayback() async {
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
    
    /// Starts monitoring for audio interruptions
    private func startInterruptionMonitoring() {
        interruptionTask = Task { [weak self] in
            guard let self = self else { return }
            
            let stream = await self.sessionManager.interruptionStream
            
            for await event in stream {
                await self.handleInterruption(event)
            }
        }
    }
    
    /// Handles audio interruption events
    private func handleInterruption(_ event: AudioInterruptionEvent) async {
        switch event {
        case .began:
            // Pause everything
            await audioPlayer.pause()
            binauralGenerator.stop()
            
            // Note: Don't stop the engine - we want to resume quickly
            
        case .ended(let shouldResume):
            if shouldResume {
                // Resume binaural beats if they were playing
                if let preset = currentBinauralPreset {
                    binauralGenerator.start(preset: preset)
                }
                
                // Resume audio playback if it was paused
                await audioPlayer.resume()
            }
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
