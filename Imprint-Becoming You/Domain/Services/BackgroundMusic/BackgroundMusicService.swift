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
/// Uses a single `AVAudioPlayerNode` attached to the shared `AVAudioEngine`.
/// Tracks are loaded from the app bundle and loop seamlessly via
/// reschedule-on-completion.
///
/// ## Audio Graph Position
/// ```
/// BackgroundMusicService
/// └── musicPlayerNode (volume: 0.15) → engine.mainMixerNode
/// ```
///
/// ## Looping Mechanism
/// All bundled tracks have 2-second fade-in/out edges baked in.
/// On playback completion, the track is immediately rescheduled,
/// creating a continuous loop. At 15% volume, the loop point is inaudible.
///
/// ## Thread Safety
/// `@MainActor` isolated. All scheduling and state mutation happens on main.
@MainActor
final class BackgroundMusicService: BackgroundMusicServiceProtocol {

    // MARK: - Properties

    /// The dedicated player node for background music.
    private let musicPlayerNode: AVAudioPlayerNode

    /// Currently loaded audio file (released on `stop()`).
    private var currentAudioFile: AVAudioFile?

    /// Weak reference to the engine this service is attached to.
    private weak var attachedEngine: AVAudioEngine?

    /// Whether background music is currently playing.
    private(set) var isPlaying: Bool = false

    /// The currently playing music category (`nil` if stopped).
    private(set) var currentCategory: MusicCategory?

    /// Current volume level (0.0–1.0).
    private(set) var volume: Float

    /// Whether the looping reschedule callback should continue.
    private var shouldLoop: Bool = false

    // MARK: - Initialization

    /// Creates a new BackgroundMusicService.
    ///
    /// - Parameter volume: Initial volume level (defaults to `Constants.Audio.backgroundMusicVolume`).
    init(volume: Float = Constants.Audio.backgroundMusicVolume) {
        self.musicPlayerNode = AVAudioPlayerNode()
        self.volume = volume
    }

    // MARK: - Engine Attachment

    /// Attaches the music player node to the audio engine.
    ///
    /// Connects to the engine's `mainMixerNode` using the standard stereo format.
    /// - Parameter engine: The shared `AVAudioEngine`.
    func attachTo(engine: AVAudioEngine) {
        engine.attach(musicPlayerNode)

        let format = AVAudioFormat(
            standardFormatWithSampleRate: Constants.Audio.sampleRate,
            channels: 2
        )!
        engine.connect(musicPlayerNode, to: engine.mainMixerNode, format: format)

        attachedEngine = engine
        musicPlayerNode.volume = volume

        musicLog.info("✅ BackgroundMusicService attached to engine")
    }

    /// Detaches the music player node from the audio engine.
    ///
    /// Stops playback first, then removes the node from the graph.
    /// - Parameter engine: The shared `AVAudioEngine`.
    func detachFrom(engine: AVAudioEngine) {
        stop()
        engine.detach(musicPlayerNode)
        attachedEngine = nil

        musicLog.info("BackgroundMusicService detached from engine")
    }

    // MARK: - Playback

    /// Starts playing a random track from the given category.
    ///
    /// If already playing, stops the current track first.
    /// The track loops seamlessly via reschedule-on-completion.
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

        // Load audio file
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            musicLog.error("❌ Failed to load audio file: \(error.localizedDescription)")
            return
        }

        currentAudioFile = audioFile
        currentCategory = category
        shouldLoop = true

        // Reconnect with correct format from the audio file
        if let engine = attachedEngine {
            engine.disconnectNodeOutput(musicPlayerNode)
            engine.connect(musicPlayerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)
        }

        // Apply volume and start
        musicPlayerNode.volume = volume
        scheduleAndPlay()

        musicLog.info("🎵 Playing: \(category.rawValue)/\(fileName)")
    }

    /// Stops playback and releases the current audio file.
    func stop() {
        shouldLoop = false
        musicPlayerNode.stop()
        currentAudioFile = nil
        currentCategory = nil
        isPlaying = false
    }

    /// Pauses playback (retains position for resume).
    func pause() {
        guard isPlaying else { return }
        musicPlayerNode.pause()
        isPlaying = false
    }

    /// Resumes paused playback.
    func resume() {
        guard !isPlaying, currentAudioFile != nil else { return }
        musicPlayerNode.play()
        isPlaying = true
    }

    /// Sets the playback volume.
    ///
    /// - Parameter newVolume: Volume level (0.0–1.0). Clamped to valid range.
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        musicPlayerNode.volume = volume
    }

    // MARK: - Reschedule

    /// Reschedules the current track from the beginning.
    ///
    /// Called after an engine full-stop/restart (e.g., recording category
    /// transition) which discards all scheduled audio buffers. Re-reads the
    /// current audio file URL and schedules it for looping playback.
    ///
    /// At 15% volume with baked-in fade edges, the brief silence during
    /// engine restart is inaudible.
    func rescheduleCurrentTrack() {
        guard shouldLoop, let audioFile = currentAudioFile else { return }

        // Re-read the file to reset the read position
        guard let freshFile = try? AVAudioFile(forReading: audioFile.url) else {
            musicLog.error("❌ Failed to re-read audio file for reschedule")
            return
        }

        currentAudioFile = freshFile

        // Reconnect with correct format
        if let engine = attachedEngine {
            engine.disconnectNodeOutput(musicPlayerNode)
            engine.connect(musicPlayerNode, to: engine.mainMixerNode, format: freshFile.processingFormat)
        }

        musicPlayerNode.volume = volume
        scheduleAndPlay()

        musicLog.info("🔄 Rescheduled current track after engine restart")
    }

    // MARK: - Private

    /// Schedules the current audio file for playback with loop-on-completion.
    ///
    /// When the track finishes, the completion callback re-reads the file
    /// from disk and reschedules it. This creates seamless looping since
    /// all tracks have 2-second fade-in/out edges baked in.
    private func scheduleAndPlay() {
        guard let audioFile = currentAudioFile, shouldLoop else { return }

        musicPlayerNode.scheduleFile(
            audioFile,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.shouldLoop else { return }
                // Re-read the file to reset the read position for the next loop
                self.currentAudioFile = try? AVAudioFile(forReading: audioFile.url)
                self.scheduleAndPlay()
            }
        }

        if !isPlaying {
            musicPlayerNode.play()
            isPlaying = true
        }
    }
}
