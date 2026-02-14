//
//  AudioPlayerService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import os

// MARK: - AudioPlayerService

/// Plays audio through AVAudioEngine using AVAudioPlayerNode.
///
/// All audio — both TTS (Kokoro PCM) and cached files — is routed through the
/// shared `AVAudioEngine` via `AVAudioPlayerNode`. This eliminates the
/// dual-render-client contention (AVAudioPlayer vs AVAudioEngine) that caused
/// static/glitch on the first TTS playback when background music was playing.
///
/// ## Architecture
/// ```
/// Kokoro TTS (24000 Hz mono Float32)
///     → AVAudioPCMBuffer
///     → playerNode.scheduleBuffer()
///     → mainMixerNode (auto sample-rate conversion)
///     → outputNode → Hardware
/// ```
///
/// ## Usage
/// ```swift
/// let player = AudioPlayerService()
/// player.attachTo(engine: audioEngine)
/// try await player.playRawPCMData(kokoroData, sampleRate: 24000)
/// ```
actor AudioPlayerService: AudioPlayerServiceProtocol {

    // MARK: - Properties

    /// Player node for audio playback (TTS + files)
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

    /// Continuation for playback completion (file path)
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    /// Continuation for PCM data playback completion
    private var dataPlaybackContinuation: CheckedContinuation<Void, Error>?

    /// Reference to attached engine
    private weak var attachedEngine: AVAudioEngine?

    /// Cache manager for file access
    private let cacheManager: AudioCacheManager

    /// The format currently connected on the playerNode output.
    /// Tracked to avoid unnecessary disconnect/reconnect cycles.
    private var currentConnectionFormat: AVAudioFormat?

    /// Total frame count of the currently scheduled PCM buffer (for progress).
    private var scheduledFrameCount: AVAudioFrameCount = 0

    /// Thread-safe reference to the player node for synchronous cross-isolation stop.
    ///
    /// `AVAudioPlayerNode` is safe to call `volume`/`stop()` from any thread.
    /// This lock provides the actor-isolation bridge so `nonisolated immediateStop()`
    /// can silence the node synchronously without waiting for actor scheduling.
    ///
    /// Initialized with the playerNode at actor init; cleared to nil is NOT needed
    /// because the same node is reused. The `isActive` flag inside controls behavior.
    private let _immediateNodeRef: OSAllocatedUnfairLock<(node: AVAudioPlayerNode, isActive: Bool)>

    // MARK: - Initialization

    /// Creates a new audio player service
    /// - Parameter cacheManager: The cache manager to use for file access
    init(cacheManager: AudioCacheManager = .shared) {
        let node = AVAudioPlayerNode()
        self.playerNode = node
        self.cacheManager = cacheManager
        self._immediateNodeRef = OSAllocatedUnfairLock(initialState: (node: node, isActive: false))
    }

    // MARK: - Engine Attachment

    /// Attaches the player to an audio engine.
    ///
    /// Connects with the Kokoro TTS native format (24000 Hz, mono, Float32)
    /// since that's the primary playback format. The mixer handles sample rate
    /// conversion to the hardware output rate automatically.
    ///
    /// - Parameter engine: The audio engine to attach to
    func attachTo(engine: AVAudioEngine) {
        engine.attach(playerNode)

        // Connect with Kokoro's native format — the mixer auto-converts
        // to the hardware output rate (44100/48000 Hz).
        let ttsFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
        engine.connect(playerNode, to: engine.mainMixerNode, format: ttsFormat)
        currentConnectionFormat = ttsFormat

        attachedEngine = engine
    }

    /// Detaches from the audio engine
    func detachFrom(engine: AVAudioEngine) {
        stop()
        engine.detach(playerNode)
        attachedEngine = nil
        currentConnectionFormat = nil
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
        reconnectIfNeeded(format: audioFile.processingFormat)

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
        _immediateNodeRef.withLock { $0.isActive = true }
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

    /// Plays raw PCM audio data through the engine's AVAudioPlayerNode.
    ///
    /// Converts Kokoro TTS output (WAV `Data`) into an `AVAudioPCMBuffer` and
    /// schedules it on the player node. The engine's mixer handles sample rate
    /// conversion from 24000 Hz to the hardware output rate automatically.
    ///
    /// **This is the unified playback path.** All TTS audio flows through the
    /// same `AVAudioEngine` as background music — one render client, zero
    /// contention, zero static.
    ///
    /// - Parameters:
    ///   - data: Audio data (WAV format from Kokoro TTS)
    ///   - sampleRate: Expected sample rate (used for validation logging only)
    /// - Throws: `AppError.audioPlaybackFailed` if playback fails
    func playRawPCMData(_ data: Data, sampleRate: Double = 24000) async throws {
        // Stop any in-progress playback cleanly. Uses stop() which resumes
        // continuations with success — the previous caller completes normally
        // rather than receiving a CancellationError.
        stop()

        guard !data.isEmpty else {
            throw AppError.audioPlaybackFailed(reason: "No audio data to play")
        }

        guard let engine = attachedEngine, engine.isRunning else {
            throw AppError.audioPlaybackFailed(reason: "Audio engine not running — cannot play TTS")
        }

        #if DEBUG
        AppLogger.debug("Playing \(data.count) bytes via AVAudioPlayerNode", category: .audio)
        #endif

        // Parse WAV data into an AVAudioPCMBuffer.
        // Kokoro outputs: 24000 Hz, mono, Float32 PCM wrapped in a WAV container.
        let pcmBuffer: AVAudioPCMBuffer
        do {
            pcmBuffer = try Self.createPCMBuffer(from: data)
        } catch {
            throw AppError.audioPlaybackFailed(reason: "Failed to parse WAV data: \(error.localizedDescription)")
        }

        // Reconnect the player node if the buffer format differs from current connection.
        // This handles edge cases like file playback (44100 Hz stereo) followed by
        // TTS playback (24000 Hz mono), or vice versa.
        reconnectIfNeeded(format: pcmBuffer.format)

        // Store frame count for progress tracking
        scheduledFrameCount = pcmBuffer.frameLength

        // Schedule the buffer with a completion callback
        playerNode.scheduleBuffer(pcmBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task {
                await self?.handleDataPlaybackComplete(success: true)
            }
        }

        // Apply volume and start playback
        playerNode.volume = volume
        playerNode.play()
        _immediateNodeRef.withLock { $0.isActive = true }
        isPlaying = true

        // Ensure the audio session is in .playback category.
        // SpeechCaptureService may have changed it to .playAndRecord.
        // This is non-blocking when already in .playback (fast path).
        try await ensurePlaybackCategory()

        #if DEBUG
        let durationSec = Double(pcmBuffer.frameLength) / pcmBuffer.format.sampleRate
        AppLogger.debug("PCM buffer scheduled (duration: \(String(format: "%.2f", durationSec))s, frames: \(pcmBuffer.frameLength))", category: .audio)
        #endif

        // Wait for completion using continuation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.dataPlaybackContinuation = continuation
        }
    }

    /// Handles completion of PCM data playback (called from schedule callback)
    private func handleDataPlaybackComplete(success: Bool) {
        _immediateNodeRef.withLock { $0.isActive = false }
        isPlaying = false
        scheduledFrameCount = 0

        if success {
            dataPlaybackContinuation?.resume(returning: ())
        } else {
            dataPlaybackContinuation?.resume(throwing: AppError.audioPlaybackFailed(reason: "Playback interrupted"))
        }
        dataPlaybackContinuation = nil
    }

    /// Immediately silences the player node from any isolation context.
    ///
    /// Bypasses actor isolation to stop the `AVAudioPlayerNode` synchronously,
    /// eliminating audible bleed when exiting sessions or transitioning.
    /// Zeros volume before stopping to silence any residual hardware
    /// buffer drain (~5-10ms on speaker, more on Bluetooth).
    ///
    /// `playerNode.stop()` clears all scheduled buffers but does **not**
    /// trigger schedule completion callbacks, so continuations remain pending
    /// until `cancelAndStop()` or `stop()` runs on the actor.
    ///
    /// - Note: Always follow with an actor-isolated `cancelAndStop()` call
    ///   to clean up continuations and internal state.
    nonisolated func immediateStop() {
        _immediateNodeRef.withLock { state in
            guard state.isActive else { return }
            // AVAudioPlayerNode.volume/stop() are thread-safe for cross-thread access.
            state.node.volume = 0
            state.node.stop()
            state.isActive = false
        }
    }

    /// Atomically silences audio, stops playback, and resolves all pending continuations.
    ///
    /// This is the authoritative cancellation method. Unlike the split
    /// `immediateStop()` + `stop()` pattern, this performs all cleanup in a
    /// single actor turn:
    /// 1. Zeros volume to silence hardware buffer drain
    /// 2. Stops player node (clears all scheduled buffers)
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
        playerNode.volume = 0

        // Stop all playback
        playerNode.stop()
        _immediateNodeRef.withLock { $0.isActive = false }

        isPlaying = false
        isPaused = false
        currentAudioFile = nil
        scheduledFrameCount = 0

        // Resume continuations with CancellationError to unblock callers cleanly.
        // This lets the caller's try-await distinguish cancellation from success.
        playbackContinuation?.resume(throwing: CancellationError())
        playbackContinuation = nil

        dataPlaybackContinuation?.resume(throwing: CancellationError())
        dataPlaybackContinuation = nil
    }

    /// Stops playback and cleans up actor state.
    func stop() {
        // Stop player node
        playerNode.stop()
        _immediateNodeRef.withLock { $0.isActive = false }

        isPlaying = false
        isPaused = false
        currentAudioFile = nil
        scheduledFrameCount = 0

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
    /// is already `.playback`, the fast path returns immediately (~0ms).
    private func ensurePlaybackCategory() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                // Fast path: when already in .playback (e.g., background music
                // activated the session), skip entirely to avoid redundant HAL work.
                guard session.category != .playback else {
                    continuation.resume()
                    return
                }
                do {
                    #if DEBUG
                    AppLogger.debug("Restoring category from \(session.category.rawValue) to .playback (background)", category: .audio)
                    #endif
                    try session.setCategory(
                        .playback,
                        mode: .default,
                        options: [.mixWithOthers]
                    )
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
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    /// Total duration of current audio in seconds
    var duration: TimeInterval {
        // For file playback
        if let audioFile = currentAudioFile {
            return Double(audioFile.length) / audioFile.processingFormat.sampleRate
        }
        // For PCM buffer playback
        if scheduledFrameCount > 0, let format = currentConnectionFormat {
            return Double(scheduledFrameCount) / format.sampleRate
        }
        return 0
    }

    /// Playback progress (0.0 - 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Private Methods

    /// Handles file playback completion
    private func handlePlaybackComplete() {
        _immediateNodeRef.withLock { $0.isActive = false }
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

    /// Reconnects the player node to the mixer if the format has changed.
    ///
    /// Avoids unnecessary `disconnectNodeOutput` / `connect` cycles which
    /// disrupt the audio graph. Only reconnects when the sample rate or
    /// channel count actually differs from the current connection.
    private func reconnectIfNeeded(format: AVAudioFormat) {
        guard let engine = attachedEngine else { return }

        // Check if reconnection is actually needed
        if let current = currentConnectionFormat,
           current.sampleRate == format.sampleRate,
           current.channelCount == format.channelCount {
            return
        }

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        currentConnectionFormat = format
    }

    /// Parses WAV `Data` into an `AVAudioPCMBuffer` for scheduling on the player node.
    ///
    /// Kokoro TTS outputs WAV files with a standard 44-byte header followed by
    /// raw Float32 PCM samples at 24000 Hz, mono. This method reads the header
    /// to determine format and frame count, then copies the sample data into
    /// an `AVAudioPCMBuffer`.
    ///
    /// - Parameter data: WAV audio data (header + PCM samples)
    /// - Returns: An `AVAudioPCMBuffer` ready for `scheduleBuffer()`
    /// - Throws: If the WAV header is invalid or the data is malformed
    private static func createPCMBuffer(from data: Data) throws -> AVAudioPCMBuffer {
        // Write to a temporary file so AVAudioFile can parse the WAV container.
        // This handles all WAV variants (16-bit int, 32-bit float, etc.) correctly
        // and lets Core Audio handle the format negotiation.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try data.write(to: tempURL, options: .atomic)

        let audioFile = try AVAudioFile(forReading: tempURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw AppError.audioPlaybackFailed(reason: "WAV file has zero frames")
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AppError.audioPlaybackFailed(reason: "Failed to create PCM buffer (format: \(format))")
        }

        try audioFile.read(into: buffer)

        return buffer
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
