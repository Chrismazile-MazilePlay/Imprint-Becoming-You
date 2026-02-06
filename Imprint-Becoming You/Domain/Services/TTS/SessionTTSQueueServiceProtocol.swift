//
//  SessionTTSQueueServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import Foundation

// MARK: - Session TTS Queue Service Protocol

/// Protocol for managing TTS pre-synthesis queue during practice sessions.
///
/// This service handles **bounded parallel synthesis** of affirmations to eliminate
/// TTS loading delays during session playback. It manages:
/// - Waiting for Kokoro TTS engine readiness
/// - Initial preparation with configurable parallelism (default: 3 concurrent tasks)
/// - Background synthesis (remaining affirmations while user practices)
/// - Priority-based queue management for fast navigation
/// - Progress callbacks for smooth UI updates
/// - Immediate cancellation on session end
///
/// ## Session Lifecycle
/// ```
/// 1. prepareSession() - Wait for Kokoro, then synthesize ALL affirmations
/// 2. (optional) User taps "Start Now" - caller cancels task, calls startBackgroundSynthesis()
/// 3. getAudio() - Retrieve cached audio for playback
/// 4. notifyPlaying() - Update queue priorities as user navigates
/// 5. cancelAll() - Stop everything on session end
/// ```
///
/// ## Preparation Phases
/// The preparation process has distinct phases for smooth progress UI:
/// ```
/// Phase 1: WaitingForKokoro  - Wait for TTS engine warm-up (0% â†’ 15%)
/// Phase 2: Synthesizing      - Parallel audio synthesis (15% â†’ 99%)
/// Phase 3: Complete          - All ready (100%)
/// Phase 4: Error             - Timeout or failure (shows fallback UI)
/// ```
///
/// ## Architecture
/// ```
/// SessionTTSQueueServiceProtocol
/// â”œâ”€â”€ SessionTTSQueueService (Production)
/// â”‚   â””â”€â”€ Uses TTSServiceProtocol with bounded TaskGroup
/// â””â”€â”€ MockSessionTTSQueueService (Testing)
/// ```
@MainActor
protocol SessionTTSQueueServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether the service is currently preparing initial affirmations
    var isPreparing: Bool { get }
    
    /// Current preparation phase
    var preparationPhase: SessionPreparationPhase { get }
    
    /// Number of affirmations prepared so far
    var preparedCount: Int { get }
    
    /// Total number of affirmations in the session
    var totalCount: Int { get }
    
    /// Progress of initial preparation (0.0 - 1.0)
    var preparationProgress: Float { get }
    
    /// Whether initial preparation is complete (all ready)
    var isInitialPreparationComplete: Bool { get }
    
    /// Whether the "Start Now" threshold has been reached (for large sessions)
    var canStartEarly: Bool { get }
    
    // MARK: - Session Lifecycle
    
    /// Prepares a session by waiting for Kokoro and pre-synthesizing ALL affirmations.
    ///
    /// This method:
    /// 1. Waits for Kokoro TTS engine to be ready (or timeout)
    /// 2. Uses a **bounded TaskGroup** to synthesize affirmations concurrently
    /// 3. Reports progress and phase changes via callbacks
    /// 4. **Always synthesizes ALL affirmations** (does not return early)
    ///
    /// ## Kokoro Wait Behavior
    /// - If Kokoro is already ready, phase transitions immediately to `.synthesizing`
    /// - If not ready, waits up to `kokoroWarmupTimeout` (12 seconds)
    /// - If timeout reached, transitions to `.kokoroTimeout` phase
    /// - Caller handles showing "Continue with System Voice" / "Retry" UI
    ///
    /// ## Early Start Handling
    /// The caller is responsible for implementing "Start Now" behavior:
    /// 1. Monitor progress callback - when `preparedCount >= 15`, enable "Start Now" button
    /// 2. If user taps "Start Now", cancel the preparation Task
    /// 3. This method will throw `CancellationError`
    /// 4. Call `startBackgroundSynthesis(startingFrom:)` to continue in background
    ///
    /// - Parameters:
    ///   - affirmations: All affirmations in the session
    ///   - voiceId: The voice ID to use for synthesis (ignored if forceSystemTTS is true)
    ///   - forceSystemTTS: If true, bypass Kokoro and use System TTS (session-scoped fallback)
    ///   - onPhaseChange: Callback fired when preparation phase changes
    ///   - onProgress: Callback fired after each affirmation is synthesized.
    ///     Parameters: (preparedCount: Int, totalCount: Int)
    /// - Throws: `CancellationError` if cancelled, `AppError.ttsError` if synthesis fails
    func prepareSession(
        affirmations: [SessionAffirmationInfo],
        voiceId: String?,
        forceSystemTTS: Bool,
        onPhaseChange: @escaping @Sendable (SessionPreparationPhase) -> Void,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws
    
    /// Continues synthesis of remaining affirmations in the background.
    ///
    /// Call this after starting the session early (user tapped "Start Now").
    /// The queue service will synthesize remaining affirmations while the user
    /// is practicing, prioritizing upcoming indices.
    ///
    /// - Parameter startIndex: The index to start synthesizing from (typically preparedCount)
    func startBackgroundSynthesis(startingFrom startIndex: Int)
    
    /// Gets cached audio data for an affirmation by its unique identifier.
    ///
    /// - Parameter id: The affirmation's UUID
    /// - Returns: Audio data if cached, nil if not yet synthesized
    func getAudio(for id: UUID) -> Data?

    /// Checks if audio is ready for the given affirmation.
    ///
    /// - Parameter id: The affirmation's UUID
    /// - Returns: true if audio is cached and ready to play
    func isReady(_ id: UUID) -> Bool
    
    /// Notifies the queue that playback has moved to a new index.
    ///
    /// This allows the queue to reprioritize synthesis:
    /// - Cancel synthesis for skipped indices
    /// - Prioritize upcoming indices (currentIndex + 1, + 2, ...)
    ///
    /// - Parameter index: The index now being played
    func notifyPlaying(index: Int)
    
    /// Synthesizes audio for a specific index on-demand.
    ///
    /// Use this when audio isn't cached and user has navigated to that index.
    /// The result is automatically cached.
    ///
    /// - Parameter index: The affirmation index to synthesize
    /// - Returns: Audio data
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesizeOnDemand(index: Int) async throws -> Data
    
    /// Updates the internal affirmation list after a shuffle.
    ///
    /// Because audio is cached by UUID (not positional index), the cache remains
    /// fully valid after a shuffle — no invalidation needed. This method simply
    /// updates the affirmation order so index-based lookups resolve to the correct
    /// affirmation in the new arrangement.
    ///
    /// - Parameter newOrder: The shuffled affirmation list (with updated indices)
    func updateAffirmationOrder(_ newOrder: [SessionAffirmationInfo])

    /// Starts background synthesis from the given index.
    ///
    /// Used after shuffle to pre-warm the cache for the new affirmation order.
    /// Without this, every segment on the first shuffled loop falls through to
    /// `synthesizeOnDemand()` (1-2s delay per segment).
    ///
    /// Synthesis runs sequentially with throttling to avoid ANE contention
    /// with active playback. Already-cached indices are skipped.
    ///
    /// - Parameter startIndex: The index to start pre-synthesizing from
    func preSynthesizeFromIndex(_ startIndex: Int)

    /// Awaits synthesis of the first affirmation, then kicks off background
    /// synthesis for the rest.
    ///
    /// Use this after shuffle to eliminate the delay on the first segment.
    /// `preSynthesizeFromIndex()` fires in background — by the time
    /// `startFlowForCurrentAffirmation()` calls `speakText()`, index 0 has
    /// no cached audio yet and falls through to `synthesizeOnDemand()`.
    ///
    /// This method:
    /// 1. Synthesizes `startIndex` synchronously (awaited)
    /// 2. Calls `preSynthesizeFromIndex(startIndex + 1)` for remaining indices
    ///
    /// - Parameter startIndex: The index to synthesize first (typically 0)
    func synthesizeFirstThenBackground(_ startIndex: Int) async

    /// Clears the audio cache and cancels background synthesis without
    /// resetting session metadata.
    ///
    /// Use this when the session is complete (summary shown) but the user
    /// may repeat. Frees cached PCM audio (~3–40 MB) while preserving
    /// `sessionAffirmations`, `currentVoiceId`, and `currentVoiceSettings`
    /// so that a subsequent repeat can re-synthesize with the same voice.
    ///
    /// Contrast with `cancelAll()`, which fully tears down session state
    /// (clears affirmations, resets voice settings, resumes idle timer).
    func clearQueue()

    /// Cancels all synthesis and clears the cache.
    ///
    /// Call this when:
    /// - Session ends (exit, summary, mode change to Read Only)
    /// - App resets to home
    /// - User taps "Cancel" during preparation
    ///
    /// This method is synchronous and returns immediately.
    /// All audio playback and pending synthesis are stopped.
    func cancelAll()
}

// MARK: - Session Preparation Phase

/// The current phase of session preparation.
///
/// Used for smooth progress bar animation and appropriate UI state.
enum SessionPreparationPhase: Equatable, Sendable {
    
    /// Waiting for Kokoro TTS engine to be ready.
    /// Progress bar animates from 2% â†’ 15% during this phase.
    case waitingForKokoro
    
    /// Actively synthesizing affirmations.
    /// Progress bar animates from 15% â†’ 99% based on completion.
    case synthesizing
    
    /// All affirmations synthesized successfully.
    case complete
    
    /// Kokoro warm-up timed out.
    /// UI should show "Continue with System Voice" and "Retry" buttons.
    case kokoroTimeout
    
    /// An error occurred during preparation.
    /// - Parameter message: Human-readable error description
    case error(message: String)
    
    /// Whether this phase represents a terminal error state
    var isError: Bool {
        switch self {
        case .kokoroTimeout, .error:
            return true
        default:
            return false
        }
    }
    
    /// Whether preparation is actively in progress
    var isInProgress: Bool {
        switch self {
        case .waitingForKokoro, .synthesizing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Session Affirmation Info

/// Lightweight struct containing only the info needed for TTS synthesis.
///
/// This avoids passing full Affirmation objects (which are SwiftData models)
/// across async boundaries.
struct SessionAffirmationInfo: Sendable {
    
    /// The affirmation's unique identifier
    let id: UUID
    
    /// The text to synthesize (already stripped of citations)
    let text: String
    
    /// The index in the session queue
    let index: Int
    
    /// Creates info from an Affirmation at a given index.
    ///
    /// - Parameters:
    ///   - affirmation: The source affirmation
    ///   - index: The index in the session
    init(affirmation: Affirmation, index: Int) {
        self.id = affirmation.id
        self.text = affirmation.text.strippingTrailingCitation
        self.index = index
    }
    
    /// Creates info with explicit values (for testing/mocks).
    init(id: UUID, text: String, index: Int) {
        self.id = id
        self.text = text
        self.index = index
    }
}

// MARK: - Queue State

/// The current state of the synthesis queue.
enum SessionTTSQueueState: Equatable, Sendable {
    
    /// Queue is idle, no session active
    case idle
    
    /// Waiting for Kokoro TTS engine to become ready
    case waitingForKokoro
    
    /// Preparing affirmations using bounded parallel synthesis
    case preparingParallel(prepared: Int, total: Int)
    
    /// Initial preparation complete, synthesizing remaining in background
    case synthesizingBackground(prepared: Int, total: Int)
    
    /// All affirmations synthesized
    case complete
    
    /// Kokoro warm-up timed out
    case kokoroTimeout
    
    /// Preparation was cancelled
    case cancelled
}

// MARK: - Default Values

extension SessionTTSQueueServiceProtocol {
    
    /// Default maximum concurrent synthesis tasks (tuned for ANE)
    static var defaultMaxConcurrency: Int {
        Constants.SessionPreparation.maxConcurrency
    }
    
    /// Default threshold for "Start Now" button
    static var defaultReadyToStartThreshold: Int {
        Constants.SessionPreparation.readyToStartThreshold
    }
    
    /// Default large session threshold
    static var defaultLargeSessionThreshold: Int {
        Constants.SessionPreparation.largeSessionThreshold
    }
    
    /// Kokoro warm-up timeout (seconds)
    static var kokoroWarmupTimeout: TimeInterval {
        Constants.SessionPreparation.kokoroWarmupTimeout
    }
}
