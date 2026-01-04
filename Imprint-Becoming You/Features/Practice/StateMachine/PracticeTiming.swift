//
//  PracticeTiming.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/3/26.
//

import Foundation

// MARK: - Practice Timing

/// Centralized timing configuration for the practice experience.
///
/// All durations used by flows, animations, and transitions are defined here.
/// This makes it easy to tune the pacing of the experience.
///
/// ## Usage
/// ```swift
/// try await Task.sleep(for: PracticeTiming.scoreDisplayDuration)
/// withAnimation(.easeInOut(duration: PracticeTiming.phaseTransitionDuration)) { ... }
/// ```
enum PracticeTiming {
    
    // MARK: - Flow Durations
    
    /// Brief pause after TTS completes before auto-advancing (Read Aloud)
    static let readAloudCompletePause: Duration = .milliseconds(500)
    
    /// Duration to wait for user to start speaking after TTS
    static let waitForUserDuration: Duration = .seconds(1)
    
    /// Minimum listening duration before accepting silence as "done"
    static let minimumListeningDuration: TimeInterval = 1.0
    
    /// Maximum listening duration before auto-stopping
    static let maximumListeningDuration: TimeInterval = 30.0
    
    /// Duration of silence that triggers listening completion
    static let silenceThreshold: TimeInterval = 1.5
    
    /// Duration to show the "analyzing" state
    static let analysisDuration: Duration = .milliseconds(500)
    
    /// Duration to display score before auto-advancing
    static let scoreDisplayDuration: Duration = .seconds(1.5)
    
    /// Duration navigation is locked during score display
    static let navigationLockDuration: Duration = .seconds(1.0)
    
    /// Delay before starting flow when entering active mode
    static let flowStartDelay: Duration = .milliseconds(300)
    
    // MARK: - Animation Durations
    
    /// Duration for phase transition animations
    static let phaseTransitionDuration: TimeInterval = 0.25
    
    /// Duration for pager snap animation
    static let pagerSnapDuration: TimeInterval = 0.35
    
    /// Duration for auto-advance animation
    static let autoAdvanceDuration: TimeInterval = 0.4
    
    /// Duration for mode/binaural selector expansion
    static let selectorExpansionDuration: TimeInterval = 0.3
    
    /// Duration for dock height changes
    static let dockResizeDuration: TimeInterval = 0.35
    
    /// Duration for score reveal animation
    static let scoreRevealDuration: TimeInterval = 0.4
    
    /// Duration for listening chip pulse animation
    static let listeningPulseDuration: TimeInterval = 1.2
    
    // MARK: - Update Intervals
    
    /// Interval for TTS progress updates
    static let ttsProgressInterval: TimeInterval = 0.05
    
    /// Interval for audio level updates during listening
    static let audioLevelUpdateInterval: TimeInterval = 0.033 // ~30fps
    
    /// Interval for speech recognition interim results
    static let speechRecognitionInterval: TimeInterval = 0.1
    
    // MARK: - Debounce Thresholds
    
    /// Debounce for rapid navigation gestures
    static let navigationDebounce: Duration = .milliseconds(150)
    
    /// Debounce for selector taps
    static let selectorTapDebounce: Duration = .milliseconds(200)
    
    /// Debounce for favorite button taps
    static let favoriteDebounce: Duration = .milliseconds(300)
}

// MARK: - Flow Timing Configuration

/// Complete timing configuration for a flow type.
///
/// Groups related timings for a specific flow to make it
/// easy to reason about the entire flow's pacing.
struct FlowTimingConfiguration: Sendable {
    
    /// Delay before flow starts
    let startDelay: Duration
    
    /// Duration of each phase (where applicable)
    let phaseDurations: [String: Duration]
    
    /// Pause after completion before auto-advance
    let completionPause: Duration
    
    /// Whether to auto-advance after completion
    let autoAdvances: Bool
}

extension PracticeTiming {
    
    /// Timing configuration for Read Aloud mode
    static let readAloudTiming = FlowTimingConfiguration(
        startDelay: flowStartDelay,
        phaseDurations: [
            "complete": readAloudCompletePause
        ],
        completionPause: readAloudCompletePause,
        autoAdvances: true
    )
    
    /// Timing configuration for Read & Speak mode
    static let readAndSpeakTiming = FlowTimingConfiguration(
        startDelay: flowStartDelay,
        phaseDurations: [
            "waitingForUser": waitForUserDuration,
            "analyzing": analysisDuration,
            "showingScore": scoreDisplayDuration
        ],
        completionPause: .zero,
        autoAdvances: true
    )
    
    /// Timing configuration for Speak Only mode
    static let speakOnlyTiming = FlowTimingConfiguration(
        startDelay: flowStartDelay,
        phaseDurations: [
            "analyzing": analysisDuration,
            "showingScore": scoreDisplayDuration
        ],
        completionPause: .zero,
        autoAdvances: true
    )
}

// MARK: - Convenience Extensions

extension Duration {
    
    /// Convert Duration to TimeInterval for APIs that require it
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1_000_000_000_000_000_000
    }
}
