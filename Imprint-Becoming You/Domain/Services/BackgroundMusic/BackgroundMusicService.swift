//
//  BackgroundMusicService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import AVFoundation
import os.log

// MARK: - Logger

private let musicLog = Logger(subsystem: "com.imprint.audio", category: "BackgroundMusic")

// MARK: - BackgroundMusicService

/// Plays looping background music during practice sessions.
///
/// Uses `AVAudioPlayer` for playback, which operates independently of
/// `AVAudioEngine`. This decoupled architecture prevents audio glitches
/// (static/pops) caused by engine reconfiguration events such as iOS
/// screenshot shutter sounds, system alerts, or audio route changes.
///
/// ## Why AVAudioPlayer (not AVAudioPlayerNode)?
/// `AVAudioPlayerNode` attaches to the `AVAudioEngine` graph. When iOS
/// triggers a system sound (e.g., screenshot shutter), the engine's
/// hardware I/O unit reconfigures, causing audible artifacts on any
/// `AVAudioPlayerNode`. `AVAudioPlayer` has its own internal buffering
/// and is not coupled to the engine graph, making it immune to these
/// disruptions.
///
/// ## Protocol Compatibility
/// `attachTo(engine:)`, `detachFrom(engine:)`, and `rescheduleCurrentTrack()`
/// are no-ops — they exist to satisfy `BackgroundMusicServiceProtocol` and
/// are still called by `AudioService`, but background music no longer
/// touches the engine.
///
/// ## Looping
/// `AVAudioPlayer` supports native infinite looping via `numberOfLoops = -1`.
/// All bundled tracks have 2-second fade-in/out edges baked in, so the
/// loop point is seamless at the default volume.
///
/// ## Thread Safety
/// `@MainActor` isolated. All playback control and state mutation happens on main.
@MainActor
final class BackgroundMusicService: BackgroundMusicServiceProtocol {

    // MARK: - Properties

    /// The audio player for background music (independent of AVAudioEngine).
    private var audioPlayer: AVAudioPlayer?

    /// Whether background music is currently playing.
    private(set) var isPlaying: Bool = false

    /// The currently playing music category (`nil` if stopped).
    private(set) var currentCategory: MusicCategory?

    /// Current volume level (0.0–1.0).
    private(set) var volume: Float

    // MARK: - Initialization

    /// Creates a new BackgroundMusicService.
    ///
    /// - Parameter volume: Initial volume level (defaults to `Constants.Audio.backgroundMusicVolume`).
    init(volume: Float = Constants.Audio.backgroundMusicVolume) {
        self.volume = volume
    }

    // MARK: - Engine Attachment (No-Ops)

    /// No-op. Background music uses `AVAudioPlayer` (not attached to engine).
    ///
    /// Retained for `BackgroundMusicServiceProtocol` conformance. Called by
    /// `AudioService.start()` but does nothing.
    /// - Parameter engine: Ignored.
    func attachTo(engine: AVAudioEngine) {
        musicLog.debug("attachTo(engine:) called — no-op (uses AVAudioPlayer)")
    }

    /// Stops playback when the engine is being torn down.
    ///
    /// Although background music is not attached to the engine, stopping
    /// playback here preserves the original contract: when `AudioService.stop()`
    /// calls `detachFrom(engine:)`, music should stop.
    /// - Parameter engine: Ignored.
    func detachFrom(engine: AVAudioEngine) {
        stop()
        musicLog.debug("detachFrom(engine:) called — stopped playback")
    }

    // MARK: - Playback

    /// Starts playing a random track from the given category, looping continuously.
    ///
    /// If already playing, stops the current track first.
    /// Uses `AVAudioPlayer` with `numberOfLoops = -1` for seamless infinite looping.
    /// - Parameter category: The music category to play.
    func play(category: MusicCategory) {
        // Stop any current playback
        stop()

        // Pick a random track from the category
        let fileName = category.randomTrackFileName()
        let fileNameWithoutExtension = fileName.replacingOccurrences(of: ".mp3", with: "")

        guard let url = Bundle.main.url(
            forResource: fileNameWithoutExtension,
            withExtension: "mp3",
            subdirectory: category.subdirectory
        ) else {
            musicLog.error("❌ Track not found: \(category.subdirectory)/\(fileName)")
            return
        }

        // Create AVAudioPlayer
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            musicLog.error("❌ Failed to create audio player: \(error.localizedDescription)")
            return
        }

        // Configure for infinite looping
        player.numberOfLoops = -1
        player.volume = volume
        player.prepareToPlay()

        // Start playback
        if player.play() {
            audioPlayer = player
            currentCategory = category
            isPlaying = true
            musicLog.info("🎵 Playing: \(category.rawValue)/\(fileName)")
        } else {
            musicLog.error("❌ AVAudioPlayer.play() returned false for: \(fileName)")
        }
    }

    /// Stops playback and releases the current audio player.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentCategory = nil
        isPlaying = false
    }

    /// Pauses playback (retains position for resume).
    func pause() {
        guard isPlaying else { return }
        audioPlayer?.pause()
        isPlaying = false
    }

    /// Resumes paused playback.
    func resume() {
        guard !isPlaying, audioPlayer != nil else { return }
        audioPlayer?.play()
        isPlaying = true
    }

    /// Sets the playback volume.
    ///
    /// - Parameter newVolume: Volume level (0.0–1.0). Clamped to valid range.
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        audioPlayer?.volume = volume
    }

    // MARK: - Reschedule (No-Op)

    /// No-op. `AVAudioPlayer` handles its own playback lifecycle.
    ///
    /// Retained for `BackgroundMusicServiceProtocol` conformance. Called by
    /// `AudioService` via `onEngineRestarted`, but `AVAudioPlayer` is not
    /// affected by engine restarts — it continues playing independently.
    func rescheduleCurrentTrack() {
        musicLog.debug("rescheduleCurrentTrack() called — no-op (AVAudioPlayer is engine-independent)")
    }
}
