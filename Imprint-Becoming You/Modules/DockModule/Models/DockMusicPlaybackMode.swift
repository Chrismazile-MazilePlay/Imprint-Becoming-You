//
//  DockMusicPlaybackMode.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/16/26.
//

import Foundation

// MARK: - DockMusicPlaybackMode

/// Playback mode for the dock music transport controls.
///
/// Mirrors ``MusicPlaybackMode`` at the dock module boundary.
/// The adapter maps between this type and the domain type.
public enum DockMusicPlaybackMode: Equatable, Sendable {
    /// Loops the current track infinitely (default).
    case repeatTrack

    /// Plays a random different track when the current one finishes.
    case shuffle
}
