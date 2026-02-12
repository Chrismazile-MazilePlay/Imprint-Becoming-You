//
//  SessionResult.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/6/26.
//

import Foundation

// MARK: - SessionAffirmationResult

/// Tracks a single affirmation's result within a session.
///
/// Holds the affirmation reference and its completion status for display
/// in the Results Summary view. Each loop iteration records whether the
/// user completed the affirmation (all words matched) or skipped it.
///
/// ## Loop Support
/// When looping is enabled, completion status from each loop iteration
/// is stored in `loopCompletions` array.
struct SessionAffirmationResult: Identifiable, Sendable {

    /// Unique identifier for this result
    let id: UUID

    /// The affirmation that was practiced
    let affirmationId: UUID

    /// The affirmation text (captured at time of practice)
    let text: String

    /// The category of the affirmation
    let category: String

    /// Completion status for each loop iteration (index = loopIteration - 1).
    /// `true` = completed (all words matched), `false` = incomplete.
    /// Empty array means not yet attempted or skipped.
    var loopCompletions: [Bool]

    /// Whether the affirmation is favorited
    var isFavorited: Bool

    /// Whether this result is from a mode that produces completion tracking (Read & Speak, Speak Only)
    /// When false (Read Aloud), no completion area is shown.
    /// When true and no completions recorded, "Skipped" is shown.
    let isFromScoringMode: Bool

    // MARK: - Computed Properties

    /// Whether the affirmation was completed in the first (or only) loop.
    var wasCompleted: Bool {
        loopCompletions.first ?? false
    }

    /// Whether this affirmation was skipped (no attempts in a scoring mode)
    var wasSkipped: Bool { isFromScoringMode && loopCompletions.isEmpty }

    /// Goal category as enum (if valid)
    var goalCategory: GoalCategory? {
        GoalCategory(rawValue: category)
    }

    /// Whether this result has completions from multiple loops
    var hasMultipleLoops: Bool {
        loopCompletions.count > 1
    }

    /// Number of loops that were completed successfully
    var completedLoopCount: Int {
        loopCompletions.filter { $0 }.count
    }

    // MARK: - Initialization

    /// Creates a result from an affirmation marked as completed
    init(affirmation: Affirmation, wasCompleted: Bool, isFromScoringMode: Bool = true) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.loopCompletions = [wasCompleted]
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }

    /// Creates a result from an affirmation without completion data (pending, skipped, or non-scoring mode)
    init(affirmation: Affirmation, isFromScoringMode: Bool) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.loopCompletions = []
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }

    /// Creates a result with explicit loop completions array
    init(
        affirmation: Affirmation,
        loopCompletions: [Bool],
        isFromScoringMode: Bool = true
    ) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.loopCompletions = loopCompletions
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }

    // MARK: - Methods

    /// Records completion status for the current loop iteration.
    /// - Parameter completed: Whether the user completed the affirmation
    mutating func addLoopCompletion(_ completed: Bool) {
        loopCompletions.append(completed)
    }

    /// Gets the completion status for a specific loop iteration.
    /// - Parameter iteration: 1-based loop iteration number
    /// - Returns: Whether the affirmation was completed in that iteration, or nil if not attempted
    func wasCompleted(forLoop iteration: Int) -> Bool? {
        let index = iteration - 1
        guard loopCompletions.indices.contains(index) else { return nil }
        return loopCompletions[index]
    }
}

// MARK: - SessionSummary

/// Complete summary of a practice session.
///
/// Contains all affirmation results and metadata needed to display
/// the Results Summary view. Supports loop tracking and saved
/// session playback identification.
struct SessionSummary: Sendable {

    /// The mode that was practiced
    let mode: SessionMode

    /// Individual affirmation results in order practiced
    var results: [SessionAffirmationResult]

    /// Session start time
    let startedAt: Date

    /// Session completion time
    let completedAt: Date

    /// Number of loop iterations completed (1 = single play)
    let loopCount: Int

    /// ID of the saved session being played, if any
    let savedSessionId: UUID?

    /// Title of the saved session being played, if any
    let savedSessionTitle: String?

    // MARK: - Computed Properties

    /// Number of affirmations in the session
    var count: Int { results.count }

    /// Whether this was a saved session playback
    var isSavedSessionPlayback: Bool {
        savedSessionId != nil
    }

    /// Number of affirmations that were completed (all words matched)
    var completedCount: Int {
        results.filter { !$0.loopCompletions.isEmpty && $0.wasCompleted }.count
    }

    /// Number of affirmations that were skipped
    var skippedCount: Int {
        results.filter { $0.wasSkipped }.count
    }

    /// Results sorted for display: completed first (in order), then skipped (in order)
    var sortedResults: [SessionAffirmationResult] {
        // For non-scoring modes (Read Aloud), return as-is since there's no completed/skipped distinction
        guard mode == .readThenSpeak || mode == .speakOnly else {
            return results
        }

        // Separate completed and skipped while preserving original order within each group
        let completed = results.filter { !$0.loopCompletions.isEmpty }
        let skipped = results.filter { $0.wasSkipped }

        return completed + skipped
    }

    // MARK: - Initialization

    /// Creates an empty summary for a mode
    init(mode: SessionMode) {
        self.mode = mode
        self.results = []
        self.startedAt = Date()
        self.completedAt = Date()
        self.loopCount = 1
        self.savedSessionId = nil
        self.savedSessionTitle = nil
    }

    /// Creates a complete summary
    init(mode: SessionMode, results: [SessionAffirmationResult], startedAt: Date) {
        self.mode = mode
        self.results = results
        self.startedAt = startedAt
        self.completedAt = Date()
        self.loopCount = 1
        self.savedSessionId = nil
        self.savedSessionTitle = nil
    }

    /// Creates a complete summary with loop and saved session info
    init(
        mode: SessionMode,
        results: [SessionAffirmationResult],
        startedAt: Date,
        loopCount: Int,
        savedSessionId: UUID? = nil,
        savedSessionTitle: String? = nil
    ) {
        self.mode = mode
        self.results = results
        self.startedAt = startedAt
        self.completedAt = Date()
        self.loopCount = loopCount
        self.savedSessionId = savedSessionId
        self.savedSessionTitle = savedSessionTitle
    }
}

// MARK: - Sample Data

extension SessionAffirmationResult {

    /// Sample result for previews (completed)
    static var sample: SessionAffirmationResult {
        SessionAffirmationResult(
            affirmation: .sample,
            wasCompleted: true,
            isFromScoringMode: true
        )
    }

    /// Sample skipped result for previews
    static var sampleSkipped: SessionAffirmationResult {
        SessionAffirmationResult(affirmation: .sample, isFromScoringMode: true)
    }

    /// Sample Read Aloud result for previews (no completion area)
    static var sampleReadAloud: SessionAffirmationResult {
        SessionAffirmationResult(affirmation: .sample, isFromScoringMode: false)
    }

    /// Sample result with multiple loop completions
    static var sampleWithLoops: SessionAffirmationResult {
        SessionAffirmationResult(
            affirmation: .sample,
            loopCompletions: [true, true, true],
            isFromScoringMode: true
        )
    }

    /// Collection of sample results for previews (includes some skipped)
    static var samples: [SessionAffirmationResult] {
        Affirmation.samples.enumerated().map { index, affirmation in
            // Make some skipped for realistic preview
            if index == 2 || index == 4 {
                return SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: true)
            } else {
                return SessionAffirmationResult(
                    affirmation: affirmation,
                    wasCompleted: true,
                    isFromScoringMode: true
                )
            }
        }
    }

    /// Collection of sample Read Aloud results (no completions)
    static var samplesReadAloud: [SessionAffirmationResult] {
        Affirmation.samples.map { affirmation in
            SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: false)
        }
    }

    /// Collection of sample results with multiple loop completions
    static var samplesWithLoops: [SessionAffirmationResult] {
        Affirmation.samples.enumerated().map { index, affirmation in
            if index == 2 {
                // One skipped
                return SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: true)
            } else {
                return SessionAffirmationResult(
                    affirmation: affirmation,
                    loopCompletions: [true, true, true],
                    isFromScoringMode: true
                )
            }
        }
    }
}

extension SessionSummary {

    /// Sample summary for previews
    static var sample: SessionSummary {
        SessionSummary(
            mode: .readThenSpeak,
            results: SessionAffirmationResult.samples,
            startedAt: Date().addingTimeInterval(-300)
        )
    }

    /// Sample summary with multiple loops for previews
    static var sampleWithLoops: SessionSummary {
        SessionSummary(
            mode: .readThenSpeak,
            results: SessionAffirmationResult.samplesWithLoops,
            startedAt: Date().addingTimeInterval(-900),
            loopCount: 3
        )
    }

    /// Sample summary from saved session playback
    static var sampleSavedSession: SessionSummary {
        SessionSummary(
            mode: .readThenSpeak,
            results: SessionAffirmationResult.samples,
            startedAt: Date().addingTimeInterval(-300),
            loopCount: 1,
            savedSessionId: UUID(),
            savedSessionTitle: "Morning Confidence"
        )
    }
}
