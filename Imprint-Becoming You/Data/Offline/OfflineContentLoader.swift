//
//  OfflineContentLoader.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/5/26.
//

import Foundation
import SwiftData

// MARK: - Offline Content Loader

/// Loads bundled affirmations from JSON and seeds them into SwiftData.
///
/// This loader is responsible for:
/// - Reading the `OfflineAffirmations.json` file from the app bundle
/// - Parsing the JSON structure into `Affirmation` models
/// - Tagging all seeded content with `source = .seeded`
/// - Inserting affirmations into SwiftData on first launch
/// - Tracking seeding status via UserDefaults
///
/// ## Seeding Strategy
/// Seeding happens **once** on first launch. The loader checks a UserDefaults flag
/// to determine if seeding has already occurred. This ensures:
/// - Fast subsequent launches (no redundant parsing)
/// - User engagement data is preserved
/// - Idempotent behavior (safe to call multiple times)
///
/// ## Source Tagging
/// All seeded affirmations are tagged with `source = .seeded`, which ensures:
/// - They are NEVER deleted (even when expired)
/// - They have lowest queue priority (backend/generated content shown first)
/// - They guarantee offline availability
///
/// ## Thread Safety
/// The `init` can be called from any context. Methods that interact with
/// SwiftData are `@MainActor` isolated since `ModelContext` requires main thread access.
///
/// ## Usage
/// ```swift
/// // In App initialization
/// let loader = OfflineContentLoader()
/// try await loader.seedIfNeeded(modelContext: context)
/// ```
///
/// ## JSON Structure
/// ```json
/// {
///   "version": "1.0",
///   "lastUpdated": "2026-01-05",
///   "totalAffirmations": 1120,
///   "categories": {
///     "Confidence": ["affirmation1", "affirmation2", ...],
///     "Focus": ["affirmation1", ...],
///     ...
///   }
/// }
/// ```
final class OfflineContentLoader: Sendable {
    
    // MARK: - Constants
    
    /// UserDefaults key for tracking seeding status
    private static let seedingCompletedKey = "com.imprint.offlineContentSeeded"
    
    /// UserDefaults key for tracking seeded content version
    private static let seedingVersionKey = "com.imprint.offlineContentVersion"
    
    /// Name of the bundled JSON file
    private static let jsonFileName = "OfflineAffirmations"
    
    // MARK: - Properties
    
    /// UserDefaults for tracking seeding status
    /// Using nonisolated(unsafe) because UserDefaults is thread-safe
    nonisolated(unsafe) private let userDefaults: UserDefaults
    
    // MARK: - Initialization
    
    /// Creates a loader with the specified UserDefaults.
    ///
    /// - Parameter userDefaults: UserDefaults instance (defaults to standard)
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Public Methods
    
    /// Seeds offline content into SwiftData if not already seeded.
    ///
    /// This method is idempotent - it will only seed once, regardless of
    /// how many times it's called. Subsequent calls return immediately.
    ///
    /// All seeded affirmations are tagged with `source = .seeded` to:
    /// - Guarantee offline availability (never deleted)
    /// - Allow backend/generated content to take priority in queues
    ///
    /// - Parameter modelContext: SwiftData model context for insertion
    /// - Throws: `AppError.loadFailed` if JSON parsing fails
    /// - Throws: `AppError.saveFailed` if database insertion fails
    @MainActor
    func seedIfNeeded(modelContext: ModelContext) async throws {
        // Check if already seeded
        guard !hasBeenSeeded else {
            #if DEBUG
            print("📦 OfflineContentLoader: Already seeded, skipping")
            #endif
            return
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("📦 OfflineContentLoader: Starting seed...")
        #endif
        
        // Load and parse JSON
        let content = try loadJSONFromBundle()
        
        // Create affirmation models with source tagging
        let affirmations = createAffirmations(from: content)
        
        // Insert into SwiftData
        try insertAffirmations(affirmations, into: modelContext)
        
        // Mark as seeded
        markAsSeeded(version: content.version)
        
        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("📦 OfflineContentLoader: Seeded \(affirmations.count) affirmations (source: .seeded) in \(String(format: "%.2f", elapsed))s")
        #endif
    }
    
    /// Forces a re-seed of offline content.
    ///
    /// Use this method when:
    /// - App ships with updated content
    /// - Database needs to be reset
    ///
    /// - Warning: This clears all existing seeded affirmations before re-seeding.
    ///   Backend and generated content is preserved.
    ///
    /// - Parameter modelContext: SwiftData model context
    /// - Throws: `AppError.loadFailed` if JSON parsing fails
    /// - Throws: `AppError.saveFailed` if database operations fail
    @MainActor
    func forceReseed(modelContext: ModelContext) async throws {
        // Clear existing seeded content only
        try clearSeededContent(from: modelContext)
        
        // Reset seeding flag
        userDefaults.removeObject(forKey: Self.seedingCompletedKey)
        userDefaults.removeObject(forKey: Self.seedingVersionKey)
        
        // Re-seed
        try await seedIfNeeded(modelContext: modelContext)
    }
    
    /// Checks if content needs updating based on version.
    ///
    /// - Returns: `true` if bundled content is newer than seeded content
    func needsUpdate() -> Bool {
        guard let seededVersion = userDefaults.string(forKey: Self.seedingVersionKey) else {
            return true // Never seeded
        }
        
        do {
            let content = try loadJSONFromBundle()
            return content.version != seededVersion
        } catch {
            return false
        }
    }
    
    // MARK: - Status Properties
    
    /// Whether offline content has been seeded
    var hasBeenSeeded: Bool {
        userDefaults.bool(forKey: Self.seedingCompletedKey)
    }
    
    /// Version of the seeded content (nil if never seeded)
    var seededVersion: String? {
        userDefaults.string(forKey: Self.seedingVersionKey)
    }
}

// MARK: - Private Methods

private extension OfflineContentLoader {
    
    /// Loads and parses the JSON file from the app bundle.
    func loadJSONFromBundle() throws -> OfflineAffirmationsContent {
        guard let url = Bundle.main.url(forResource: Self.jsonFileName, withExtension: "json") else {
            throw AppError.loadFailed(reason: "OfflineAffirmations.json not found in bundle")
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(OfflineAffirmationsContent.self, from: data)
        } catch let decodingError as DecodingError {
            throw AppError.loadFailed(reason: "Failed to parse OfflineAffirmations.json: \(decodingError.localizedDescription)")
        } catch {
            throw AppError.loadFailed(reason: "Failed to read OfflineAffirmations.json: \(error.localizedDescription)")
        }
    }
    
    /// Creates Affirmation models from parsed JSON content.
    ///
    /// All affirmations are tagged with:
    /// - `source = .seeded` - Marks as bundled content
    /// - `expiresAt = Date.distantFuture` - Never expires
    /// - `isOfflineContent = true` - Legacy field sync
    func createAffirmations(from content: OfflineAffirmationsContent) -> [Affirmation] {
        var affirmations: [Affirmation] = []
        var globalIndex = 0
        
        // Create a single batch ID for all offline content
        let batchId = UUID()
        
        for (category, texts) in content.categories {
            for text in texts {
                let affirmation = Affirmation(
                    text: text,
                    category: category,
                    source: .seeded,  // CRITICAL: Tag as seeded
                    backendId: nil,   // No backend ID for seeded content
                    fetchedAt: nil,   // Not fetched from backend
                    sourcePromptId: nil,
                    generatedAt: Date(),
                    expiresAt: Date.distantFuture, // CRITICAL: Never expires
                    batchId: batchId,
                    batchIndex: globalIndex
                )
                
                affirmations.append(affirmation)
                globalIndex += 1
            }
        }
        
        return affirmations
    }
    
    /// Inserts affirmations into SwiftData.
    @MainActor
    func insertAffirmations(_ affirmations: [Affirmation], into modelContext: ModelContext) throws {
        for affirmation in affirmations {
            modelContext.insert(affirmation)
        }
        
        try modelContext.save()
    }
    
    /// Clears existing seeded content from the database.
    ///
    /// Only deletes affirmations with `source = .seeded`.
    /// Backend and generated content is preserved.
    @MainActor
    func clearSeededContent(from modelContext: ModelContext) throws {
        let seededRawValue = AffirmationSource.seeded.rawValue
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate<Affirmation> { affirmation in
                affirmation.source.rawValue == seededRawValue
            }
        )
        
        let existing = try modelContext.fetch(descriptor)
        
        for affirmation in existing {
            modelContext.delete(affirmation)
        }
        
        try modelContext.save()
        
        #if DEBUG
        print("📦 OfflineContentLoader: Cleared \(existing.count) existing seeded affirmations")
        #endif
    }
    
    /// Marks seeding as completed in UserDefaults.
    func markAsSeeded(version: String) {
        userDefaults.set(true, forKey: Self.seedingCompletedKey)
        userDefaults.set(version, forKey: Self.seedingVersionKey)
    }
}

// MARK: - JSON Model

/// Codable model for the OfflineAffirmations.json structure.
private struct OfflineAffirmationsContent: Codable, Sendable {
    
    /// Version identifier for the content
    let version: String
    
    /// Last update date (ISO format)
    let lastUpdated: String
    
    /// Total count of affirmations
    let totalAffirmations: Int
    
    /// Dictionary mapping category names to affirmation text arrays
    let categories: [String: [String]]
}
