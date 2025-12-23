//
//  Affirmation.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData

// MARK: - Affirmation

/// A single affirmation statement that the user practices.
///
/// Affirmations can be generated from the user's selected goals,
/// from a custom prompt, or loaded from the offline bundle.
@Model
final class Affirmation {
    
    // MARK: - Properties
    
    /// Unique identifier for the affirmation
    @Attribute(.unique)
    var id: UUID
    
    /// The affirmation text to be displayed and spoken
    var text: String
    
    /// Category this affirmation belongs to
    var category: String
    
    /// ID of the custom prompt that generated this (nil if from goals)
    var sourcePromptId: UUID?
    
    /// Date when this affirmation was generated
    var generatedAt: Date
    
    /// Date when this affirmation expires from cache
    var expiresAt: Date
    
    /// Local filename of cached audio (nil if not cached)
    var audioFileName: String?
    
    /// Date when the audio cache expires
    var audioExpiresAt: Date?
    
    /// Whether the user has seen this affirmation
    var hasBeenSeen: Bool
    
    /// Date of last practice session with this affirmation
    var lastPracticedAt: Date?
    
    /// History of resonance scores for this affirmation
    var resonanceScores: [ResonanceRecord]
    
    /// Batch identifier for grouping affirmations
    var batchId: UUID?
    
    /// Index within the batch for ordering
    var batchIndex: Int
    
    /// Whether this is from the offline bundle
    var isOfflineContent: Bool
    
    // MARK: - Engagement Properties (Phase 4A)
    
    /// Whether user has favorited this affirmation
    var isFavorited: Bool
    
    /// Date when the affirmation was favorited
    var favoritedAt: Date?
    
    /// Number of times this affirmation has been viewed
    var viewCount: Int
    
    /// Number of times user has spoken this affirmation
    var speakCount: Int
    
    /// Number of times this affirmation has been shared
    var shareCount: Int
    
    /// Number of times user skipped past this affirmation quickly
    var skipCount: Int
    
    /// Date of last interaction with this affirmation
    var lastInteractedAt: Date?
    
    // MARK: - Initialization
    
    /// Creates a new affirmation
    init(
        id: UUID = UUID(),
        text: String,
        category: String,
        sourcePromptId: UUID? = nil,
        generatedAt: Date = Date(),
        expiresAt: Date? = nil,
        audioFileName: String? = nil,
        audioExpiresAt: Date? = nil,
        hasBeenSeen: Bool = false,
        lastPracticedAt: Date? = nil,
        resonanceScores: [ResonanceRecord] = [],
        batchId: UUID? = nil,
        batchIndex: Int = 0,
        isOfflineContent: Bool = false,
        isFavorited: Bool = false,
        favoritedAt: Date? = nil,
        viewCount: Int = 0,
        speakCount: Int = 0,
        shareCount: Int = 0,
        skipCount: Int = 0,
        lastInteractedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.sourcePromptId = sourcePromptId
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt ?? Date().addingTimeInterval(
            TimeInterval(Constants.Cache.expirationDays * 24 * 60 * 60)
        )
        self.audioFileName = audioFileName
        self.audioExpiresAt = audioExpiresAt
        self.hasBeenSeen = hasBeenSeen
        self.lastPracticedAt = lastPracticedAt
        self.resonanceScores = resonanceScores
        self.batchId = batchId
        self.batchIndex = batchIndex
        self.isOfflineContent = isOfflineContent
        self.isFavorited = isFavorited
        self.favoritedAt = favoritedAt
        self.viewCount = viewCount
        self.speakCount = speakCount
        self.shareCount = shareCount
        self.skipCount = skipCount
        self.lastInteractedAt = lastInteractedAt
    }
}

// MARK: - Computed Properties

extension Affirmation {
    
    /// Whether this affirmation has cached audio available
    var hasAudioCache: Bool {
        guard let fileName = audioFileName else { return false }
        guard let expiresAt = audioExpiresAt else { return false }
        return !fileName.isEmpty && expiresAt > Date()
    }
    
    /// Whether this affirmation is expired
    var isExpired: Bool {
        expiresAt < Date()
    }
    
    /// Whether this is from a custom prompt
    var isFromPrompt: Bool {
        sourcePromptId != nil
    }
    
    /// The most recent resonance score
    var latestResonanceScore: ResonanceRecord? {
        resonanceScores.last
    }
    
    /// Average resonance score across all attempts
    var averageResonanceScore: Float? {
        guard !resonanceScores.isEmpty else { return nil }
        let total = resonanceScores.reduce(0) { $0 + $1.overallScore }
        return total / Float(resonanceScores.count)
    }
    
    /// Number of times this affirmation has been practiced
    var practiceCount: Int {
        resonanceScores.count
    }
    
    /// Best resonance score achieved
    var bestResonanceScore: Float? {
        resonanceScores.map(\.overallScore).max()
    }
    
    /// Goal category as enum (if valid)
    var goalCategory: GoalCategory? {
        GoalCategory(rawValue: category)
    }
    
    /// Engagement score for recommendation algorithm
    var engagementScore: Double {
        var score = Double(viewCount) * 0.1
        score += Double(speakCount) * 0.3
        score += Double(averageResonanceScore ?? 0) * 0.3
        score += Double(shareCount) * 0.5
        score -= Double(skipCount) * 0.2
        if isFavorited { score += 1.0 }
        return max(0, score)
    }
}

// MARK: - ResonanceRecord

/// A single resonance score recording from a practice session
struct ResonanceRecord: Codable, Equatable, Sendable, Identifiable {
    
    /// Unique identifier for the record
    var id: UUID
    
    /// Timestamp of the recording
    var timestamp: Date
    
    /// Combined resonance score (0.0 - 1.0)
    var overallScore: Float
    
    /// Text accuracy component (0.0 - 1.0)
    var textAccuracy: Float
    
    /// Vocal energy (RMS) component (0.0 - 1.0)
    var vocalEnergy: Float
    
    /// Pitch stability component (0.0 - 1.0)
    var pitchStability: Float
    
    /// Duration of the recording in seconds
    var duration: TimeInterval
    
    /// Session mode used during this recording
    var sessionMode: SessionMode
    
    /// Creates a new resonance record
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        overallScore: Float,
        textAccuracy: Float,
        vocalEnergy: Float,
        pitchStability: Float,
        duration: TimeInterval = 0,
        sessionMode: SessionMode = .speakOnly
    ) {
        self.id = id
        self.timestamp = timestamp
        self.overallScore = overallScore
        self.textAccuracy = textAccuracy
        self.vocalEnergy = vocalEnergy
        self.pitchStability = pitchStability
        self.duration = duration
        self.sessionMode = sessionMode
    }
    
    /// Quality level based on overall score
    var qualityLevel: ResonanceQuality {
        ResonanceQuality(score: overallScore)
    }
}

// MARK: - ResonanceQuality

/// Quality levels for resonance scores
enum ResonanceQuality: String, Sendable {
    case needsWork = "Needs Work"
    case good = "Good"
    case excellent = "Excellent"
    
    init(score: Float) {
        if score >= Constants.ResonanceScoring.excellentThreshold {
            self = .excellent
        } else if score >= Constants.ResonanceScoring.goodThreshold {
            self = .good
        } else {
            self = .needsWork
        }
    }
    
    /// Color associated with this quality level
    var colorName: String {
        switch self {
        case .needsWork:
            return "resonanceNeedsWork"
        case .good:
            return "resonanceGood"
        case .excellent:
            return "resonanceExcellent"
        }
    }
    
    /// SF Symbol icon for this quality level
    var iconName: String {
        switch self {
        case .needsWork:
            return "arrow.up.circle"
        case .good:
            return "checkmark.circle"
        case .excellent:
            return "star.circle.fill"
        }
    }
}

// MARK: - Sample Data

extension Affirmation {
    
    /// Sample affirmation for previews
    static var sample: Affirmation {
        Affirmation(
            text: "I am confident and capable of achieving my goals.",
            category: GoalCategory.confidence.rawValue,
            batchIndex: 0
        )
    }
    
    /// Collection of sample affirmations for previews
    static var samples: [Affirmation] {
        [
            Affirmation(
                text: "I am confident and capable of achieving my goals.",
                category: GoalCategory.confidence.rawValue,
                batchIndex: 0
            ),
            Affirmation(
                text: "I embrace each day with focus and determination.",
                category: GoalCategory.focus.rawValue,
                batchIndex: 1
            ),
            Affirmation(
                text: "I am worthy of love, success, and abundance.",
                category: GoalCategory.abundance.rawValue,
                batchIndex: 2
            ),
            Affirmation(
                text: "My faith guides me through every challenge.",
                category: GoalCategory.faith.rawValue,
                batchIndex: 3
            ),
            Affirmation(
                text: "I choose peace in this moment.",
                category: GoalCategory.peace.rawValue,
                batchIndex: 4
            )
        ]
    }
}
