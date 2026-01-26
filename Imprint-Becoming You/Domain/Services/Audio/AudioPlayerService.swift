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
    
    /// AVAudioPlayer instance for data playback (separate from AVAudioEngine)
    private var dataPlayer: AVAudioPlayer?
    
    /// Delegate for data player completion (must be retained)
    private var dataPlayerDelegate: AudioPlayerCompletionDelegate?
    
    /// Continuation for data playback completion
    private var dataPlaybackContinuation: CheckedContinuation<Void, Error>?
    
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
        
        // Schedule the file for playback with explicit callback type
        // Using .dataPlayedBack ensures callback fires when audio reaches output hardware
        playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
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
    
    /// Plays audio data directly (assumes encoded format like MP3)
    /// - Parameter data: Audio data to play
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playData(_ data: Data) async throws {
        // Write to temporary file (synchronous but small operation)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        
        // Perform file write
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            throw AppError.audioPlaybackFailed(reason: "Failed to write temp file: \(error.localizedDescription)")
        }
        
        // Play the file and clean up after
        do {
            try await playFile(at: tempURL)
            // Clean up temp file after playback completes
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            // Clean up on error too
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
    
    /// Plays audio data directly using AVAudioPlayer (from Kokoro TTS)
    ///
    /// Uses `AVAudioPlayer(data:)` which handles the audio format automatically.
    /// This is the same approach used by TTSService and works reliably with
    /// Kokoro TTS output.
    ///
    /// - Parameters:
    ///   - data: Audio data (WAV format from Kokoro TTS)
    ///   - sampleRate: Sample rate (unused, kept for API compatibility)
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playRawPCMData(_ data: Data, sampleRate: Double = 24000) async throws {
        // Stop any current playback
        stop()
        
        guard !data.isEmpty else {
            throw AppError.audioPlaybackFailed(reason: "No audio data to play")
        }
        
        #if DEBUG
        print("🔊 AudioPlayerService: Playing \(data.count) bytes via AVAudioPlayer")
        #endif
        
        // Create the player synchronously within actor context
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw AppError.audioPlaybackFailed(reason: "Failed to create audio player: \(error.localizedDescription)")
        }
        
        // Store reference
        self.dataPlayer = player
        
        // Create delegate with weak self capture - callback dispatches back to actor
        let delegate = AudioPlayerCompletionDelegate { [weak self] success in
            Task {
                await self?.handleDataPlaybackComplete(success: success)
            }
        }
        self.dataPlayerDelegate = delegate
        player.delegate = delegate
        player.volume = self.volume
        
        // Configure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            throw AppError.audioPlaybackFailed(reason: "Failed to configure audio session: \(error.localizedDescription)")
        }
        
        // Start playback
        guard player.play() else {
            throw AppError.audioPlaybackFailed(reason: "Failed to start playback")
        }
        
        self.isPlaying = true
        
        #if DEBUG
        print("🔊 AudioPlayerService: Playback started (duration: \(String(format: "%.2f", player.duration))s)")
        #endif
        
        // Wait for completion using continuation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.dataPlaybackContinuation = continuation
        }
    }
    
    /// Handles completion of data playback (called from delegate callback)
    private func handleDataPlaybackComplete(success: Bool) {
        dataPlayer = nil
        dataPlayerDelegate = nil
        isPlaying = false
        
        if success {
            dataPlaybackContinuation?.resume(returning: ())
        } else {
            dataPlaybackContinuation?.resume(throwing: AppError.audioPlaybackFailed(reason: "Playback interrupted"))
        }
        dataPlaybackContinuation = nil
    }
    
    /// Stops playback
    func stop() {
        // Stop AVAudioEngine playback
        playerNode.stop()
        
        // Stop AVAudioPlayer playback (for data/TTS)
        dataPlayer?.stop()
        dataPlayer = nil
        dataPlayerDelegate = nil
        
        isPlaying = false
        isPaused = false
        currentAudioFile = nil
        
        // Cancel any waiting continuations
        playbackContinuation?.resume(returning: ())
        playbackContinuation = nil
        
        dataPlaybackContinuation?.resume(returning: ())
        dataPlaybackContinuation = nil
    }
    
    /// Pauses playback
    func pause() {
        guard isPlaying && !isPaused else { return }
        playerNode.pause()
        dataPlayer?.pause()
        isPaused = true
    }
    
    /// Resumes paused playback
    func resume() {
        guard isPaused else { return }
        playerNode.play()
        dataPlayer?.play()
        isPaused = false
    }
    
    /// Sets the playback volume
    /// - Parameter newVolume: Volume level (0.0 - 1.0)
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        playerNode.volume = volume
        dataPlayer?.volume = volume
    }
    
    // MARK: - Playback Info
    
    /// Current playback position in seconds
    var currentTime: TimeInterval {
        // Check data player first
        if let dataPlayer = dataPlayer, dataPlayer.isPlaying {
            return dataPlayer.currentTime
        }
        
        // Then check engine player
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    
    /// Total duration of current audio in seconds
    var duration: TimeInterval {
        // Check data player first
        if let dataPlayer = dataPlayer {
            return dataPlayer.duration
        }
        
        // Then check audio file
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

// MARK: - Audio Player Completion Delegate

/// Helper class to handle AVAudioPlayer delegate callbacks for data playback.
final class AudioPlayerCompletionDelegate: NSObject, AVAudioPlayerDelegate {
    
    private let completion: @Sendable (Bool) -> Void
    
    init(completion: @escaping @Sendable (Bool) -> Void) {
        self.completion = completion
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion(flag)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        #if DEBUG
        print("⚠️ AudioPlayerCompletionDelegate: Decode error - \(error?.localizedDescription ?? "unknown")")
        #endif
        completion(false)
    }
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
