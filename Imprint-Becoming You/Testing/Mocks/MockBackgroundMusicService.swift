//
//  MockBackgroundMusicService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import AVFoundation

// MARK: - MockBackgroundMusicService

/// Mock implementation of `BackgroundMusicServiceProtocol` for previews and testing.
///
/// Simulates music playback state without actual audio output.
@MainActor
final class MockBackgroundMusicService: BackgroundMusicServiceProtocol {

    // MARK: - State

    private(set) var isPlaying: Bool = false
    private(set) var currentCategory: MusicCategory?
    private(set) var volume: Float = Constants.Audio.backgroundMusicVolume
    private(set) var currentTrackIndex: Int = 0
    var currentTrackCount: Int { currentCategory?.trackCount ?? 0 }
    private(set) var playbackMode: MusicPlaybackMode = .repeatTrack

    // MARK: - BackgroundMusicServiceProtocol

    func attachTo(engine: AVAudioEngine) {
        // No-op for mock
    }

    func detachFrom(engine: AVAudioEngine) {
        stop()
    }

    func play(category: MusicCategory) {
        currentCategory = category
        isPlaying = true
    }

    func stop() {
        currentCategory = nil
        isPlaying = false
    }

    func pause() {
        isPlaying = false
    }

    func resume() {
        if currentCategory != nil {
            isPlaying = true
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
    }

    func rescheduleCurrentTrack() {
        // No-op for mock
    }

    func setPlaybackMode(_ mode: MusicPlaybackMode) {
        playbackMode = mode
    }

    func skipForward() {
        guard let category = currentCategory else { return }
        currentTrackIndex = (currentTrackIndex + 1) % category.trackCount
    }

    func skipBackward() {
        guard let category = currentCategory else { return }
        currentTrackIndex = (currentTrackIndex - 1 + category.trackCount) % category.trackCount
    }
}
