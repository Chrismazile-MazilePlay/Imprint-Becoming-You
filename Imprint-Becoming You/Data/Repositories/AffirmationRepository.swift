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
/// ```
/// Priority Order:
/// 1. source.priority (generated=0, backend=1, seeded=2)
/// 2. hasBeenSeen == false (unseen first)
/// 3. viewCount ascending (least viewed)
/// 4. lastPracticedAt ascending (oldest practiced)
/// 5. Shuffle within same priority tier
/// ```
///
/// ## Source-Aware Lifecycle
/// - `.seeded`: Never deleted, always available offline
/// - `.backend`: Deleted when expired
/// - `.generated`: Deleted when expired
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
        guard !categories.isEmpty else {
            return []
        }
        
        do {
            // Fetch all affirmations matching categories
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    categories.contains(affirmation.category)
                }
            )
            
            var results = try modelContext.fetch(descriptor)
            
            // Apply source-aware smart queue sorting
            results = applySmartQueueSorting(results, excluding: [])
            
            // Limit results
            return Array(results.prefix(limit))
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch affirmation queue: \(error.localizedDescription)")
        }
    }
    
    func fetchSessionQueue(
        forCategories categories: [String],
        excluding: Set<UUID>,
        limit: Int
    ) throws -> [Affirmation] {
        guard !categories.isEmpty else {
            return []
        }
        
        do {
            // Fetch all affirmations matching categories
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    categories.contains(affirmation.category)
                }
            )
            
            var results = try modelContext.fetch(descriptor)
            
            // Apply source-aware smart queue sorting with exclusions
            results = applySmartQueueSorting(results, excluding: excluding)
            
            // Take limited results
            let sessionQueue = Array(results.prefix(limit))
            
            #if DEBUG
            let excludedCount = excluding.count
            let resultCount = sessionQueue.count
            print("📦 AffirmationRepository: Session queue - excluded \(excludedCount), returning \(resultCount)")
            #endif
            
            return sessionQueue
            
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
    
    func recordView(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            return // Silently ignore if not found
        }
        
        do {
            affirmation.viewCount += 1
            affirmation.hasBeenSeen = true
            affirmation.lastInteractedAt = Date()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record view: \(error.localizedDescription)")
        }
    }
    
    func recordSpeak(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            return
        }
        
        do {
            affirmation.speakCount += 1
            affirmation.lastPracticedAt = Date()
            affirmation.lastInteractedAt = Date()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record speak: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func toggleFavorite(affirmationId: UUID) throws -> Bool {
        guard let affirmation = try fetchById(affirmationId) else {
            throw AppError.loadFailed(reason: "Affirmation not found")
        }
        
        do {
            affirmation.isFavorited.toggle()
            affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
            affirmation.lastInteractedAt = Date()
            
            try modelContext.save()
            
            return affirmation.isFavorited
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    func recordSkip(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            return
        }
        
        do {
            affirmation.skipCount += 1
            affirmation.lastInteractedAt = Date()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record skip: \(error.localizedDescription)")
        }
    }
    
    func recordShare(affirmationId: UUID) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            return
        }
        
        do {
            affirmation.shareCount += 1
            affirmation.lastInteractedAt = Date()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to record share: \(error.localizedDescription)")
        }
    }
    
    func addResonanceRecord(affirmationId: UUID, record: ResonanceRecord) throws {
        guard let affirmation = try fetchById(affirmationId) else {
            return
        }
        
        do {
            affirmation.resonanceScores.append(record)
            affirmation.lastPracticedAt = Date()
            affirmation.lastInteractedAt = Date()
            
            try modelContext.save()
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to add resonance record: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Content Management
    
    func insertBatch(_ affirmations: [Affirmation]) throws {
        guard !affirmations.isEmpty else { return }
        
        do {
            for affirmation in affirmations {
                modelContext.insert(affirmation)
            }
            
            try modelContext.save()
            
            #if DEBUG
            let sources = Dictionary(grouping: affirmations, by: { $0.source })
            let sourceCounts = sources.map { "\($0.key.rawValue): \($0.value.count)" }.joined(separator: ", ")
            print("📦 AffirmationRepository: Inserted \(affirmations.count) affirmations (\(sourceCounts))")
            #endif
            
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
            
            #if DEBUG
            if count > 0 {
                print("🗑️ AffirmationRepository: Deleted \(count) expired affirmations (seeded content preserved)")
            }
            #endif
            
            return count
            
        } catch {
            throw AppError.cacheError(reason: "Failed to delete expired affirmations: \(error.localizedDescription)")
        }
    }
    
    func categoriesNeedingRefresh(from categories: [String]) throws -> [String] {
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

// MARK: - Smart Queue Sorting

private extension AffirmationRepository {
    
    /// Applies the source-aware smart queue sorting algorithm.
    ///
    /// ## Priority Order
    /// 1. Exclude IDs in `excluding` set
    /// 2. Source priority: generated (0) > backend (1) > seeded (2)
    /// 3. `hasBeenSeen == false` (unseen first)
    /// 4. `speakCount` ascending (least spoken for sessions)
    /// 5. `viewCount` ascending (least viewed)
    /// 6. `lastPracticedAt` ascending (oldest practiced, nil = never practiced)
    /// 7. Shuffle within same priority tier for variety
    ///
    /// - Parameters:
    ///   - affirmations: Unordered affirmations
    ///   - excluding: Set of IDs to exclude from results
    /// - Returns: Sorted affirmations according to smart queue algorithm
    func applySmartQueueSorting(
        _ affirmations: [Affirmation],
        excluding: Set<UUID>
    ) -> [Affirmation] {
        // Step 1: Filter out excluded IDs
        var filtered = affirmations
        if !excluding.isEmpty {
            filtered = affirmations.filter { !excluding.contains($0.id) }
        }
        
        // Step 2: Group by source priority
        var generated: [Affirmation] = []
        var backend: [Affirmation] = []
        var seeded: [Affirmation] = []
        
        for affirmation in filtered {
            switch affirmation.source {
            case .generated:
                generated.append(affirmation)
            case .backend:
                backend.append(affirmation)
            case .seeded:
                seeded.append(affirmation)
            }
        }
        
        // Step 3: Sort each tier by engagement metrics
        generated = sortByEngagement(generated)
        backend = sortByEngagement(backend)
        seeded = sortByEngagement(seeded)
        
        // Step 4: Combine in priority order
        return generated + backend + seeded
    }
    
    /// Sorts affirmations within a tier by engagement metrics.
    ///
    /// Priority:
    /// 1. Unseen first
    /// 2. Least spoken
    /// 3. Least viewed
    /// 4. Oldest practiced
    /// 5. Shuffle within same metrics for variety
    func sortByEngagement(_ affirmations: [Affirmation]) -> [Affirmation] {
        // Group by seen status
        var unseen: [Affirmation] = []
        var seen: [Affirmation] = []
        
        for affirmation in affirmations {
            if !affirmation.hasBeenSeen {
                unseen.append(affirmation)
            } else {
                seen.append(affirmation)
            }
        }
        
        // Shuffle unseen for variety
        unseen.shuffle()
        
        // Sort seen by engagement metrics
        seen.sort { a, b in
            // Primary: speakCount ascending (least spoken for session freshness)
            if a.speakCount != b.speakCount {
                return a.speakCount < b.speakCount
            }
            
            // Secondary: viewCount ascending (least viewed)
            if a.viewCount != b.viewCount {
                return a.viewCount < b.viewCount
            }
            
            // Tertiary: lastPracticedAt ascending (nil = earliest)
            let aDate = a.lastPracticedAt ?? Date.distantPast
            let bDate = b.lastPracticedAt ?? Date.distantPast
            return aDate < bDate
        }
        
        // Combine: unseen first, then seen
        return unseen + seen
    }
}
