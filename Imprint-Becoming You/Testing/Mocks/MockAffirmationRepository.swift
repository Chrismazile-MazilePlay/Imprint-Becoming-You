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
    
    /// Number of times `recordView` was called
    private(set) var recordViewCallCount = 0
    
    /// Number of times `recordSpeak` was called
    private(set) var recordSpeakCallCount = 0
    
    /// Number of times `toggleFavorite` was called
    private(set) var toggleFavoriteCallCount = 0
    
    /// Number of times `insertBatch` was called
    private(set) var insertBatchCallCount = 0
    
    // MARK: - Initialization
    
    init() {}
    
    /// Creates a mock with pre-populated data
    /// - Parameter affirmations: Initial affirmations
    init(affirmations: [Affirmation]) {
        self.mockAffirmations = affirmations
    }
    
    // MARK: - Fetching
    
    func fetchQueue(forCategories categories: [String], limit: Int) throws -> [Affirmation] {
        try throwIfErrorConfigured()
        fetchQueueCallCount += 1
        
        let filtered = mockAffirmations.filter { categories.contains($0.category) }
        
        // Apply simple smart queue logic (unseen first)
        let sorted = filtered.sorted { a, b in
            if a.hasBeenSeen != b.hasBeenSeen {
                return !a.hasBeenSeen
            }
            return a.viewCount < b.viewCount
        }
        
        return Array(sorted.prefix(limit))
    }
    
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
    
    func countTotal() throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.count
    }
    
    func countForCategories(_ categories: [String]) throws -> Int {
        try throwIfErrorConfigured()
        
        return mockAffirmations.filter { categories.contains($0.category) }.count
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
        
        mockAffirmations.removeAll { affirmation in
            affirmation.expiresAt < now && !affirmation.isOfflineContent
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
        recordViewCallCount = 0
        recordSpeakCallCount = 0
        toggleFavoriteCallCount = 0
        insertBatchCallCount = 0
    }
    
    /// Resets mock to default state
    func reset() {
        mockAffirmations = Affirmation.samples
        errorToThrow = nil
        resetCallCounts()
    }
    
    // MARK: - Private Helpers
    
    /// Throws configured error if set
    private func throwIfErrorConfigured() throws {
        if let error = errorToThrow {
            errorToThrow = nil // Clear after throwing
            throw error
        }
    }
}
