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
/// - Source-aware queue sorting
/// - No dependency on SwiftData
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
        fetchQueueCallCount += 1
        
        let filtered = mockAffirmations.filter { categories.contains($0.category) }
        
        // Apply source-aware smart queue logic
        let sorted = applySmartQueueSorting(filtered, excluding: [])
        
        return Array(sorted.prefix(limit))
    }
    
    func fetchSessionQueue(
        forCategories categories: [String],
        excluding: Set<UUID>,
        limit: Int
    ) throws -> [Affirmation] {
        try throwIfErrorConfigured()
        fetchSessionQueueCallCount += 1
        lastSessionExclusionSet = excluding
        
        let filtered = mockAffirmations.filter { categories.contains($0.category) }
        
        // Apply source-aware smart queue logic with exclusions
        let sorted = applySmartQueueSorting(filtered, excluding: excluding)
        
        return Array(sorted.prefix(limit))
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
        
        return mockAffirmations.filter { ids.contains($0.id) }
    }
    
    func fetchById(_ id: UUID) throws -> Affirmation? {
        try throwIfErrorConfigured()
        
        return mockAffirmations.first { $0.id == id }
    }
    
    // MARK: - Counting
    
    func countTotal() throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.count
    }
    
    func countForCategories(_ categories: [String]) throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.filter { categories.contains($0.category) }.count
    }
    
    func countBySource(_ source: AffirmationSource) throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.filter { $0.source == source }.count
    }
    
    // MARK: - Engagement Tracking
    
    func recordView(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        recordViewCallCount += 1
        
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].viewCount += 1
            mockAffirmations[index].hasBeenSeen = true
            mockAffirmations[index].lastInteractedAt = Date()
        }
    }
    
    func recordSpeak(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        recordSpeakCallCount += 1
        
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].speakCount += 1
            mockAffirmations[index].lastPracticedAt = Date()
            mockAffirmations[index].lastInteractedAt = Date()
        }
    }
    
    @discardableResult
    func toggleFavorite(affirmationId: UUID) throws -> Bool {
        try throwIfErrorConfigured()
        toggleFavoriteCallCount += 1
        
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].isFavorited.toggle()
            mockAffirmations[index].favoritedAt = mockAffirmations[index].isFavorited ? Date() : nil
            mockAffirmations[index].lastInteractedAt = Date()
            return mockAffirmations[index].isFavorited
        }
        
        throw AppError.loadFailed(reason: "Affirmation not found")
    }
    
    func recordSkip(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].skipCount += 1
            mockAffirmations[index].lastInteractedAt = Date()
        }
    }
    
    func recordShare(affirmationId: UUID) throws {
        try throwIfErrorConfigured()
        
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].shareCount += 1
            mockAffirmations[index].lastInteractedAt = Date()
        }
    }
    
    func addResonanceRecord(affirmationId: UUID, record: ResonanceRecord) throws {
        try throwIfErrorConfigured()
        
        if let index = mockAffirmations.firstIndex(where: { $0.id == affirmationId }) {
            mockAffirmations[index].resonanceScores.append(record)
            mockAffirmations[index].lastPracticedAt = Date()
            mockAffirmations[index].lastInteractedAt = Date()
        }
    }
    
    // MARK: - Content Management
    
    func insertBatch(_ affirmations: [Affirmation]) throws {
        try throwIfErrorConfigured()
        insertBatchCallCount += 1
        
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
    
    /// Applies source-aware smart queue sorting.
    private func applySmartQueueSorting(
        _ affirmations: [Affirmation],
        excluding: Set<UUID>
    ) -> [Affirmation] {
        // Filter out excluded IDs
        var filtered = affirmations
        if !excluding.isEmpty {
            filtered = affirmations.filter { !excluding.contains($0.id) }
        }
        
        // Group by source priority
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
        
        // Sort each tier
        generated = sortByEngagement(generated)
        backend = sortByEngagement(backend)
        seeded = sortByEngagement(seeded)
        
        // Combine in priority order
        return generated + backend + seeded
    }
    
    /// Sorts by engagement metrics.
    private func sortByEngagement(_ affirmations: [Affirmation]) -> [Affirmation] {
        var unseen: [Affirmation] = []
        var seen: [Affirmation] = []
        
        for affirmation in affirmations {
            if !affirmation.hasBeenSeen {
                unseen.append(affirmation)
            } else {
                seen.append(affirmation)
            }
        }
        
        unseen.shuffle()
        
        seen.sort { a, b in
            if a.speakCount != b.speakCount {
                return a.speakCount < b.speakCount
            }
            if a.viewCount != b.viewCount {
                return a.viewCount < b.viewCount
            }
            return true
        }
        
        return unseen + seen
    }
}
