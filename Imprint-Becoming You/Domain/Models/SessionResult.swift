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
/// Holds the affirmation reference and its resonance score for display
/// in the Results Summary view. Score is optional - `nil` means skipped
/// (for scoring modes) or not applicable (for Read Aloud mode).
struct SessionAffirmationResult: Identifiable, Sendable {
    
    /// Unique identifier for this result
    let id: UUID
    
    /// The affirmation that was practiced
    let affirmationId: UUID
    
    /// The affirmation text (captured at time of practice)
    let text: String
    
    /// The category of the affirmation
    let category: String
    
    /// The resonance score (0-100), or nil if skipped/not applicable
    var score: Int?
    
    /// Whether the affirmation is favorited
    var isFavorited: Bool
    
    /// Whether this result is from a mode that produces scores (Read & Speak, Speak Only)
    /// When false (Read Aloud), no score area is shown.
    /// When true and score is nil, "Skipped" is shown.
    let isFromScoringMode: Bool
    
    /// Whether this affirmation was skipped (no score in a scoring mode)
    var wasSkipped: Bool { isFromScoringMode && score == nil }
    
    /// Goal category as enum (if valid)
    var goalCategory: GoalCategory? {
        GoalCategory(rawValue: category)
    }
    
    /// Creates a result from an affirmation with a score
    init(affirmation: Affirmation, score: Int, isFromScoringMode: Bool = true) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.score = score
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }
    
    /// Creates a result from an affirmation without a score (pending, skipped, or non-scoring mode)
    init(affirmation: Affirmation, isFromScoringMode: Bool) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.score = nil
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }
}

// MARK: - SessionSummary

/// Complete summary of a practice session.
///
/// Contains all affirmation results and metadata needed to display
/// the Results Summary view.
struct SessionSummary: Sendable {
    
    /// The mode that was practiced
    let mode: SessionMode
    
    /// Individual affirmation results in order practiced
    var results: [SessionAffirmationResult]
    
    /// Session start time
    let startedAt: Date
    
    /// Session completion time
    let completedAt: Date
    
    /// Number of affirmations in the session
    var count: Int { results.count }
    
    /// Average score across all scored affirmations (excludes skipped)
    var averageScore: Int {
        let scoredResults = results.compactMap { $0.score }
        guard !scoredResults.isEmpty else { return 0 }
        let total = scoredResults.reduce(0, +)
        return total / scoredResults.count
    }
    
    /// Number of affirmations that were skipped
    var skippedCount: Int {
        results.filter { $0.wasSkipped }.count
    }
    
    /// Results sorted for display: scored first (in order), then skipped (in order)
    var sortedResults: [SessionAffirmationResult] {
        // For non-scoring modes (Read Aloud), return as-is since there's no scored/skipped distinction
        guard mode == .readThenSpeak || mode == .speakOnly else {
            return results
        }
        
        // Separate scored and skipped while preserving original order within each group
        let scored = results.filter { $0.score != nil }
        let skipped = results.filter { $0.wasSkipped }
        
        return scored + skipped
    }
    
    /// Creates an empty summary for a mode
    init(mode: SessionMode) {
        self.mode = mode
        self.results = []
        self.startedAt = Date()
        self.completedAt = Date()
    }
    
    /// Creates a complete summary
    init(mode: SessionMode, results: [SessionAffirmationResult], startedAt: Date) {
        self.mode = mode
        self.results = results
        self.startedAt = startedAt
        self.completedAt = Date()
    }
}

// MARK: - Sample Data

extension SessionAffirmationResult {
    
    /// Sample result for previews (scored)
    static var sample: SessionAffirmationResult {
        SessionAffirmationResult(
            affirmation: .sample,
            score: 87,
            isFromScoringMode: true
        )
    }
    
    /// Sample skipped result for previews
    static var sampleSkipped: SessionAffirmationResult {
        SessionAffirmationResult(affirmation: .sample, isFromScoringMode: true)
    }
    
    /// Sample Read Aloud result for previews (no score area)
    static var sampleReadAloud: SessionAffirmationResult {
        SessionAffirmationResult(affirmation: .sample, isFromScoringMode: false)
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
                    score: Int.random(in: 70...98),
                    isFromScoringMode: true
                )
            }
        }
    }
    
    /// Collection of sample Read Aloud results (no scores)
    static var samplesReadAloud: [SessionAffirmationResult] {
        Affirmation.samples.map { affirmation in
            SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: false)
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
}
