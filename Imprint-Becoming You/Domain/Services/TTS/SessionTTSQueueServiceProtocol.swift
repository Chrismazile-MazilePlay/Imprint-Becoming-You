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
/// This service handles background synthesis of affirmations to eliminate
/// TTS loading delays during session playback. It manages:
/// - Initial preparation (first 5 affirmations before session starts)
/// - Background synthesis (remaining affirmations while user practices)
/// - Priority-based queue management for fast navigation
/// - Immediate cancellation on session end
///
/// ## Session Lifecycle
/// ```
/// 1. prepareSession() - Synthesize first 5 affirmations, show loading
/// 2. getAudio() - Retrieve cached audio for playback
/// 3. notifyPlaying() - Update queue priorities as user navigates
/// 4. cancelAll() - Stop everything on session end
/// ```
///
/// ## Architecture
/// ```
/// SessionTTSQueueServiceProtocol
/// ├── SessionTTSQueueService (Production)
/// │   └── Uses TTSServiceProtocol for synthesis
/// └── MockSessionTTSQueueService (Testing)
/// ```
@MainActor
protocol SessionTTSQueueServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether the service is currently preparing initial affirmations
    var isPreparing: Bool { get }
    
    /// Number of affirmations prepared so far
    var preparedCount: Int { get }
    
    /// Total number of affirmations to prepare initially
    var preparationTarget: Int { get }
    
    /// Progress of initial preparation (0.0 - 1.0)
    var preparationProgress: Float { get }
    
    /// Whether initial preparation is complete (first N ready)
    var isInitialPreparationComplete: Bool { get }
    
    // MARK: - Session Lifecycle
    
    /// Prepares a session by pre-synthesizing affirmations.
    ///
    /// This method:
    /// 1. Clears any existing cache
    /// 2. Synthesizes the first `initialCount` affirmations synchronously
    /// 3. Returns when initial preparation is complete
    /// 4. Continues synthesizing remaining affirmations in background
    ///
    /// - Parameters:
    ///   - affirmations: All affirmations in the session
    ///   - voiceId: The voice ID to use for synthesis
    ///   - initialCount: Number of affirmations to prepare before returning (default: 5)
    /// - Throws: `AppError.ttsError` if initial preparation fails completely
    func prepareSession(
        affirmations: [SessionAffirmationInfo],
        voiceId: String?,
        initialCount: Int
    ) async throws
    
    /// Gets cached audio data for an affirmation at the given index.
    ///
    /// - Parameter index: The affirmation index in the session
    /// - Returns: Audio data if cached, nil if not yet synthesized
    func getAudio(for index: Int) -> Data?
    
    /// Checks if audio is ready for the given index.
    ///
    /// - Parameter index: The affirmation index in the session
    /// - Returns: true if audio is cached and ready to play
    func isReady(_ index: Int) -> Bool
    
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
    
    /// Cancels all synthesis and clears the cache.
    ///
    /// Call this when:
    /// - Session ends (exit, summary, mode change to Read Only)
    /// - App resets to home
    ///
    /// This method is synchronous and returns immediately.
    /// All audio playback and pending synthesis are stopped.
    func cancelAll()
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
}

// MARK: - Queue State

/// The current state of the synthesis queue.
enum SessionTTSQueueState: Equatable, Sendable {
    
    /// Queue is idle, no session active
    case idle
    
    /// Preparing initial affirmations (blocking)
    case preparingInitial(prepared: Int, total: Int)
    
    /// Initial preparation complete, synthesizing remaining in background
    case synthesizingBackground(prepared: Int, total: Int)
    
    /// All affirmations synthesized
    case complete
    
    /// Preparation was cancelled
    case cancelled
}

// MARK: - Default Values

extension SessionTTSQueueServiceProtocol {
    
    /// Default number of affirmations to prepare before starting session
    static var defaultInitialCount: Int { 5 }
    
    /// Maximum time to wait for initial preparation (seconds)
    static var preparationTimeout: TimeInterval { 15.0 }
}
