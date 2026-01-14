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
///
/// ## Loop Support
/// When looping is enabled, scores from each loop iteration are stored
/// in `loopScores` array. The `score` property returns the first/most
/// recent score for backward compatibility.
struct SessionAffirmationResult: Identifiable, Sendable {
    
    /// Unique identifier for this result
    let id: UUID
    
    /// The affirmation that was practiced
    let affirmationId: UUID
    
    /// The affirmation text (captured at time of practice)
    let text: String
    
    /// The category of the affirmation
    let category: String
    
    /// Scores from each loop iteration (index = loopIteration - 1).
    /// Empty array means not yet scored or skipped.
    var loopScores: [Int]
    
    /// Whether the affirmation is favorited
    var isFavorited: Bool
    
    /// Whether this result is from a mode that produces scores (Read & Speak, Speak Only)
    /// When false (Read Aloud), no score area is shown.
    /// When true and score is nil, "Skipped" is shown.
    let isFromScoringMode: Bool
    
    // MARK: - Computed Properties
    
    /// The resonance score (0-100), or nil if skipped/not applicable.
    /// Returns the first loop score for backward compatibility.
    var score: Int? {
        get { loopScores.first }
        set {
            if let newValue = newValue {
                if loopScores.isEmpty {
                    loopScores = [newValue]
                } else {
                    loopScores[0] = newValue
                }
            } else {
                loopScores = []
            }
        }
    }
    
    /// Average score across all loop iterations.
    /// Returns nil if no scores recorded.
    var averageScore: Int? {
        guard !loopScores.isEmpty else { return nil }
        let total = loopScores.reduce(0, +)
        return total / loopScores.count
    }
    
    /// Best score achieved across all loop iterations.
    var bestScore: Int? {
        loopScores.max()
    }
    
    /// Whether this affirmation was skipped (no score in a scoring mode)
    var wasSkipped: Bool { isFromScoringMode && loopScores.isEmpty }
    
    /// Goal category as enum (if valid)
    var goalCategory: GoalCategory? {
        GoalCategory(rawValue: category)
    }
    
    /// Whether this result has scores from multiple loops
    var hasMultipleLoopScores: Bool {
        loopScores.count > 1
    }
    
    // MARK: - Initialization
    
    /// Creates a result from an affirmation with a score
    init(affirmation: Affirmation, score: Int, isFromScoringMode: Bool = true) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.loopScores = [score]
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }
    
    /// Creates a result from an affirmation without a score (pending, skipped, or non-scoring mode)
    init(affirmation: Affirmation, isFromScoringMode: Bool) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.loopScores = []
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }
    
    /// Creates a result with explicit loop scores array
    init(
        affirmation: Affirmation,
        loopScores: [Int],
        isFromScoringMode: Bool = true
    ) {
        self.id = UUID()
        self.affirmationId = affirmation.id
        self.text = affirmation.text
        self.category = affirmation.category
        self.loopScores = loopScores
        self.isFavorited = affirmation.isFavorited
        self.isFromScoringMode = isFromScoringMode
    }
    
    // MARK: - Methods
    
    /// Adds a score for the current loop iteration.
    /// - Parameter score: The score to add
    mutating func addLoopScore(_ score: Int) {
        loopScores.append(score)
    }
    
    /// Gets the score for a specific loop iteration.
    /// - Parameter iteration: 1-based loop iteration number
    /// - Returns: The score for that iteration, or nil if not available
    func score(forLoop iteration: Int) -> Int? {
        let index = iteration - 1
        guard loopScores.indices.contains(index) else { return nil }
        return loopScores[index]
    }
}

// MARK: - SessionSummary

/// Complete summary of a practice session.
///
/// Contains all affirmation results and metadata needed to display
/// the Results Summary view. Now supports loop tracking and saved
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
    
    /// Average scores per loop iteration.
    /// Returns array where index = loopIteration - 1.
    var averageScoresByLoop: [Int] {
        guard loopCount > 1 else {
            return [averageScore]
        }
        
        var loopAverages: [Int] = []
        
        for loopIndex in 0..<loopCount {
            let scoresForLoop = results.compactMap { result -> Int? in
                guard result.loopScores.indices.contains(loopIndex) else { return nil }
                return result.loopScores[loopIndex]
            }
            
            guard !scoresForLoop.isEmpty else {
                loopAverages.append(0)
                continue
            }
            
            let total = scoresForLoop.reduce(0, +)
            loopAverages.append(total / scoresForLoop.count)
        }
        
        return loopAverages
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
    
    /// Sample result with multiple loop scores
    static var sampleWithLoops: SessionAffirmationResult {
        SessionAffirmationResult(
            affirmation: .sample,
            loopScores: [84, 91, 88],
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
    
    /// Collection of sample results with multiple loop scores
    static var samplesWithLoops: [SessionAffirmationResult] {
        Affirmation.samples.enumerated().map { index, affirmation in
            if index == 2 {
                // One skipped
                return SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: true)
            } else {
                return SessionAffirmationResult(
                    affirmation: affirmation,
                    loopScores: [
                        Int.random(in: 70...90),
                        Int.random(in: 75...95),
                        Int.random(in: 80...98)
                    ],
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
