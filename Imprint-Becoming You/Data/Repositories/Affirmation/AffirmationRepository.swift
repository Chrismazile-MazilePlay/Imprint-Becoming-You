//
//  AffirmationRepository.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/5/26.
//

import Foundation
import SwiftData

// MARK: - Affirmation Repository

/// SwiftData implementation of the affirmation repository.
///
/// Provides data access operations for affirmations including:
/// - Smart queue fetching with source-aware priority ordering
/// - Session queue generation with exclusion support
/// - Engagement tracking (views, speaks, favorites, etc.)
/// - Batch operations for content seeding
/// - Content refresh detection
///
/// ## Thread Safety
/// This class is `@MainActor` isolated because SwiftData's `ModelContext`
/// must be accessed from the main thread. All operations are synchronous.
///
/// ## Smart Queue Algorithm
/// The queue uses a pre-computed `queueScore` field for database-level sorting,
/// enabling efficient queries with `fetchLimit` instead of loading all records.
///
/// ```
/// queueScore Formula:
/// score = (source.priority * 10000)
///       + (hasBeenSeen ? 5000 : 0)
///       + (speakCount * 100)
///       + viewCount
///
/// Score Ranges by Source:
/// | Source | Unseen Range | Seen Range |
/// |--------|-------------|------------|
/// | .generated | 0-4999 | 5000-9999 |
/// | .backend | 10000-14999 | 15000-19999 |
/// | .seeded | 20000-24999 | 25000-29999 |
/// ```
///
/// ## Source-Aware Lifecycle
/// - `.seeded`: Never deleted, always available offline
/// - `.backend`: Deleted when expired
/// - `.generated`: Deleted when expired
///
/// ## Error Handling Strategy
///
/// This repository follows a consistent error handling contract:
///
/// - **Input validation errors**: Throw `AppError.validationFailed` for invalid inputs
///   (empty categories, non-positive limits). This allows callers to show specific validation feedback.
///
/// - **Entity not found**: Return `nil` or empty array for fetch methods. This is expected
///   behavior, not an error condition.
///
/// - **Database errors**: Throw `AppError.loadFailed` or `AppError.saveFailed` for
///   SwiftData operation failures.
///
/// - **Best-effort operations**: Engagement tracking methods (`recordView`, `recordSpeak`,
///   `recordSkip`, `recordShare`, `addResonanceRecord`) log and return gracefully when
///   entity is not found. These are non-critical analytics that shouldn't block user flow.
@MainActor
final class AffirmationRepository: AffirmationRepositoryProtocol {
    
    // MARK: - Properties
    
    /// The SwiftData model context
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    
    /// Creates a repository with the given model context.
    ///
    /// - Parameter modelContext: SwiftData model context for database operations
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Queue Fetching
    
    func fetchQueue(forCategories categories: [String], limit: Int) throws -> [Affirmation] {
        // Validate input - throw for invalid parameters
        guard !categories.isEmpty else {
            throw AppError.validationFailed(
                field: "categories",
                reason: "At least one category is required"
            )
        }
        
        guard limit > 0 else {
            throw AppError.validationFailed(
                field: "limit",
                reason: "Limit must be a positive number"
            )
        }
        
        do {
            // Use database-level sorting on pre-computed queueScore
            // This is much more efficient than fetching all and sorting in-memory
            var descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    categories.contains(affirmation.category)
                },
                sortBy: [SortDescriptor(\.queueScore, order: .forward)]
            )
            descriptor.fetchLimit = limit
            
            let results = try modelContext.fetch(descriptor)
            
            // Light shuffle within same-score tier for variety
            return shuffleWithinScoreTiers(results)
            
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch affirmation queue: \(error.localizedDescription)")
        }
    }
    
    func fetchSessionQueue(
        forCategories categories: [String],
        excluding: Set<UUID>,
        limit: Int
    ) throws -> [Affirmation] {
        // Validate input - throw for invalid parameters
        guard !categories.isEmpty else {
            throw AppError.validationFailed(
                field: "categories",
                reason: "At least one category is required"
            )
        }
        
        guard limit > 0 else {
            throw AppError.validationFailed(
                field: "limit",
                reason: "Limit must be a positive number"
            )
        }
        
        do {
            // For session queue with exclusions, we need to fetch more than limit
            // since some results will be filtered out by exclusion set
            // Fetch extra to account for potential exclusions
            let fetchMultiplier = excluding.isEmpty ? 1 : 2
            let fetchCount = min(limit * fetchMultiplier + excluding.count, 500)
            
            var descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    categories.contains(affirmation.category)
                },
                sortBy: [SortDescriptor(\.queueScore, order: .forward)]
            )
            descriptor.fetchLimit = fetchCount
            
            var results = try modelContext.fetch(descriptor)
            
            // Filter out excluded IDs (done in-memory, but on a smaller set)
            if !excluding.isEmpty {
                results = results.filter { !excluding.contains($0.id) }
            }
            
            // Take limited results after filtering
            let sessionQueue = Array(results.prefix(limit))
            
            // Light shuffle within same-score tier for variety
            let shuffledQueue = shuffleWithinScoreTiers(sessionQueue)
            
            AppLogger.debug(
                "Session queue fetched",
                category: .data,
                context: ["excluded": excluding.count, "returned": shuffledQueue.count]
            )
            
            return shuffledQueue
            
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch session queue: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Basic Fetching
    
    func fetchFavorites() throws -> [Affirmation] {
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { $0.isFavorited },
                sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
            )
            
            return try modelContext.fetch(descriptor)
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch favorites: \(error.localizedDescription)")
        }
    }
    
    func fetchByIds(_ ids: [UUID]) throws -> [Affirmation] {
        // Empty input returns empty result - not an error
        guard !ids.isEmpty else { return [] }
        
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    ids.contains(affirmation.id)
                }
            )
            
            return try modelContext.fetch(descriptor)
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch affirmations by IDs: \(error.localizedDescription)")
        }
    }
    
    func fetchById(_ id: UUID) throws -> Affirmation? {
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { $0.id == id }
            )
            
            // Return nil if not found - not an error
            return try modelContext.fetch(descriptor).first
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch affirmation: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Counting
    
    func countTotal() throws -> Int {
        do {
            let descriptor = FetchDescriptor<Affirmation>()
            return try modelContext.fetchCount(descriptor)
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to count affirmations: \(error.localizedDescription)")
        }
    }
    
    func countForCategories(_ categories: [String]) throws -> Int {
        // Empty categories returns 0 - not an error
        guard !categories.isEmpty else { return 0 }
        
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    categories.contains(affirmation.category)
                }
            )
            
            return try modelContext.fetchCount(descriptor)
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to count affirmations for categories: \(error.localizedDescription)")
        }
    }
    
    func countBySource(_ source: AffirmationSource) throws -> Int {
        do {
            // SwiftData predicate requires raw value comparison for enums
            let sourceRawValue = source.rawValue
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    affirmation.source.rawValue == sourceRawValue
                }
            )
            
            return try modelContext.fetchCount(descriptor)
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to count affirmations by source: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Engagement Tracking
    //
    // These are "best effort" operations - they track analytics but shouldn't
    // block user flow if the entity is not found. Entity not found is expected
    // for deleted/expired content.
    //
    // IMPORTANT: All engagement tracking methods must call recalculateQueueScore()
    // after updating engagement metrics to keep database-level sorting accurate.
    
    func recordView(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            // Entity not found is expected for deleted/expired content - log and return
            AppLogger.entityNotFound("Affirmation", id: affirmationId)
            return
        }
        
        do {
            affirmation.viewCount += 1
            affirmation.hasBeenSeen = true
            affirmation.lastInteractedAt = Date()
            
            // Recalculate queue score for database-level sorting
            affirmation.recalculateQueueScore()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record view: \(error.localizedDescription)")
        }
    }
    
    func recordSpeak(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            // Entity not found is expected for deleted/expired content - log and return
            AppLogger.entityNotFound("Affirmation", id: affirmationId)
            return
        }
        
        do {
            affirmation.speakCount += 1
            affirmation.lastPracticedAt = Date()
            affirmation.lastInteractedAt = Date()
            
            // Recalculate queue score for database-level sorting
            affirmation.recalculateQueueScore()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record speak: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func toggleFavorite(affirmationId: UUID) throws -> Bool {
        // For user-initiated actions, not finding the entity IS an error
        guard let affirmation = try fetchById(affirmationId) else {
            throw AppError.loadFailed(reason: "Affirmation not found")
        }
        
        do {
            affirmation.isFavorited.toggle()
            affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
            affirmation.lastInteractedAt = Date()
            
            // Note: toggleFavorite doesn't affect queueScore (not in formula)
            // but we update lastInteractedAt for tracking purposes
            
            try modelContext.save()
            
            AppLogger.debug(
                "Toggled favorite",
                category: .data,
                context: ["id": affirmationId.uuidString, "isFavorited": affirmation.isFavorited]
            )
            
            return affirmation.isFavorited
            
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.saveFailed(reason: "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    func recordSkip(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            // Entity not found is expected for deleted/expired content - log and return
            AppLogger.entityNotFound("Affirmation", id: affirmationId)
            return
        }
        
        do {
            affirmation.skipCount += 1
            affirmation.lastInteractedAt = Date()
            
            // Note: skipCount doesn't affect queueScore (not in formula)
            // but we track it for analytics purposes
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record skip: \(error.localizedDescription)")
        }
    }
    
    func recordShare(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            // Entity not found is expected for deleted/expired content - log and return
            AppLogger.entityNotFound("Affirmation", id: affirmationId)
            return
        }
        
        do {
            affirmation.shareCount += 1
            affirmation.lastInteractedAt = Date()
            
            // Note: shareCount doesn't affect queueScore (not in formula)
            // but we track it for analytics purposes
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record share: \(error.localizedDescription)")
        }
    }
    
    func addResonanceRecord(affirmationId: UUID, record: ResonanceRecord) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            // Entity not found is expected for deleted/expired content - log and return
            AppLogger.entityNotFound("Affirmation", id: affirmationId)
            return
        }
        
        do {
            affirmation.resonanceScores.append(record)
            affirmation.lastPracticedAt = Date()
            affirmation.lastInteractedAt = Date()
            
            // Note: resonanceScores doesn't affect queueScore (not in formula)
            // but we track practice times for analytics purposes
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to add resonance record: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Content Management
    
    func insertBatch(_ affirmations: [Affirmation]) throws {
        // Empty batch is a no-op - not an error
        guard !affirmations.isEmpty else { return }
        
        do {
            for affirmation in affirmations {
                // Ensure queueScore is calculated for each new affirmation
                affirmation.recalculateQueueScore()
                modelContext.insert(affirmation)
            }
            
            try modelContext.save()
            
            // Log insertion with source breakdown
            let sources = Dictionary(grouping: affirmations) { $0.source }
            let sourceCounts = sources.map { "\($0.key.rawValue): \($0.value.count)" }.joined(separator: ", ")
            AppLogger.info(
                "Inserted affirmation batch",
                category: .data,
                context: ["total": affirmations.count, "sources": sourceCounts]
            )
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to insert affirmation batch: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func deleteExpired() throws -> Int {
        let now = Date()
        
        do {
            // Only delete non-seeded content that has expired
            // CRITICAL: source != .seeded ensures offline content is NEVER deleted
            let seededRawValue = AffirmationSource.seeded.rawValue
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    affirmation.expiresAt < now && affirmation.source.rawValue != seededRawValue
                }
            )
            
            let expired = try modelContext.fetch(descriptor)
            let count = expired.count
            
            for affirmation in expired {
                modelContext.delete(affirmation)
            }
            
            try modelContext.save()
            
            if count > 0 {
                AppLogger.info(
                    "Deleted expired affirmations",
                    category: .data,
                    context: ["count": count, "seededPreserved": true]
                )
            }
            
            return count
            
        } catch {
            throw AppError.cacheError(reason: "Failed to delete expired affirmations: \(error.localizedDescription)")
        }
    }
    
    func categoriesNeedingRefresh(from categories: [String]) throws -> [String] {
        // Empty categories returns empty result - not an error
        guard !categories.isEmpty else { return [] }
        
        let threshold = Constants.ContentRefresh.depletedViewCountThreshold
        var depletedCategories: [String] = []
        
        do {
            for category in categories {
                // Count affirmations below threshold for this category
                let descriptor = FetchDescriptor<Affirmation>(
                    predicate: #Predicate<Affirmation> { affirmation in
                        affirmation.category == category && affirmation.viewCount < threshold
                    }
                )
                
                let freshCount = try modelContext.fetchCount(descriptor)
                
                // If no fresh content remains, category needs refresh
                if freshCount == 0 {
                    depletedCategories.append(category)
                }
            }
            
            return depletedCategories
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to check categories for refresh: \(error.localizedDescription)")
        }
    }
}

// MARK: - Queue Score Optimization Helpers

private extension AffirmationRepository {
    
    /// Shuffles results while keeping same-score items together for variety.
    ///
    /// This provides some randomness within priority tiers without breaking
    /// the overall priority ordering established by the database sort.
    ///
    /// - Parameter affirmations: Sorted affirmations from database query
    /// - Returns: Affirmations with same-score tiers shuffled for variety
    func shuffleWithinScoreTiers(_ affirmations: [Affirmation]) -> [Affirmation] {
        // Early return for small arrays where shuffling has minimal effect
        guard affirmations.count > 2 else { return affirmations }
        
        // Group by score using Dictionary(grouping:) - efficient O(n) operation
        let grouped = Dictionary(grouping: affirmations) { $0.queueScore }
        
        // Shuffle within each group, maintain group order by score
        var result: [Affirmation] = []
        result.reserveCapacity(affirmations.count)
        
        for score in grouped.keys.sorted() {
            var tier = grouped[score] ?? []
            tier.shuffle()
            result.append(contentsOf: tier)
        }
        
        return result
    }
}
