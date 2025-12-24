//
//  DockState.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - DockState

/// Represents the current state of the adaptive bottom dock.
///
/// The dock morphs its appearance and controls based on the current
/// practice mode and phase within that mode.
///
/// ## States
/// - **Home**: Browse mode, minimal dock with just mode/binaural selectors
/// - **Read Aloud**: TTS is playing, shows waveform and progress
/// - **Read & Speak**: TTS then user speaks, full interaction flow
/// - **Speak Only**: User speaks without TTS prompt
///
/// ## Usage
/// ```swift
/// let state: DockState = .readAndSpeak(phase: .listening)
/// print(state.sessionMode)  // .readThenSpeak
/// print(state.isActiveMode) // true
/// ```
enum DockState: Equatable, Sendable {
    /// Home state - user is browsing in Read Only mode
    case home
    
    /// Read Aloud mode - TTS is playing
    case readAloud(phase: TTSPhase)
    
    /// Read & Speak mode - TTS then user speaks
    case readAndSpeak(phase: ReadAndSpeakPhase)
    
    /// Speak Only mode - user speaks without TTS
    case speakOnly(phase: SpeakPhase)
    
    // MARK: - Computed Properties
    
    /// Whether this is the home/browse state
    var isHome: Bool {
        if case .home = self { return true }
        return false
    }
    
    /// Whether this is an active session mode (not home)
    var isActiveMode: Bool {
        !isHome
    }
    
    /// The session mode this state represents
    var sessionMode: SessionMode {
        switch self {
        case .home:
            return .readOnly
        case .readAloud:
            return .readAloud
        case .readAndSpeak:
            return .readThenSpeak
        case .speakOnly:
            return .speakOnly
        }
    }
    
    /// Human-readable description of current state
    var description: String {
        switch self {
        case .home:
            return "Home"
        case .readAloud(let phase):
            return "Read Aloud - \(phase)"
        case .readAndSpeak(let phase):
            return "Read & Speak - \(phase)"
        case .speakOnly(let phase):
            return "Speak Only - \(phase)"
        }
    }
}
