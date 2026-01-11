//
//  Affirmation.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData

// MARK: - Affirmation Source

/// The origin of an affirmation, determining its lifecycle and priority.
///
/// ## Source Hierarchy (Priority Order)
/// 1. `.generated` - AI-generated from user's custom prompts (most personalized)
/// 2. `.backend` - Fetched from Firebase database (curated, fresh content)
/// 3. `.seeded` - Bundled with app (always available offline, fallback)
///
/// ## Lifecycle Rules
/// - `.seeded`: Never expires, never deleted. Guaranteed offline availability.
/// - `.backend`: Has expiration date. Deleted when expired.
/// - `.generated`: Has expiration date. Deleted when expired.
///
/// ## Usage
/// ```swift
/// // Queue generation prioritizes by source
/// let queue = repository.fetchQueue(forCategories: categories)
/// // Returns: generated first, then backend, then seeded
///
/// // Cleanup only affects non-seeded content
/// repository.deleteExpired()
/// // Only deletes .backend and .generated with expired dates
/// ```
enum AffirmationSource: String, Codable, Sendable, CaseIterable {
    /// Bundled with app, loaded from OfflineAffirmations.json.
    /// Always available offline. Never expires. Never deleted.
    case seeded
    
    /// Fetched from Firebase backend database.
    /// Has expiration date. Deleted when expired.
    case backend
    
    /// AI-generated via OpenAI from user's custom prompt.
    /// Most personalized. Has expiration date.
    case generated
    
    /// Priority value for queue sorting (lower = higher priority)
    var priority: Int {
        switch self {
        case .generated: return 0
        case .backend: return 1
        case .seeded: return 2
        }
    }
    
    /// Whether this source can be deleted when expired
    var canExpire: Bool {
        switch self {
        case .seeded: return false
        case .backend, .generated: return true
        }
    }
}

// MARK: - Affirmation

/// A single affirmation statement that the user practices.
///
/// Affirmations can originate from three sources:
/// - **Seeded**: Bundled with the app (1,120 items), always available offline
/// - **Backend**: Fetched from Firebase database when online
/// - **Generated**: AI-generated from user's custom prompts via OpenAI
///
/// ## Source-Based Lifecycle
/// | Source | Expires | Deleted | Offline |
/// |--------|---------|---------|---------|
/// | .seeded | Never | Never | Always âœ“ |
/// | .backend | Yes | When expired | Cached |
/// | .generated | Yes | When expired | Cached |
///
/// ## Related Types
/// - `AffirmationSource` - Enum defining content origin
/// - `ResonanceRecord` - Defined in Domain/Models/ResonanceRecord.swift
/// - `GoalCategory` - Defined in Constants.swift
@Model
final class Affirmation {
    
    // MARK: - Identity Properties
    
    /// Unique identifier for the affirmation
    @Attribute(.unique)
    var id: UUID
    
    /// The affirmation text to be displayed and spoken
    var text: String
    
    /// Category this affirmation belongs to
    var category: String
    
    // MARK: - Source Properties
    
    /// The origin of this affirmation (seeded, backend, or generated).
    ///
    /// Determines expiration behavior and queue priority:
    /// - `.seeded`: Never expires, lowest queue priority, always offline
    /// - `.backend`: Can expire, medium priority, fetched from Firebase
    /// - `.generated`: Can expire, highest priority, AI-created
    var source: AffirmationSource
    
    /// Unique identifier from the backend database (Firebase document ID).
    /// Used to prevent duplicate fetches when syncing.
    /// Only set for `.backend` source affirmations.
    var backendId: String?
    
    /// When this affirmation was fetched from backend or generated.
    /// Only set for `.backend` and `.generated` sources.
    var fetchedAt: Date?
    
    /// ID of the custom prompt that generated this (nil if from goals)
    var sourcePromptId: UUID?
    
    // MARK: - Temporal Properties
    
    /// Date when this affirmation was created or seeded
    var generatedAt: Date
    
    /// Date when this affirmation expires from cache.
    /// For `.seeded` source, this is `Date.distantFuture` (never expires).
    var expiresAt: Date
    
    // MARK: - Audio Cache Properties
    
    /// Local filename of cached audio (nil if not cached)
    var audioFileName: String?
    
    /// Date when the audio cache expires
    var audioExpiresAt: Date?
    
    // MARK: - Engagement Properties
    
    /// Whether the user has seen this affirmation
    var hasBeenSeen: Bool
    
    /// Date of last practice session with this affirmation
    var lastPracticedAt: Date?
    
    /// History of resonance scores for this affirmation
    var resonanceScores: [ResonanceRecord]
    
    // MARK: - Batch Properties
    
    /// Batch identifier for grouping affirmations
    var batchId: UUID?
    
    /// Index within the batch for ordering
    var batchIndex: Int
    
    // MARK: - User Engagement Properties
    
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
    
    // MARK: - Legacy Properties (Migration Support)
    
    /// Whether this is from the offline bundle.
    /// @deprecated Maintained for SwiftData migration. Use `source == .seeded` instead.
    var isOfflineContent: Bool
    
    // MARK: - Initialization
    
    /// Creates a new affirmation.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - text: The affirmation text
    ///   - category: Category name (e.g., "Confidence")
    ///   - source: Origin of the affirmation (defaults to `.seeded`)
    ///   - backendId: Firebase document ID (for backend source)
    ///   - fetchedAt: When fetched/generated (for backend/generated source)
    ///   - sourcePromptId: Custom prompt ID if generated from prompt
    ///   - generatedAt: Creation timestamp
    ///   - expiresAt: Expiration timestamp (nil uses default based on source)
    ///   - audioFileName: Cached audio filename
    ///   - audioExpiresAt: Audio cache expiration
    ///   - hasBeenSeen: Whether user has viewed this
    ///   - lastPracticedAt: Last practice timestamp
    ///   - resonanceScores: History of resonance scores
    ///   - batchId: Batch grouping ID
    ///   - batchIndex: Position within batch
    ///   - isFavorited: Whether user favorited this
    ///   - favoritedAt: When favorited
    ///   - viewCount: Number of views
    ///   - speakCount: Number of times spoken
    ///   - shareCount: Number of shares
    ///   - skipCount: Number of skips
    ///   - lastInteractedAt: Last interaction timestamp
    init(
        id: UUID = UUID(),
        text: String,
        category: String,
        source: AffirmationSource = .seeded,
        backendId: String? = nil,
        fetchedAt: Date? = nil,
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
        self.source = source
        self.backendId = backendId
        self.fetchedAt = fetchedAt
        self.sourcePromptId = sourcePromptId
        self.generatedAt = generatedAt
        
        // Set expiration based on source if not provided
        if let expiresAt = expiresAt {
            self.expiresAt = expiresAt
        } else {
            switch source {
            case .seeded:
                // Seeded content never expires
                self.expiresAt = Date.distantFuture
            case .backend, .generated:
                // Backend/generated content expires after cache duration
                self.expiresAt = Date().addingTimeInterval(
                    TimeInterval(Constants.Cache.expirationDays * 24 * 60 * 60)
                )
            }
        }
        
        self.audioFileName = audioFileName
        self.audioExpiresAt = audioExpiresAt
        self.hasBeenSeen = hasBeenSeen
        self.lastPracticedAt = lastPracticedAt
        self.resonanceScores = resonanceScores
        self.batchId = batchId
        self.batchIndex = batchIndex
        self.isFavorited = isFavorited
        self.favoritedAt = favoritedAt
        self.viewCount = viewCount
        self.speakCount = speakCount
        self.shareCount = shareCount
        self.skipCount = skipCount
        self.lastInteractedAt = lastInteractedAt
        
        // Sync legacy field with source
        self.isOfflineContent = (source == .seeded)
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
    
    /// Whether this affirmation can be deleted (non-seeded sources only)
    var canBeDeleted: Bool {
        source.canExpire
    }
    
    /// Whether this is seeded (bundled) content
    var isSeeded: Bool {
        source == .seeded
    }
    
    /// Whether this is backend (Firebase) content
    var isBackend: Bool {
        source == .backend
    }
    
    /// Whether this is AI-generated content
    var isGenerated: Bool {
        source == .generated
    }
    
    /// The most recent resonance score
    var latestResonanceScore: ResonanceRecord? {
        resonanceScores.last
    }
    
    /// Average resonance score across all attempts
    var averageResonanceScore: Float? {
        guard !resonanceScores.isEmpty else { return nil }
        let total = resonanceScores.reduce(0) { $0 + $1.finalScore }
        return total / Float(resonanceScores.count)
    }
    
    /// Number of times this affirmation has been practiced
    var practiceCount: Int {
        resonanceScores.count
    }
    
    /// Best resonance score achieved
    var bestResonanceScore: Float? {
        resonanceScores.map(\.finalScore).max()
    }
    
    /// Goal category as enum (if valid)
    var goalCategory: GoalCategory? {
        GoalCategory(rawValue: category)
    }
    
    // MARK: - Speech Duration Properties
    
    /// Estimated speech duration in seconds based on word count.
    ///
    /// Calculated using average speech rate of ~120 WPM (0.5 seconds/word)
    /// for clear, deliberate affirmation delivery.
    var speechDuration: TimeInterval {
        let wordCount = text.split(separator: " ").count
        let secondsPerWord: Double = 0.5  // ~120 WPM, slow and clear
        return Double(wordCount) * secondsPerWord
    }
    
    /// Whether this affirmation is within the acceptable duration limit for TTS.
    ///
    /// Affirmations exceeding `PracticeTiming.ttsMaximumSpeechDuration` (7 seconds)
    /// should be filtered out during queue generation as a QA measure.
    var isWithinDurationLimit: Bool {
        speechDuration <= PracticeTiming.ttsMaximumSpeechDuration
    }
    
    /// Word count for the affirmation text
    var wordCount: Int {
        text.split(separator: " ").count
    }
    
    /// Engagement score for recommendation algorithm.
    ///
    /// Higher scores indicate more meaningful engagement.
    /// Factors in views, speaks, resonance, shares, and favorites.
    /// Skips reduce the score to deprioritize less-engaged content.
    var engagementScore: Double {
        var score = Double(viewCount) * 0.1
        score += Double(speakCount) * 0.3
        score += Double(averageResonanceScore ?? 0) * 0.3
        score += Double(shareCount) * 0.5
        score -= Double(skipCount) * 0.2
        if isFavorited { score += 1.0 }
        return max(0, score)
    }
    
    /// Queue priority score for smart queue algorithm.
    ///
    /// Lower scores = higher priority in queue.
    /// Factors:
    /// - Source priority (generated > backend > seeded)
    /// - Seen status (unseen prioritized)
    /// - View count (less viewed prioritized)
    /// - Recency (older content prioritized for freshness)
    var queuePriorityScore: Double {
        var score = Double(source.priority) * 1000 // Source tier
        
        if hasBeenSeen {
            score += 500 // Penalize seen content
        }
        
        score += Double(viewCount) * 10 // Penalize heavily viewed
        score += Double(speakCount) * 5 // Penalize practiced
        
        // Favor older content for variety
        let daysSinceInteraction = lastInteractedAt.map {
            Date().timeIntervalSince($0) / 86400
        } ?? 365
        score -= min(daysSinceInteraction, 30) * 2 // Up to 60 point bonus for old content
        
        return score
    }
}

// MARK: - Sample Data

extension Affirmation {
    
    /// Sample affirmation for previews
    static var sample: Affirmation {
        Affirmation(
            text: "I am confident and capable of achieving my goals.",
            category: GoalCategory.confidence.rawValue,
            source: .seeded,
            batchIndex: 0
        )
    }
    
    /// Collection of sample affirmations for previews
    static var samples: [Affirmation] {
        [
            Affirmation(
                text: "I am confident and capable of achieving my goals.",
                category: GoalCategory.confidence.rawValue,
                source: .seeded,
                batchIndex: 0
            ),
            Affirmation(
                text: "I embrace each day with focus and determination.",
                category: GoalCategory.focus.rawValue,
                source: .seeded,
                batchIndex: 1
            ),
            Affirmation(
                text: "I am worthy of love, success, and abundance.",
                category: GoalCategory.abundance.rawValue,
                source: .seeded,
                batchIndex: 2
            ),
            Affirmation(
                text: "My faith guides me through every challenge.",
                category: GoalCategory.faith.rawValue,
                source: .seeded,
                batchIndex: 3
            ),
            Affirmation(
                text: "I choose peace in this moment.",
                category: GoalCategory.peace.rawValue,
                source: .seeded,
                batchIndex: 4
            )
        ]
    }
}

// NOTE: ResonanceRecord is defined in Domain/Models/ResonanceRecord.swift
// NOTE: ResonanceRating is defined in Domain/Models/ResonanceRecord.swift
