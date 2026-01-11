//
//  AffirmationRepositoryProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/5/26.
//

import Foundation
import SwiftData

// MARK: - Affirmation Repository Protocol

/// Protocol defining data access operations for affirmations.
///
/// The repository pattern provides a clean abstraction between the business logic
/// (PracticeStore) and the data layer (SwiftData). This enables:
/// - Testability via mock implementations
/// - Single responsibility for data operations
/// - Consistent API across the app
///
/// ## MainActor Isolation
/// This protocol is `@MainActor` isolated because SwiftData's `ModelContext`
/// must be accessed from the main thread. All methods are synchronous since
/// SwiftData operations do not require async/await.
///
/// ## Smart Queue Algorithm
/// The `fetchQueue` method implements intelligent affirmation selection:
/// 1. Filter by user's selected categories
/// 2. Prioritize by source (generated > backend > seeded)
/// 3. Then unseen affirmations (`hasBeenSeen == false`)
/// 4. Then sort by least viewed (`viewCount` ascending)
/// 5. Finally by oldest practiced (`lastPracticedAt` ascending)
///
/// ## Dual Queue Support
/// - `fetchQueue`: For browse mode (30 items)
/// - `fetchSessionQueue`: For session mode (10 items, excludes recently browsed)
///
/// ## Usage
/// ```swift
/// @MainActor
/// func loadAffirmations() throws {
///     let repository = AffirmationRepository(modelContext: context)
///
///     // Fetch browse queue
///     let browseQueue = try repository.fetchQueue(
///         forCategories: ["Confidence", "Focus"],
///         limit: 30
///     )
///
///     // Fetch session queue (excludes recently browsed)
///     let recentlyBrowsedIds = browseQueue.prefix(20).map { $0.id }
///     let sessionQueue = try repository.fetchSessionQueue(
///         forCategories: ["Confidence", "Focus"],
///         excluding: recentlyBrowsedIds,
///         limit: 10
///     )
/// }
/// ```
@MainActor
protocol AffirmationRepositoryProtocol {
    
    // MARK: - Queue Fetching
    
    /// Fetches a smart queue of affirmations for browse mode.
    ///
    /// The queue is ordered by:
    /// 1. Source priority (generated > backend > seeded)
    /// 2. Unseen affirmations first (`hasBeenSeen == false`)
    /// 3. Least viewed affirmations (`viewCount` ascending)
    /// 4. Oldest practiced affirmations (`lastPracticedAt` ascending)
    ///
    /// - Parameters:
    ///   - categories: Array of category names (e.g., ["Confidence", "Focus"])
    ///   - limit: Maximum number of affirmations to return
    /// - Returns: Ordered array of affirmations
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchQueue(forCategories categories: [String], limit: Int) throws -> [Affirmation]
    
    /// Fetches a fresh queue for session mode, excluding recently browsed affirmations.
    ///
    /// This method ensures session practice uses different content than recently browsed:
    /// 1. Excludes affirmations with IDs in the `excluding` set
    /// 2. Applies source priority (generated > backend > seeded)
    /// 3. Prioritizes unseen, then least spoken
    /// 4. Falls back to seeded content if not enough fresh content
    ///
    /// ## Session Freshness
    /// By excluding recently browsed IDs, users always get a fresh 10-affirmation
    /// session even if they've been browsing the same categories.
    ///
    /// - Parameters:
    ///   - categories: Array of category names
    ///   - excluding: Set of affirmation IDs to exclude (recently browsed)
    ///   - limit: Maximum affirmations to return (typically 10)
    /// - Returns: Fresh affirmations for session practice
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchSessionQueue(
        forCategories categories: [String],
        excluding: Set<UUID>,
        limit: Int
    ) throws -> [Affirmation]
    
    // MARK: - Basic Fetching
    
    /// Fetches all favorited affirmations.
    ///
    /// - Returns: Array of favorited affirmations, ordered by most recently favorited
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchFavorites() throws -> [Affirmation]
    
    /// Fetches affirmations by specific IDs.
    ///
    /// - Parameter ids: Array of affirmation UUIDs
    /// - Returns: Array of matching affirmations
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchByIds(_ ids: [UUID]) throws -> [Affirmation]
    
    /// Fetches a single affirmation by ID.
    ///
    /// - Parameter id: The affirmation UUID
    /// - Returns: The affirmation if found, nil otherwise
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchById(_ id: UUID) throws -> Affirmation?
    
    // MARK: - Counting
    
    /// Counts total affirmations in the database.
    ///
    /// - Returns: Total count of affirmations
    /// - Throws: `AppError.loadFailed` if count fails
    func countTotal() throws -> Int
    
    /// Counts affirmations for specific categories.
    ///
    /// - Parameter categories: Array of category names
    /// - Returns: Count of affirmations matching categories
    /// - Throws: `AppError.loadFailed` if count fails
    func countForCategories(_ categories: [String]) throws -> Int
    
    /// Counts affirmations by source type.
    ///
    /// - Parameter source: The affirmation source to count
    /// - Returns: Count of affirmations with that source
    /// - Throws: `AppError.loadFailed` if count fails
    func countBySource(_ source: AffirmationSource) throws -> Int
    
    // MARK: - Engagement Tracking
    
    /// Records a view of an affirmation.
    ///
    /// Increments `viewCount` and sets `hasBeenSeen` to true.
    ///
    /// - Parameter affirmationId: The affirmation UUID
    /// - Throws: `AppError.saveFailed` if update fails
    func recordView(affirmationId: UUID) throws
    
    /// Records that user spoke an affirmation.
    ///
    /// Increments `speakCount` and updates `lastPracticedAt`.
    ///
    /// - Parameter affirmationId: The affirmation UUID
    /// - Throws: `AppError.saveFailed` if update fails
    func recordSpeak(affirmationId: UUID) throws
    
    /// Toggles favorite status of an affirmation.
    ///
    /// - Parameter affirmationId: The affirmation UUID
    /// - Returns: New favorite status
    /// - Throws: `AppError.saveFailed` if update fails
    @discardableResult
    func toggleFavorite(affirmationId: UUID) throws -> Bool
    
    /// Records a skip (quick swipe past) of an affirmation.
    ///
    /// - Parameter affirmationId: The affirmation UUID
    /// - Throws: `AppError.saveFailed` if update fails
    func recordSkip(affirmationId: UUID) throws
    
    /// Records a share of an affirmation.
    ///
    /// - Parameter affirmationId: The affirmation UUID
    /// - Throws: `AppError.saveFailed` if update fails
    func recordShare(affirmationId: UUID) throws
    
    /// Adds a resonance score record to an affirmation.
    ///
    /// - Parameters:
    ///   - affirmationId: The affirmation UUID
    ///   - record: The resonance score record to add
    /// - Throws: `AppError.saveFailed` if update fails
    func addResonanceRecord(affirmationId: UUID, record: ResonanceRecord) throws
    
    // MARK: - Content Management
    
    /// Inserts a batch of new affirmations.
    ///
    /// Used by `OfflineContentLoader` to seed the database and
    /// by sync service to insert backend content.
    ///
    /// - Parameter affirmations: Array of affirmations to insert
    /// - Throws: `AppError.saveFailed` if insert fails
    func insertBatch(_ affirmations: [Affirmation]) throws
    
    /// Deletes expired affirmations.
    ///
    /// Removes affirmations where `expiresAt < now` AND `source != .seeded`.
    /// Seeded content is NEVER deleted to guarantee offline availability.
    ///
    /// - Returns: Number of affirmations deleted
    /// - Throws: `AppError.cacheError` if deletion fails
    @discardableResult
    func deleteExpired() throws -> Int
    
    /// Checks if categories need content refresh.
    ///
    /// A category is "depleted" when all its affirmations have been viewed
    /// at least `Constants.ContentRefresh.depletedViewCountThreshold` times.
    ///
    /// - Parameter categories: Array of category names to check
    /// - Returns: Array of category names that need fresh content
    /// - Throws: `AppError.loadFailed` if check fails
    func categoriesNeedingRefresh(from categories: [String]) throws -> [String]
}

// MARK: - Affirmation Queue Options

/// Configuration options for fetching the affirmation queue.
struct AffirmationQueueOptions {
    
    /// Categories to include
    let categories: [String]
    
    /// Maximum number of affirmations to return
    let limit: Int
    
    /// Affirmation IDs to exclude (for session freshness)
    let excludingIds: Set<UUID>
    
    /// Whether to include favorites in the queue
    let includeFavorites: Bool
    
    /// Whether to shuffle within same priority tier
    let shuffleWithinTier: Bool
    
    /// Preferred source priority (nil = default ordering)
    let preferredSource: AffirmationSource?
    
    /// Creates queue options for browse mode
    static func browse(
        categories: [String],
        limit: Int = Constants.Session.batchSize
    ) -> AffirmationQueueOptions {
        AffirmationQueueOptions(
            categories: categories,
            limit: limit,
            excludingIds: [],
            includeFavorites: true,
            shuffleWithinTier: true,
            preferredSource: nil
        )
    }
    
    /// Creates queue options for session mode
    static func session(
        categories: [String],
        excluding: Set<UUID>,
        limit: Int = Constants.Session.sessionSize
    ) -> AffirmationQueueOptions {
        AffirmationQueueOptions(
            categories: categories,
            limit: limit,
            excludingIds: excluding,
            includeFavorites: true,
            shuffleWithinTier: true,
            preferredSource: nil
        )
    }
    
    /// Creates queue options with all parameters
    init(
        categories: [String],
        limit: Int = Constants.Session.batchSize,
        excludingIds: Set<UUID> = [],
        includeFavorites: Bool = true,
        shuffleWithinTier: Bool = true,
        preferredSource: AffirmationSource? = nil
    ) {
        self.categories = categories
        self.limit = limit
        self.excludingIds = excludingIds
        self.includeFavorites = includeFavorites
        self.shuffleWithinTier = shuffleWithinTier
        self.preferredSource = preferredSource
    }
}
