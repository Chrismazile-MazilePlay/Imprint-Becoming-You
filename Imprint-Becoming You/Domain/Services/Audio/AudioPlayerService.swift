//
//  AudioPlayerService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import os

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
actor AudioPlayerService: AudioPlayerServiceProtocol {

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

    /// Thread-safe reference for synchronous stop from any isolation context.
    ///
    /// Protects the active `AVAudioPlayer` reference used by `immediateStop()`.
    /// Written inside actor isolation, read by `nonisolated immediateStop()`.
    private let _immediatePlayerRef = OSAllocatedUnfairLock<AVAudioPlayer?>(initialState: nil)

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
        // Stop any in-progress playback cleanly. Uses stop() which resumes
        // continuations with success — the previous caller completes normally
        // rather than receiving a CancellationError.
        stop()

        guard !data.isEmpty else {
            throw AppError.audioPlaybackFailed(reason: "No audio data to play")
        }

        #if DEBUG
        AppLogger.debug("Playing \(data.count) bytes via AVAudioPlayer", category: .audio)
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
        _immediatePlayerRef.withLock { $0 = player }

        // Create delegate with weak self capture - callback dispatches back to actor
        let delegate = AudioPlayerCompletionDelegate { [weak self] success in
            Task {
                await self?.handleDataPlaybackComplete(success: success)
            }
        }
        self.dataPlayerDelegate = delegate
        player.delegate = delegate
        player.volume = self.volume

        // Ensure audio session is active with correct category.
        //
        // TTSService.preConfigureAudioSession() sets `.playback` during warm-up,
        // but SpeechCaptureService changes the category to `.playAndRecord` during
        // listening phases. If the listening phase was interrupted (e.g., rapid skip
        // or loop transition), the category may still be `.playAndRecord` when we
        // try to play TTS in the next segment.
        //
        // The `setCategory()` call blocks for 50-200ms (HAL reconfiguration), so
        // it is dispatched to a background queue and awaited. This keeps the actor
        // free during the category switch while guaranteeing the session is in
        // `.playback` before playback begins.
        //
        // When the category is already `.playback` the background dispatch returns
        // almost immediately (~0ms) since `setActive()` is the only work.
        try await ensurePlaybackCategory()

        // Start playback
        guard player.play() else {
            throw AppError.audioPlaybackFailed(reason: "Failed to start playback")
        }

        self.isPlaying = true

        #if DEBUG
        AppLogger.debug("Playback started (duration: \(String(format: "%.2f", player.duration))s)", category: .audio)
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
        _immediatePlayerRef.withLock { $0 = nil }
        isPlaying = false

        if success {
            dataPlaybackContinuation?.resume(returning: ())
        } else {
            dataPlaybackContinuation?.resume(throwing: AppError.audioPlaybackFailed(reason: "Playback interrupted"))
        }
        dataPlaybackContinuation = nil
    }

    /// Immediately silences audio from any isolation context.
    ///
    /// Bypasses actor isolation to stop `AVAudioPlayer` synchronously,
    /// eliminating audible bleed when exiting sessions or transitioning.
    /// Zeros volume before stopping to silence any residual hardware
    /// buffer drain (~5-10ms on speaker, more on Bluetooth).
    ///
    /// `AVAudioPlayer.stop()` does **not** trigger delegate callbacks,
    /// so continuations remain pending until `cancelAndStop()` or `stop()`
    /// runs on the actor.
    ///
    /// - Note: Always follow with an actor-isolated `cancelAndStop()` call
    ///   to clean up continuations and internal state.
    nonisolated func immediateStop() {
        _immediatePlayerRef.withLock { player in
            player?.volume = 0
            player?.stop()
        }
    }

    /// Atomically silences audio, stops playback, and resolves all pending continuations.
    ///
    /// This is the authoritative cancellation method. Unlike the split
    /// `immediateStop()` + `stop()` pattern, this performs all cleanup in a
    /// single actor turn:
    /// 1. Zeros volume to silence hardware buffer drain
    /// 2. Stops all players (AVAudioPlayerNode + AVAudioPlayer)
    /// 3. Resumes pending continuations with `CancellationError` so callers
    ///    can distinguish cancellation from successful completion
    ///
    /// Use for:
    /// - Session exit (via `stopTTSPlayback()`)
    /// - Segment transitions (called internally by `playRawPCMData()`)
    ///
    /// - Note: Existing `stop()` is preserved for clean shutdown paths where
    ///   `resume(returning: ())` semantics are needed.
    func cancelAndStop() {
        // Zero volume BEFORE stop to silence hardware buffer drain
        dataPlayer?.volume = 0

        // Stop all playback
        playerNode.stop()
        dataPlayer?.stop()
        dataPlayer = nil
        dataPlayerDelegate = nil
        _immediatePlayerRef.withLock { $0 = nil }

        isPlaying = false
        isPaused = false
        currentAudioFile = nil

        // Resume continuations with CancellationError to unblock callers cleanly.
        // This lets the caller's try-await distinguish cancellation from success.
        playbackContinuation?.resume(throwing: CancellationError())
        playbackContinuation = nil

        dataPlaybackContinuation?.resume(throwing: CancellationError())
        dataPlaybackContinuation = nil
    }

    /// Stops playback and cleans up actor state.
    func stop() {
        // Stop AVAudioEngine playback
        playerNode.stop()

        // Stop AVAudioPlayer playback (for data/TTS)
        dataPlayer?.stop()
        dataPlayer = nil
        dataPlayerDelegate = nil
        _immediatePlayerRef.withLock { $0 = nil }

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

    // MARK: - Audio Session

    /// Ensures the audio session is in `.playback` category before playback.
    ///
    /// `SpeechCaptureService` sets the category to `.playAndRecord` during
    /// listening phases. If a rapid skip or loop transition interrupts
    /// listening, the category may still be `.playAndRecord` when the next
    /// segment needs to play TTS. `.playAndRecord` with `.measurement` mode
    /// doesn't route output correctly for non-recording playback, causing
    /// silent audio.
    ///
    /// The `setCategory()` call blocks for 50-200ms (HAL driver reconfiguration).
    /// By dispatching to a background queue and awaiting via continuation,
    /// the actor remains free during the reconfiguration. When the category
    /// is already `.playback`, only `setActive(true)` runs (~1-5ms).
    ///
    /// `SpeechCaptureService.stopCapture()/cancelCapture()` also fire a
    /// best-effort background restoration, but that dispatch is not awaited
    /// and may not complete before this method runs. This method is the
    /// definitive guarantee.
    private func ensurePlaybackCategory() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    if session.category != .playback {
                        #if DEBUG
                        AppLogger.debug("Restoring category from \(session.category.rawValue) to .playback (background)", category: .audio)
                        #endif
                        try session.setCategory(
                            .playback,
                            mode: .default,
                            options: [.duckOthers]
                        )
                    }
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AppError.audioPlaybackFailed(
                        reason: "Failed to configure audio session: \(error.localizedDescription)"
                    ))
                }
            }
        }
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
        AppLogger.warning("AudioPlayerCompletionDelegate: Decode error - \(error?.localizedDescription ?? "unknown")", category: .audio)
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
