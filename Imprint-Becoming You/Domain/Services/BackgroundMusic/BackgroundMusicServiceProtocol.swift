//
//  BackgroundMusicServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import AVFoundation

// MARK: - BackgroundMusicServiceProtocol

/// Protocol for background music playback during practice sessions.
///
/// Background music plays at low volume (default 15%) behind TTS affirmation
/// audio. Tracks loop seamlessly using baked-in fade edges.
///
/// All methods are `@MainActor` because:
/// 1. Playback state (`isPlaying`, `currentCategory`) drives UI
/// 2. Called from `@MainActor`-isolated `AudioService` and `PracticeStore`
/// 3. AVAudioPlayerNode scheduling must happen on a consistent actor
@MainActor
protocol BackgroundMusicServiceProtocol: AnyObject {

    /// Whether background music is currently playing.
    var isPlaying: Bool { get }

    /// The currently playing music category (`nil` if stopped).
    var currentCategory: MusicCategory? { get }

    /// Current volume level (0.0–1.0).
    var volume: Float { get }

    /// Attaches the music player node to the audio engine.
    ///
    /// Must be called before `play()`. Connects the internal
    /// `AVAudioPlayerNode` to the engine's `mainMixerNode`.
    /// - Parameter engine: The shared `AVAudioEngine`.
    func attachTo(engine: AVAudioEngine)

    /// Detaches the music player node from the audio engine.
    ///
    /// Stops playback and removes the node from the engine graph.
    /// - Parameter engine: The shared `AVAudioEngine`.
    func detachFrom(engine: AVAudioEngine)

    /// Starts playing a random track from the given category, looping continuously.
    ///
    /// If already playing, stops the current track and starts the new one.
    /// - Parameter category: The music category to play.
    func play(category: MusicCategory)

    /// Stops playback and releases the current audio file.
    func stop()

    /// Pauses playback (retains position for resume).
    func pause()

    /// Resumes paused playback.
    func resume()

    /// Sets the playback volume.
    ///
    /// - Parameter newVolume: Volume level (0.0–1.0). Clamped to valid range.
    func setVolume(_ newVolume: Float)

    /// Reschedules the current track from the beginning.
    ///
    /// Called after an engine full-stop/restart (e.g., recording category
    /// transition) which discards all scheduled audio buffers. Re-reads the
    /// current audio file and schedules it for looping playback.
    ///
    /// Does nothing if no track is currently loaded.
    func rescheduleCurrentTrack()
}
