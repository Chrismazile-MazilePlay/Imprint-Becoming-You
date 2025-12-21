//
//  AudioPlayerService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation

// MARK: - AudioPlayerService

/// Plays cached audio files using AVAudioEngine.
///
/// This service handles playback of TTS audio files that have been cached
/// from ElevenLabs or other sources. It integrates with the main audio engine
/// to allow simultaneous playback with binaural beats.
///
/// ## Usage
/// ```swift
/// let player = AudioPlayerService()
/// player.attachTo(engine: audioEngine)
/// try await player.playFile(named: "cached-audio.mp3")
/// ```
actor AudioPlayerService {
    
    // MARK: - Properties
    
    /// Player node for audio playback
    private var playerNode: AVAudioPlayerNode
    
    /// Audio file currently loaded
    private var currentAudioFile: AVAudioFile?
    
    /// Whether playback is currently active
    private(set) var isPlaying: Bool = false
    
    /// Whether playback is paused
    private(set) var isPaused: Bool = false
    
    /// Current playback volume (0.0 - 1.0)
    private var volume: Float = 1.0
    
    /// Delegate for playback events
    weak var delegate: AudioPlayerDelegate?
    
    /// Continuation for playback completion
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    
    /// Reference to attached engine
    private weak var attachedEngine: AVAudioEngine?
    
    /// Cache manager for file access
    private let cacheManager: AudioCacheManager
    
    // MARK: - Initialization
    
    /// Creates a new audio player service
    /// - Parameter cacheManager: The cache manager to use for file access
    init(cacheManager: AudioCacheManager = .shared) {
        self.playerNode = AVAudioPlayerNode()
        self.cacheManager = cacheManager
    }
    
    // MARK: - Engine Attachment
    
    /// Attaches the player to an audio engine
    /// - Parameter engine: The audio engine to attach to
    func attachTo(engine: AVAudioEngine) {
        engine.attach(playerNode)
        
        // Connect with a flexible format - will reconnect when playing
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        attachedEngine = engine
    }
    
    /// Detaches from the audio engine
    func detachFrom(engine: AVAudioEngine) {
        stop()
        engine.detach(playerNode)
        attachedEngine = nil
    }
    
    // MARK: - Playback Control
    
    /// Plays an audio file from the cache
    /// - Parameter fileName: Name of the cached file
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playFile(named fileName: String) async throws {
        guard let fileURL = await cacheManager.fileURL(forFileName: fileName) else {
            throw AppError.audioPlaybackFailed(reason: "File not found: \(fileName)")
        }
        
        try await playFile(at: fileURL)
    }
    
    /// Plays an audio file from a URL
    /// - Parameter url: URL of the audio file
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playFile(at url: URL) async throws {
        // Stop any current playback
        stop()
        
        // Load the audio file
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw AppError.audioPlaybackFailed(reason: "Failed to load audio file: \(error.localizedDescription)")
        }
        
        currentAudioFile = audioFile
        
        // Reconnect player node with correct format if needed
        if let engine = attachedEngine {
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)
        }
        
        // Schedule the file for playback
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            Task {
                await self?.handlePlaybackComplete()
            }
        }
        
        // Apply volume
        playerNode.volume = volume
        
        // Start playback
        playerNode.play()
        isPlaying = true
        isPaused = false
        
        // Wait for completion
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playbackContinuation = continuation
        }
    }
    
    /// Plays audio data directly
    /// - Parameter data: Audio data to play
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playData(_ data: Data) async throws {
        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        
        do {
            try data.write(to: tempURL)
        } catch {
            throw AppError.audioPlaybackFailed(reason: "Failed to write temp file: \(error.localizedDescription)")
        }
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        try await playFile(at: tempURL)
    }
    
    /// Stops playback
    func stop() {
        playerNode.stop()
        isPlaying = false
        isPaused = false
        currentAudioFile = nil
        
        // Cancel any waiting continuation
        playbackContinuation?.resume(returning: ())
        playbackContinuation = nil
    }
    
    /// Pauses playback
    func pause() {
        guard isPlaying && !isPaused else { return }
        playerNode.pause()
        isPaused = true
    }
    
    /// Resumes paused playback
    func resume() {
        guard isPaused else { return }
        playerNode.play()
        isPaused = false
    }
    
    /// Sets the playback volume
    /// - Parameter newVolume: Volume level (0.0 - 1.0)
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        playerNode.volume = volume
    }
    
    // MARK: - Playback Info
    
    /// Current playback position in seconds
    var currentTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    
    /// Total duration of current audio in seconds
    var duration: TimeInterval {
        guard let audioFile = currentAudioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
    
    /// Playback progress (0.0 - 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    // MARK: - Private Methods
    
    /// Handles playback completion
    private func handlePlaybackComplete() {
        isPlaying = false
        isPaused = false
        
        // Resume continuation
        playbackContinuation?.resume(returning: ())
        playbackContinuation = nil
        
        // Notify delegate
        Task { @MainActor in
            await delegate?.audioPlaybackDidComplete()
        }
    }
}

// MARK: - AudioPlayerDelegate

/// Delegate protocol for audio player events
protocol AudioPlayerDelegate: AnyObject, Sendable {
    /// Called when playback completes
    @MainActor func audioPlaybackDidComplete()
    
    /// Called when playback is interrupted
    @MainActor func audioPlaybackWasInterrupted()
    
    /// Called when an error occurs
    @MainActor func audioPlaybackDidFail(with error: AppError)
}

// MARK: - Default Implementation

extension AudioPlayerDelegate {
    func audioPlaybackDidComplete() {}
    func audioPlaybackWasInterrupted() {}
    func audioPlaybackDidFail(with error: AppError) {}
}

// MARK: - Streaming Audio Player

/// Alternative player for streaming audio (future ElevenLabs streaming support)
actor StreamingAudioPlayer {
    
    // MARK: - Properties
    
    private var playerNode: AVAudioPlayerNode
    private var converter: AVAudioConverter?
    private var isPlaying: Bool = false
    private weak var attachedEngine: AVAudioEngine?
    
    // MARK: - Initialization
    
    init() {
        playerNode = AVAudioPlayerNode()
    }
    
    // MARK: - Engine Attachment
    
    func attachTo(engine: AVAudioEngine) {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        attachedEngine = engine
    }
    
    func detachFrom(engine: AVAudioEngine) {
        stop()
        engine.detach(playerNode)
        attachedEngine = nil
    }
    
    // MARK: - Streaming
    
    /// Streams audio data as it's received
    /// - Parameter chunk: Audio data chunk
    func streamChunk(_ chunk: Data) async throws {
        // TODO: Implement streaming playback for ElevenLabs streaming API
        // This would involve:
        // 1. Decoding MP3 chunks on the fly
        // 2. Converting to PCM
        // 3. Scheduling buffers for playback
    }
    
    func start() {
        playerNode.play()
        isPlaying = true
    }
    
    func stop() {
        playerNode.stop()
        isPlaying = false
    }
}
