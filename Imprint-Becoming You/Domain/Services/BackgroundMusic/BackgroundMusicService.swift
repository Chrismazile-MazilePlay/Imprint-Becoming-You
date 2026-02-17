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

// MARK: - BackgroundMusicPlayerDelegate

/// Trampoline delegate for detecting track completion.
///
/// `BackgroundMusicService` is `@MainActor` and cannot directly conform to
/// `AVAudioPlayerDelegate` (which requires `NSObjectProtocol`). This lightweight
/// `NSObject` subclass forwards `audioPlayerDidFinishPlaying` back to the
/// service on `@MainActor`.
private final class BackgroundMusicPlayerDelegate: NSObject, AVAudioPlayerDelegate {

    /// Callback invoked when the track finishes playing.
    let onFinish: @MainActor @Sendable () -> Void

    init(onFinish: @MainActor @Sendable @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.onFinish()
        }
    }
}

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
/// ## Playback Modes
/// - **Repeat** (default): Single track loops infinitely via `numberOfLoops = -1`.
/// - **Shuffle**: Track plays once (`numberOfLoops = 0`), then
///   `BackgroundMusicPlayerDelegate` triggers auto-advance to a random
///   different track.
///
/// ## Track Navigation
/// Skip forward/backward respects the current playback mode:
/// - Repeat: Sequential order (wraps around).
/// - Shuffle: Random selection (forward) or history-based (backward).
///
/// ## Thread Safety
/// `@MainActor` isolated. All playback control and state mutation happens on main.
@MainActor
final class BackgroundMusicService: BackgroundMusicServiceProtocol {

    // MARK: - Properties

    /// The audio player for background music (independent of AVAudioEngine).
    private var audioPlayer: AVAudioPlayer?

    /// Delegate trampoline for track-finished detection (shuffle auto-advance).
    private var playerDelegate: BackgroundMusicPlayerDelegate?

    /// Whether background music is currently playing.
    private(set) var isPlaying: Bool = false

    /// The currently playing music category (`nil` if stopped).
    private(set) var currentCategory: MusicCategory?

    /// Current volume level (0.0–1.0).
    private(set) var volume: Float

    /// The current track index within the active category.
    private(set) var currentTrackIndex: Int = 0

    /// The total number of tracks in the current category (0 if stopped).
    var currentTrackCount: Int { currentCategory?.trackCount ?? 0 }

    /// The current playback mode.
    private(set) var playbackMode: MusicPlaybackMode = .repeatTrack

    // MARK: - Shuffle History

    /// History of played track indices for shuffle-back navigation.
    ///
    /// Each entry is the track index that was played. The most recent
    /// entry is at the end. Used by `skipBackward()` in shuffle mode
    /// to return to previously played tracks.
    private var trackHistory: [Int] = []

    /// Current position within `trackHistory`.
    ///
    /// Points to the currently playing track's position in history.
    /// `skipBackward()` decrements this; `skipForward()` increments
    /// (if not at the end, replays from history rather than picking new).
    private var historyPosition: Int = -1

    // MARK: - Initialization

    /// Creates a new BackgroundMusicService.
    ///
    /// - Parameter volume: Initial volume level (defaults to `Constants.Audio.backgroundMusicVolume`).
    init(volume: Float = Constants.Audio.backgroundMusicVolume) {
        self.volume = volume

        // Create the delegate once — it will be wired to players as needed
        self.playerDelegate = BackgroundMusicPlayerDelegate { [weak self] in
            self?.handleTrackFinished()
        }
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

    /// Starts playing a track from the given category.
    ///
    /// In repeat mode, plays track at index 0. In shuffle mode, plays a
    /// random track. Resets track history for the new category.
    /// - Parameter category: The music category to play.
    func play(category: MusicCategory) {
        // Stop any current playback
        stop()

        // Reset history for new category
        trackHistory = []
        historyPosition = -1

        // Pick starting track based on mode
        let startIndex: Int
        if playbackMode == .shuffle {
            startIndex = Int.random(in: 0..<category.trackCount)
        } else {
            startIndex = 0
        }

        playTrack(at: startIndex, in: category)
    }

    /// Stops playback and releases the current audio player.
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil
        currentCategory = nil
        currentTrackIndex = 0
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

    // MARK: - Playback Mode

    /// Sets the playback mode, updating the current player immediately.
    ///
    /// - Switching to `.repeatTrack`: Sets `numberOfLoops = -1` and removes delegate.
    /// - Switching to `.shuffle`: Sets `numberOfLoops = 0` and wires delegate
    ///   for auto-advance when the track finishes.
    /// - Parameter mode: The desired playback mode.
    func setPlaybackMode(_ mode: MusicPlaybackMode) {
        guard playbackMode != mode else { return }
        playbackMode = mode

        // Update the current player if one is active
        guard let player = audioPlayer else { return }

        switch mode {
        case .repeatTrack:
            player.numberOfLoops = -1
            player.delegate = nil
            musicLog.debug("Playback mode → repeat (numberOfLoops = -1)")

        case .shuffle:
            player.numberOfLoops = 0
            player.delegate = playerDelegate
            musicLog.debug("Playback mode → shuffle (numberOfLoops = 0, delegate wired)")
        }
    }

    // MARK: - Track Navigation

    /// Skips to the next track in the current category.
    ///
    /// - Repeat mode: Advances sequentially (wraps around via modular arithmetic).
    /// - Shuffle mode: Picks a random different track (avoids immediate repeat).
    ///   If navigating forward through existing history, replays that entry instead.
    func skipForward() {
        guard let category = currentCategory else { return }

        let nextIndex: Int

        switch playbackMode {
        case .repeatTrack:
            nextIndex = currentTrackIndex + 1 // playTrack wraps via trackFileName(at:)

        case .shuffle:
            // Check if we can move forward in existing history
            if historyPosition < trackHistory.count - 1 {
                historyPosition += 1
                nextIndex = trackHistory[historyPosition]
                playTrack(at: nextIndex, in: category, appendToHistory: false)
                return
            }
            // Pick a random different track
            nextIndex = randomDifferentIndex(excluding: currentTrackIndex, count: category.trackCount)
        }

        playTrack(at: nextIndex, in: category)
    }

    /// Skips to the previous track in the current category.
    ///
    /// - Repeat mode: Goes to previous sequential track (wraps around).
    /// - Shuffle mode: Returns to the previously played track from history.
    func skipBackward() {
        guard let category = currentCategory else { return }

        let prevIndex: Int

        switch playbackMode {
        case .repeatTrack:
            prevIndex = currentTrackIndex - 1 // playTrack wraps via trackFileName(at:)

        case .shuffle:
            // Go back in history if possible
            guard historyPosition > 0 else {
                // At the beginning of history — replay current track from start
                audioPlayer?.currentTime = 0
                audioPlayer?.play()
                isPlaying = true
                return
            }
            historyPosition -= 1
            prevIndex = trackHistory[historyPosition]
            playTrack(at: prevIndex, in: category, appendToHistory: false)
            return
        }

        playTrack(at: prevIndex, in: category)
    }

    // MARK: - Private Helpers

    /// Core track loading method.
    ///
    /// Loads a track from the bundle, configures `numberOfLoops` based on
    /// the current playback mode, sets volume, and starts playback.
    ///
    /// - Parameters:
    ///   - index: The track index (will be wrapped to valid range).
    ///   - category: The music category containing the track.
    ///   - appendToHistory: Whether to append this track to shuffle history.
    ///     Set to `false` when replaying from existing history entries.
    private func playTrack(at index: Int, in category: MusicCategory, appendToHistory: Bool = true) {
        // Stop current playback without clearing category/state
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil

        // Resolve the track filename (wraps index to valid range)
        let wrappedIndex = ((index % category.trackCount) + category.trackCount) % category.trackCount
        let fileName = category.trackFileName(at: wrappedIndex)
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

        // Configure based on playback mode
        switch playbackMode {
        case .repeatTrack:
            player.numberOfLoops = -1
            player.delegate = nil

        case .shuffle:
            player.numberOfLoops = 0
            player.delegate = playerDelegate
        }

        player.volume = volume
        player.prepareToPlay()

        // Start playback
        if player.play() {
            audioPlayer = player
            currentCategory = category
            currentTrackIndex = wrappedIndex
            isPlaying = true

            // Update shuffle history
            if appendToHistory {
                // Trim any forward history beyond current position
                if historyPosition < trackHistory.count - 1 {
                    trackHistory = Array(trackHistory.prefix(historyPosition + 1))
                }
                trackHistory.append(wrappedIndex)
                historyPosition = trackHistory.count - 1
            }

            musicLog.info("🎵 Playing: \(category.rawValue)/\(fileName) [index=\(wrappedIndex), mode=\(self.playbackMode.rawValue)]")
        } else {
            musicLog.error("❌ AVAudioPlayer.play() returned false for: \(fileName)")
        }
    }

    /// Picks a random track index different from the excluded one.
    ///
    /// For single-track categories (count == 1), returns the only index (0).
    /// - Parameters:
    ///   - excluding: The index to avoid repeating.
    ///   - count: Total number of tracks in the category.
    /// - Returns: A random index ≠ `excluding`, or `excluding` if only 1 track.
    private func randomDifferentIndex(excluding: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var next: Int
        repeat {
            next = Int.random(in: 0..<count)
        } while next == excluding
        return next
    }

    /// Handles track completion in shuffle mode.
    ///
    /// Called by `BackgroundMusicPlayerDelegate` when the current track
    /// finishes playing (only fires when `numberOfLoops = 0`).
    /// Picks a random different track and auto-advances.
    private func handleTrackFinished() {
        guard playbackMode == .shuffle, let category = currentCategory else { return }

        let nextIndex = randomDifferentIndex(excluding: currentTrackIndex, count: category.trackCount)
        musicLog.debug("Shuffle auto-advance: \(self.currentTrackIndex) → \(nextIndex)")
        playTrack(at: nextIndex, in: category)
    }
}
