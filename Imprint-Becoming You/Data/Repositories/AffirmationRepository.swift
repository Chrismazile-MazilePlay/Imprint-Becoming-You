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
/// - Smart queue fetching with priority ordering
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
/// 1. hasBeenSeen == false (unseen first)
/// 2. viewCount ascending (least viewed)
/// 3. lastPracticedAt ascending (oldest practiced)
/// 4. Shuffle within same priority tier
/// ```
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
    
    // MARK: - Fetching
    
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
            
            // Apply smart queue sorting
            results = applySmartQueueSorting(results)
            
            // Limit results
            return Array(results.prefix(limit))
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch affirmation queue: \(error.localizedDescription)")
        }
    }
    
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
            print("📦 AffirmationRepository: Inserted \(affirmations.count) affirmations")
            #endif
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to insert affirmation batch: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func deleteExpired() throws -> Int {
        let now = Date()
        
        do {
            // Only delete non-offline content that has expired
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    affirmation.expiresAt < now && !affirmation.isOfflineContent
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
                print("🗑️ AffirmationRepository: Deleted \(count) expired affirmations")
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
    
    /// Applies the smart queue sorting algorithm.
    ///
    /// ## Priority Order
    /// 1. `hasBeenSeen == false` (unseen first)
    /// 2. `viewCount` ascending (least viewed)
    /// 3. `lastPracticedAt` ascending (oldest practiced, nil = never practiced)
    /// 4. Shuffle within same priority tier for variety
    ///
    /// - Parameter affirmations: Unordered affirmations
    /// - Returns: Sorted affirmations according to smart queue algorithm
    func applySmartQueueSorting(_ affirmations: [Affirmation]) -> [Affirmation] {
        // Group by priority tier
        var unseen: [Affirmation] = []
        var seen: [Affirmation] = []
        
        for affirmation in affirmations {
            if !affirmation.hasBeenSeen {
                unseen.append(affirmation)
            } else {
                seen.append(affirmation)
            }
        }
        
        // Shuffle within tiers for variety
        unseen.shuffle()
        
        // Sort seen by viewCount, then by lastPracticedAt
        seen.sort { a, b in
            // Primary: viewCount ascending
            if a.viewCount != b.viewCount {
                return a.viewCount < b.viewCount
            }
            
            // Secondary: lastPracticedAt ascending (nil = earliest)
            let aDate = a.lastPracticedAt ?? Date.distantPast
            let bDate = b.lastPracticedAt ?? Date.distantPast
            return aDate < bDate
        }
        
        // Combine: unseen first, then seen
        return unseen + seen
    }
}
