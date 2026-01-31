//
//  MockAffirmationRepository.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/5/26.
//

import Foundation

// MARK: - Mock Affirmation Repository

/// Mock implementation of `AffirmationRepositoryProtocol` for testing and previews.
///
/// This mock provides:
/// - In-memory storage using arrays
/// - Configurable initial data
/// - Simulation of all repository operations
/// - Queue score-based sorting (matches real repository)
/// - No dependency on SwiftData
///
/// ## Error Handling Contract
///
/// This mock follows the same error handling contract as `AffirmationRepository`:
/// - **Input validation errors**: Throws `AppError.validationFailed` for empty categories or non-positive limits
/// - **Entity not found**: Returns `nil` or empty array for fetch methods
/// - **Best-effort operations**: Engagement tracking silently ignores missing entities
/// - **User actions**: `toggleFavorite` throws if entity not found
///
/// ## Queue Score Algorithm
///
/// Uses the same pre-computed `queueScore` formula as the real repository:
/// ```
/// score = (source.priority * 10000)
///       + (hasBeenSeen ? 5000 : 0)
///       + (speakCount * 100)
///       + viewCount
/// ```
///
/// ## Usage
/// ```swift
/// let mock = MockAffirmationRepository()
///
/// // Pre-populate with test data
/// mock.mockAffirmations = [Affirmation.sample]
///
/// // Use in tests
/// let queue = try mock.fetchQueue(forCategories: ["Confidence"], limit: 10)
/// let session = try mock.fetchSessionQueue(
///     forCategories: ["Confidence"],
///     excluding: Set(queue.prefix(5).map { $0.id }),
///     limit: 10
/// )
/// ```
@MainActor
final class MockAffirmationRepository: AffirmationRepositoryProtocol {
    
    // MARK: - Mock Data
    
    /// In-memory storage for mock affirmations
    var mockAffirmations: [Affirmation] = Affirmation.samples
    
    /// Error to throw on next operation (for testing error handling)
    var errorToThrow: AppError?
    
    // MARK: - Call Tracking
    
    /// Number of times `fetchQueue` was called
    private(set) var fetchQueueCallCount = 0
    
    /// Number of times `fetchSessionQueue` was called
    private(set) var fetchSessionQueueCallCount = 0
    
    /// Number of times `recordView` was called
    private(set) var recordViewCallCount = 0
    
    /// Number of times `recordSpeak` was called
    private(set) var recordSpeakCallCount = 0
    
    /// Number of times `toggleFavorite` was called
    private(set) var toggleFavoriteCallCount = 0
    
    /// Number of times `insertBatch` was called
    private(set) var insertBatchCallCount = 0
    
    /// Last exclusion set passed to `fetchSessionQueue`
    private(set) var lastSessionExclusionSet: Set<UUID> = []
    
    // MARK: - Initialization
    
    init() {}
    
    /// Creates a mock with pre-populated data
    /// - Parameter affirmations: Initial affirmations
    init(affirmations: [Affirmation]) {
        self.mockAffirmations = affirmations
    }
    
    // MARK: - Queue Fetching
    
    func fetchQueue(forCategories categories: [String], limit: Int) throws -> [Affirmation] {
        try throwIfErrorConfigured()
        
        // Validate input - throw for invalid parameters (matches real repository)
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
        
        fetchQueueCallCount += 1
        
        // Filter by categories
        let filtered = mockAffirmations.filter { categories.contains($0.category) }
        
        // Sort by queueScore (matches real repository database-level sorting)
        let sorted = filtered.sorted { $0.queueScore < $1.queueScore }
        
        // Take limit and shuffle within score tiers for variety
        let limited = Array(sorted.prefix(limit))
        return shuffleWithinScoreTiers(limited)
    }
    
    func fetchSessionQueue(
        forCategories categories: [String],
        excluding: Set<UUID>,
        limit: Int
    ) throws -> [Affirmation] {
        try throwIfErrorConfigured()
        
        // Validate input - throw for invalid parameters (matches real repository)
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
        
        fetchSessionQueueCallCount += 1
        lastSessionExclusionSet = excluding
        
        // Filter by categories
        var filtered = mockAffirmations.filter { categories.contains($0.category) }
        
        // Filter out excluded IDs
        if !excluding.isEmpty {
            filtered = filtered.filter { !excluding.contains($0.id) }
        }
        
        // Sort by queueScore (matches real repository database-level sorting)
        let sorted = filtered.sorted { $0.queueScore < $1.queueScore }
        
        // Take limit and shuffle within score tiers for variety
        let limited = Array(sorted.prefix(limit))
        return shuffleWithinScoreTiers(limited)
    }
    
    // MARK: - Basic Fetching
    
    func fetchFavorites() throws -> [Affirmation] {
        try throwIfErrorConfigured()
        
        return mockAffirmations
            .filter { $0.isFavorited }
            .sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
    }
    
    func fetchByIds(_ ids: [UUID]) throws -> [Affirmation] {
        try throwIfErrorConfigured()
        
        // Empty input returns empty result - not an error
        guard !ids.isEmpty else { return [] }
        
        return mockAffirmations.filter { ids.contains($0.id) }
    }
    
    func fetchById(_ id: UUID) throws -> Affirmation? {
        try throwIfErrorConfigured()
        
        // Return nil if not found - not an error
        return mockAffirmations.first { $0.id == id }
    }
    
    // MARK: - Counting
    
    func countTotal() throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.count
    }
    
    func countForCategories(_ categories: [String]) throws -> Int {
        try throwIfErrorConfigured()
        
        // Empty categories returns 0 - not an error
        guard !categories.isEmpty else { return 0 }
        
        return mockAffirmations.filter { categories.contains($0.category) }.count
    }
    
    func countBySource(_ source: AffirmationSource) throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.filter { $0.source == source }.count
    }
    
    // MARK: - Engagement Tracking
    //
    // These are "best effort" operations - they silently ignore missing entities
    // since the user action has already completed.
    //
    // IMPORTANT: All engagement tracking methods must call recalculateQueueScore()
    // after updating engagement metrics to keep sorting accurate.
    
    func recordView(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        recordViewCallCount += 1
        
        // Silently ignore if not found (best effort)
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].viewCount += 1
            mockAffirmations[index].hasBeenSeen = true
            mockAffirmations[index].lastInteractedAt = Date()
            
            // Recalculate queue score for sorting
            mockAffirmations[index].recalculateQueueScore()
        }
    }
    
    func recordSpeak(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        recordSpeakCallCount += 1
        
        // Silently ignore if not found (best effort)
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].speakCount += 1
            mockAffirmations[index].lastPracticedAt = Date()
            mockAffirmations[index].lastInteractedAt = Date()
            
            // Recalculate queue score for sorting
            mockAffirmations[index].recalculateQueueScore()
        }
    }
    
    @discardableResult
    func toggleFavorite(affirmationId: UUID) throws -> Bool {
        try throwIfErrorConfigured()
        toggleFavoriteCallCount += 1
        
        // For user-initiated actions, not finding the entity IS an error
        guard let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) else {
            throw AppError.loadFailed(reason: "Affirmation not found")
        }
        
        mockAffirmations[index].isFavorited.toggle()
        mockAffirmations[index].favoritedAt = mockAffirmations[index].isFavorited ? Date() : nil
        mockAffirmations[index].lastInteractedAt = Date()
        
        // Note: toggleFavorite doesn't affect queueScore (not in formula)
        
        return mockAffirmations[index].isFavorited
    }
    
    func recordSkip(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        
        // Silently ignore if not found (best effort)
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].skipCount += 1
            mockAffirmations[index].lastInteractedAt = Date()
            
            // Note: skipCount doesn't affect queueScore (not in formula)
        }
    }
    
    func recordShare(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        
        // Silently ignore if not found (best effort)
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].shareCount += 1
            mockAffirmations[index].lastInteractedAt = Date()
            
            // Note: shareCount doesn't affect queueScore (not in formula)
        }
    }
    
    func addResonanceRecord(affirmationId: UUID, record: ResonanceRecord) throws {
        try throwIfErrorConfigured()
        
        // Silently ignore if not found (best effort)
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].resonanceScores.append(record)
            mockAffirmations[index].lastPracticedAt = Date()
            mockAffirmations[index].lastInteractedAt = Date()
            
            // Note: resonanceScores doesn't affect queueScore (not in formula)
        }
    }
    
    // MARK: - Content Management
    
    func insertBatch(_ affirmations: [Affirmation]) throws {
        try throwIfErrorConfigured()
        insertBatchCallCount += 1
        
        // Empty batch is a no-op - not an error
        guard !affirmations.isEmpty else { return }
        
        // Ensure queueScore is calculated for each new affirmation
        for affirmation in affirmations {
            affirmation.recalculateQueueScore()
        }
        
        mockAffirmations.append(contentsOf: affirmations)
    }
    
    @discardableResult
    func deleteExpired() throws -> Int {
        try throwIfErrorConfigured()
        
        let now = Date()
        let initialCount = mockAffirmations.count
        
        // Only delete non-seeded content that has expired
        mockAffirmations.removeAll { affirmation in
            affirmation.expiresAt < now && affirmation.source != .seeded
        }
        
        return initialCount - mockAffirmations.count
    }
    
    func categoriesNeedingRefresh(from categories: [String]) throws -> [String] {
        try throwIfErrorConfigured()
        
        // Empty categories returns empty result - not an error
        guard !categories.isEmpty else { return [] }
        
        let threshold = Constants.ContentRefresh.depletedViewCountThreshold
        var depleted: [String] = []
        
        for category in categories {
            let freshCount = mockAffirmations.filter {
                $0.category == category && $0.viewCount < threshold
            }.count
            
            if freshCount == 0 {
                depleted.append(category)
            }
        }
        
        return depleted
    }
    
    // MARK: - Test Helpers
    
    /// Resets all call counts
    func resetCallCounts() {
        fetchQueueCallCount = 0
        fetchSessionQueueCallCount = 0
        recordViewCallCount = 0
        recordSpeakCallCount = 0
        toggleFavoriteCallCount = 0
        insertBatchCallCount = 0
        lastSessionExclusionSet = []
    }
    
    /// Resets mock to default state
    func reset() {
        mockAffirmations = Affirmation.samples
        errorToThrow = nil
        resetCallCounts()
    }
    
    /// Adds test affirmations with specific sources
    func addTestAffirmations(count: Int, source: AffirmationSource, category: String) {
        for i in 0..<count {
            let affirmation = Affirmation(
                text: "Test affirmation \(i) from \(source.rawValue)",
                category: category,
                source: source,
                batchIndex: mockAffirmations.count + i
            )
            // queueScore is auto-calculated in init
            mockAffirmations.append(affirmation)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Throws configured error if set
    private func throwIfErrorConfigured() throws {
        if let error = errorToThrow {
            errorToThrow = nil // Clear after throwing
            throw error
        }
    }
    
    /// Shuffles results while keeping same-score items together for variety.
    ///
    /// This matches the real repository's behavior of providing randomness
    /// within priority tiers without breaking overall priority order.
    ///
    /// - Parameter affirmations: Sorted affirmations
    /// - Returns: Affirmations with same-score tiers shuffled for variety
    private func shuffleWithinScoreTiers(_ affirmations: [Affirmation]) -> [Affirmation] {
        // Early return for small arrays where shuffling has minimal effect
        guard affirmations.count > 2 else { return affirmations }
        
        // Group by queueScore
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
