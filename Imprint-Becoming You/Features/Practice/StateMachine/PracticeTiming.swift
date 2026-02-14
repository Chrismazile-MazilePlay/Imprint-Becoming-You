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
    
    /// Maximum listening duration before auto-stopping (absolute cap)
    static let maximumListeningDuration: TimeInterval = 30.0
    
    /// Duration of silence that triggers completion for COMPLETE affirmations
    /// User finished speaking the full affirmation - short pause accepts it
    static let completedAffirmationSilenceThreshold: TimeInterval = 2.0
    
    /// Duration of silence that triggers TIMEOUT for incomplete/no speech
    /// User said nothing or stopped mid-affirmation - longer silence shows retry
    static let incompleteSilenceTimeout: TimeInterval = 8.0
    
    /// Duration of the sparkle burst celebration before auto-advancing
    static let celebrationDuration: Duration = .seconds(2.5)

    /// Brief pause with all words highlighted before celebration sparkle burst.
    /// Gives the user a moment to absorb the fully-highlighted state.
    static let preCelebrationPause: Duration = .milliseconds(500)

    /// Brief delay after celebration completes before auto-advancing to next affirmation.
    /// Prevents the transition from feeling abrupt after the sparkle burst.
    static let postCelebrationDelay: Duration = .milliseconds(300)

    /// Brief pause after final score before transitioning to summary
    static let sessionCompletePause: Duration = .milliseconds(800)
    
    /// Duration for crossfade transition to results summary
    static let summaryTransitionDuration: TimeInterval = 0.5
    
    /// Duration for slide-down dismissal of results summary
    static let summaryDismissDuration: TimeInterval = 0.35
    
    /// Duration navigation is locked during score display
    static let navigationLockDuration: Duration = .seconds(1.0)
    
    // MARK: - TTS Duration Constants
    
    /// Minimum duration to hold on TTS affirmation before advancing.
    /// Ensures user has time to absorb the message.
    static let ttsMininumHoldDuration: TimeInterval = 3.0
    
    /// Maximum allowed speech duration for affirmations (QA threshold).
    /// Affirmations exceeding this should be flagged or excluded.
    static let ttsMaximumSpeechDuration: TimeInterval = 7.0
    
    /// Additional hold time after TTS completes before auto-advancing.
    /// Provides absorption time beyond the speech itself.
    static let ttsPostSpeechHold: Duration = .seconds(2)
    
    // MARK: - Word Detection Timeout Constants
    
    /// Duration without new word match before triggering timeout modal.
    /// Timer resets each time a matching word is detected.
    static let wordDetectionTimeout: TimeInterval = 10.0
    
    /// Minimum words that must be matched before timeout logic activates.
    /// Prevents timeout during initial silence before user starts speaking.
    static let wordDetectionMinimumBeforeTimeout: Int = 1
    
    /// Grace period before word detection timeout starts counting.
    /// Allows user time to prepare before speaking.
    static let wordDetectionGracePeriod: Duration = .seconds(2)
    
    // MARK: - Animation Durations
    
    /// Duration for phase transition animations
    static let phaseTransitionDuration: TimeInterval = 0.25
    
    /// Duration for pager snap animation
    static let pagerSnapDuration: TimeInterval = 0.35
    
    /// Duration for auto-advance animation
    static let autoAdvanceDuration: TimeInterval = 0.4
    
    /// Duration for mode/music selector expansion
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

// MARK: - Convenience Extensions

extension Duration {
    
    /// Convert Duration to TimeInterval for APIs that require it
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1_000_000_000_000_000_000
    }
}
