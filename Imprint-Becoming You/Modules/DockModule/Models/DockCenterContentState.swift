//
//  DockCenterContentState.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import Foundation

// MARK: - DockCenterContentState

/// States for the center content slot in session configuration.
///
/// This enum drives the visualization shown in the center area of the dock
/// during active sessions. The dock's center content view is fully decoupled
/// from practice flows — it only knows about these visualization states.
///
/// ## State Transitions
///
/// ```
/// idle → playing(audioLevel) → preparing → listening(audioLevel) → idle
///   ↑                                                                │
///   └────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Visual States
///
/// | State                    | Visual                    | Color         |
/// |--------------------------|---------------------------|---------------|
/// | `hidden`                 | Nothing                   | N/A           |
/// | `idle`                   | ● ● ● ● ● ● ● ● ●         | tertiary      |
/// | `playing(audioLevel)`    | Animated bars             | accent        |
/// | `preparing`              | Gentle breathing          | success/green |
/// | `listening(audioLevel)`  | Animated bars             | success/green |
/// | `settling`               | Shrinking bars → dots     | tertiary      |
///
/// ## Waveform Design Principles
///
/// The waveform visualization is:
/// - **Decoupled**: Knows nothing about TTS callbacks or session modes
/// - **Single Instance**: One waveform view handles all states
/// - **Responsive**: Reacts to state changes with smooth animations
/// - **Continuous**: Transitions smoothly between states
///
/// The adapter is responsible for mapping TTS callbacks and session state
/// to the appropriate `DockCenterContentState` value.
///
/// ## Mapping from Practice Flows
///
/// ```swift
/// // Example adapter mapping
/// func mapFlowToCenterContentState(_ flow: PracticeFlow) -> DockCenterContentState {
///     switch flow {
///     case .home:
///         return .hidden
///     case .readAloud(let phase):
///         switch phase {
///         case .idle, .complete: return .idle
///         case .playing: return .playing(audioLevel: currentAudioLevel)
///         }
///     case .readAndSpeak(let phase):
///         switch phase {
///         case .idle: return .idle
///         case .ttsPlaying: return .playing(audioLevel: currentAudioLevel)
///         case .preparingToListen: return .preparing
///         case .listening(let ctx): return .listening(audioLevel: ctx.audioLevel)
///         case .celebrating: return .idle
///         }
///     // ... etc
///     }
/// }
/// ```
public enum DockCenterContentState: Equatable, Sendable {
    
    /// No content — the center slot is hidden or not applicable.
    ///
    /// Used when:
    /// - Configuration is `.home` or `.configuration`
    /// - Session mode is Read Only
    case hidden
    
    /// Idle waveform — small dots, no animation.
    ///
    /// Visual: ● ● ● ● ● ● ● ● ●
    ///
    /// Used when:
    /// - Session is active but waiting to start
    /// - Between actions in a practice cycle
    case idle
    
    /// TTS playback — animated waveform bars in accent color.
    ///
    /// Visual: Bars animate based on audio level
    /// Color: Accent (amber/gold)
    ///
    /// - Parameter audioLevel: Current audio output level (0.0–1.0)
    case playing(audioLevel: CGFloat)
    
    /// Preparing to listen — gentle breathing animation in green.
    ///
    /// Visual: Gentle breathing/pulsing bars
    /// Color: Success (green)
    ///
    /// Used when:
    /// - Speech recognition engine is initializing
    /// - Audio session is being configured
    /// - Brief transition between TTS and listening
    ///
    /// This state ensures the UI reflects "getting ready to listen"
    /// while heavy audio initialization happens off the main thread.
    case preparing
    
    /// Microphone input — animated waveform bars in success/green color.
    ///
    /// Visual: Bars animate based on voice input level
    /// Color: Success (green)
    ///
    /// - Parameter audioLevel: Current microphone input level (0.0–1.0)
    case listening(audioLevel: CGFloat)
    
    /// Transitioning back to idle — bars shrinking to dots.
    ///
    /// Visual: Animated transition from bars back to small dots
    /// Color: Tertiary (gray)
    ///
    /// Used when:
    /// - Brief transition after listening completes
    case settling
}

// MARK: - Convenience Properties

public extension DockCenterContentState {
    
    /// Whether this state represents an active audio visualization.
    ///
    /// Returns `true` for states that show animated waveform bars.
    var isAnimatingWaveform: Bool {
        switch self {
        case .playing, .listening:
            return true
        case .hidden, .idle, .preparing, .settling:
            return false
        }
    }
    
    /// Whether this state should be visible.
    ///
    /// Returns `false` only for `.hidden`.
    var isVisible: Bool {
        self != .hidden
    }
    
    /// The audio level if this state includes one, otherwise `nil`.
    var audioLevel: CGFloat? {
        switch self {
        case .playing(let level), .listening(let level):
            return level
        default:
            return nil
        }
    }
    
    /// Whether this state represents user input (listening).
    ///
    /// Used to determine waveform color (green for listening, accent for playing).
    /// Note: `.preparing` is NOT considered user input — the mic isn't active yet.
    var isUserInput: Bool {
        if case .listening = self {
            return true
        }
        return false
    }
    
    /// Whether this state indicates the system is preparing for listening.
    ///
    /// Used to show the "Listening" chip should NOT be visible yet.
    var isPreparing: Bool {
        if case .preparing = self {
            return true
        }
        return false
    }
}
