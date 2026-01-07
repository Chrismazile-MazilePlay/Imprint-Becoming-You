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
/// 2. Prioritize unseen affirmations (`hasBeenSeen == false`)
/// 3. Then sort by least viewed (`viewCount` ascending)
/// 4. Finally by oldest practiced (`lastPracticedAt` ascending)
///
/// ## Usage
/// ```swift
/// @MainActor
/// func loadAffirmations() throws {
///     let repository = AffirmationRepository(modelContext: context)
///
///     // Fetch smart queue for user's categories
///     let queue = try repository.fetchQueue(
///         forCategories: ["Confidence", "Focus"],
///         limit: 30
///     )
///
///     // Record engagement
///     try repository.recordView(affirmationId: id)
/// }
/// ```
@MainActor
protocol AffirmationRepositoryProtocol {
    
    // MARK: - Fetching
    
    /// Fetches a smart queue of affirmations based on user's categories.
    ///
    /// The queue is ordered by:
    /// 1. Unseen affirmations first (`hasBeenSeen == false`)
    /// 2. Least viewed affirmations (`viewCount` ascending)
    /// 3. Oldest practiced affirmations (`lastPracticedAt` ascending)
    ///
    /// - Parameters:
    ///   - categories: Array of category names (e.g., ["Confidence", "Focus"])
    ///   - limit: Maximum number of affirmations to return
    /// - Returns: Ordered array of affirmations
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchQueue(forCategories categories: [String], limit: Int) throws -> [Affirmation]
    
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
    /// Used by `OfflineContentLoader` to seed the database.
    ///
    /// - Parameter affirmations: Array of affirmations to insert
    /// - Throws: `AppError.saveFailed` if insert fails
    func insertBatch(_ affirmations: [Affirmation]) throws
    
    /// Deletes expired affirmations.
    ///
    /// Removes affirmations where `expiresAt < now` and `isOfflineContent == false`.
    /// Offline content is never deleted.
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
    
    /// Whether to include favorites in the queue
    let includeFavorites: Bool
    
    /// Whether to shuffle within same priority tier
    let shuffleWithinTier: Bool
    
    /// Creates queue options
    init(
        categories: [String],
        limit: Int = Constants.Session.batchSize,
        includeFavorites: Bool = true,
        shuffleWithinTier: Bool = true
    ) {
        self.categories = categories
        self.limit = limit
        self.includeFavorites = includeFavorites
        self.shuffleWithinTier = shuffleWithinTier
    }
}
