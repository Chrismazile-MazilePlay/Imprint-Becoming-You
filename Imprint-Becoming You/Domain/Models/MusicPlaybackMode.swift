//
//  MusicPlaybackMode.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/16/26.
//

import Foundation

// MARK: - MusicPlaybackMode

/// Controls how background music advances between tracks.
///
/// - ``repeatTrack``: The current track loops infinitely (default).
///   Uses `AVAudioPlayer.numberOfLoops = -1`.
/// - ``shuffle``: When the current track finishes, a random different
///   track from the same category plays next. Uses delegate-based
///   auto-advance with `numberOfLoops = 0`.
enum MusicPlaybackMode: String, Sendable {
    /// Loops the current track infinitely.
    case repeatTrack

    /// Plays a random different track when the current one finishes.
    case shuffle
}
