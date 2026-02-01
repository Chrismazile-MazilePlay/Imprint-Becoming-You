//
//  SavedSessionRepository.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import Foundation
import SwiftData

// MARK: - SavedSessionRepository

/// SwiftData implementation of the saved session repository.
///
/// Provides data access operations for saved sessions including:
/// - CRUD operations for saved sessions
/// - Affirmation fetching for playback
/// - Duplicate detection
/// - Sort order management
///
/// ## Thread Safety
/// This class is `@MainActor` isolated because SwiftData's `ModelContext`
/// must be accessed from the main thread. All operations are synchronous.
///
/// ## Base Repository Conformance
/// This repository conforms to `BaseRepositoryProtocol`, inheriting:
/// - `insert(_:)` - Inserts a single session (prefer `save(_:)` for relationship setup)
/// - `delete(_:)` - Deletes a single session (prefer domain `delete(_:)` for cleanup)
/// - `save()` - Saves pending changes
///
/// Note: `fetchAll()` is overridden to provide specific sort ordering.
/// Note: `count()` is available from the protocol for basic counting needs.
///
/// ## Error Handling Strategy
///
/// This repository follows a consistent error handling contract:
///
/// - **Empty input**: Return empty array or `false` for queries with empty input.
///   This is expected behavior, not an error condition.
///
/// - **Entity not found**: Return `nil` for fetch-by-ID methods.
///   This is expected behavior, not an error condition.
///
/// - **Best-effort operations**: The `recordPlayback` method logs and returns
///   gracefully when the session is not found, since the user action has
///   already completed and this is non-critical tracking.
///
/// - **Database errors**: Throw `AppError.loadFailed` for fetch failures and
///   `AppError.saveFailed` for write failures.
///
/// ## Affirmation Protection
/// When a saved session is created, relationships are established with
/// the referenced affirmations. This enables `Affirmation.isProtected`
/// to return true, preventing deletion of those affirmations.
@MainActor
final class SavedSessionRepository: BaseRepositoryProtocol, SavedSessionRepositoryProtocol {
    
    // MARK: - BaseRepositoryProtocol Conformance
    
    /// The model type this repository manages.
    typealias Model = SavedSession
    
    /// The SwiftData model context for database operations.
    ///
    /// Exposed as `let` (not `private`) to satisfy `BaseRepositoryProtocol` requirements,
    /// enabling default implementations for common CRUD operations.
    let modelContext: ModelContext
    
    // MARK: - Initialization
    
    /// Creates a repository with the given model context.
    ///
    /// - Parameter modelContext: SwiftData model context for database operations
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetching
    
    /// Fetches all saved sessions ordered by sort order.
    ///
    /// - Returns: Array of saved sessions, sorted by `sortOrder` ascending
    /// - Throws: `AppError.loadFailed` if fetch fails
    ///
    /// - Note: This overrides the `BaseRepositoryProtocol` default to provide
    ///   specific sort ordering required for the saved sessions list.
    func fetchAll() throws -> [SavedSession] {
        do {
            let descriptor = FetchDescriptor<SavedSession>(
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch saved sessions: \(error.localizedDescription)")
        }
    }
    
    /// Fetches a saved session by its unique identifier.
    ///
    /// - Parameter id: The UUID of the session to fetch
    /// - Returns: The session if found, `nil` otherwise
    /// - Throws: `AppError.loadFailed` if the fetch operation fails
    ///
    /// - Note: This method is required by `BaseRepositoryProtocol` but cannot use
    ///   a default implementation due to Swift macro limitations with generic predicates.
    func fetchById(_ id: UUID) throws -> SavedSession? {
        do {
            let descriptor = FetchDescriptor<SavedSession>(
                predicate: #Predicate<SavedSession> { session in
                    session.id == id
                }
            )
            // Return nil if not found - not an error
            return try modelContext.fetch(descriptor).first
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch saved session: \(error.localizedDescription)")
        }
    }
    
    func fetchAffirmations(byIds ids: [UUID]) throws -> [Affirmation] {
        // Empty input returns empty result - not an error
        guard !ids.isEmpty else { return [] }
        
        do {
            // Fetch all matching affirmations
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate<Affirmation> { affirmation in
                    ids.contains(affirmation.id)
                }
            )
            let fetched = try modelContext.fetch(descriptor)
            
            // Create lookup dictionary
            let idToAffirmation = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            
            // Return in original order, filtering out any missing
            return ids.compactMap { idToAffirmation[$0] }
            
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch affirmations: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Counting
    
    /// Counts total saved sessions.
    ///
    /// - Returns: Total count of saved sessions
    /// - Throws: `AppError.loadFailed` if count fails
    ///
    /// - Note: This overrides the `BaseRepositoryProtocol` default to provide
    ///   consistent error messaging.
    func count() throws -> Int {
        do {
            let descriptor = FetchDescriptor<SavedSession>()
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw AppError.loadFailed(reason: "Failed to count saved sessions: \(error.localizedDescription)")
        }
    }
    
    func exists(withAffirmationIds ids: [UUID]) throws -> Bool {
        // Empty input returns false - not an error
        guard !ids.isEmpty else { return false }
        
        do {
            let allSessions = try fetchAll()
            
            // Check if any session has the exact same affirmation IDs
            let targetSet = Set(ids)
            for session in allSessions {
                let sessionSet = Set(session.affirmationIds)
                if sessionSet == targetSet {
                    return true
                }
            }
            
            return false
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.loadFailed(reason: "Failed to check for existing session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Persistence
    
    func save(_ session: SavedSession) throws {
        do {
            // Fetch and link affirmations for relationship
            let affirmations = try fetchAffirmations(byIds: session.affirmationIds)
            session.affirmations = affirmations
            
            // Set sort order to end of list
            let currentCount = try count()
            session.sortOrder = currentCount
            
            modelContext.insert(session)
            try modelContext.save()
            
            AppLogger.info(
                "Saved session",
                category: .data,
                context: ["name": session.name, "affirmationCount": affirmations.count]
            )
            
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.saveFailed(reason: "Failed to save session: \(error.localizedDescription)")
        }
    }
    
    func update(_ session: SavedSession) throws {
        do {
            try modelContext.save()
            
            AppLogger.debug(
                "Updated session",
                category: .data,
                context: ["name": session.name]
            )
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to update session: \(error.localizedDescription)")
        }
    }
    
    /// Deletes a saved session with proper cleanup.
    ///
    /// - Parameter session: The session to delete
    /// - Throws: `AppError.saveFailed` if delete fails
    ///
    /// - Note: This overrides the `BaseRepositoryProtocol` default to provide
    ///   proper relationship cleanup before deletion.
    func delete(_ session: SavedSession) throws {
        do {
            let sessionName = session.name
            
            // Clear relationships first
            session.affirmations = []
            
            modelContext.delete(session)
            try modelContext.save()
            
            AppLogger.info(
                "Deleted session",
                category: .data,
                context: ["name": sessionName]
            )
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to delete session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Ordering
    
    func updateSortOrder(_ sessions: [SavedSession]) throws {
        do {
            for (index, session) in sessions.enumerated() {
                session.sortOrder = index
            }
            try modelContext.save()
            
            AppLogger.debug(
                "Updated sort order",
                category: .data,
                context: ["sessionCount": sessions.count]
            )
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to update sort order: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Playback Tracking
    //
    // This is a "best effort" operation - logs and returns gracefully
    // when session is not found since playback has already completed.
    
    func recordPlayback(sessionId: UUID) throws {
        do {
            guard let session = try fetchById(sessionId) else {
                // Session not found is expected for deleted sessions - log and return
                AppLogger.debug(
                    "Session not found for playback recording",
                    category: .data,
                    context: ["sessionId": sessionId.uuidString]
                )
                return
            }
            
            session.recordPlayback()
            try modelContext.save()
            
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.saveFailed(reason: "Failed to record playback: \(error.localizedDescription)")
        }
    }
}

// MARK: - Mock Implementation

/// Mock implementation for previews and testing
@MainActor
final class MockSavedSessionRepository: SavedSessionRepositoryProtocol {
    
    // MARK: - Properties
    
    var savedSessions: [SavedSession] = SavedSession.samples
    var mockAffirmations: [Affirmation] = Affirmation.samples
    
    // MARK: - Fetching
    
    func fetchAll() throws -> [SavedSession] {
        savedSessions.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    func fetchById(_ id: UUID) throws -> SavedSession? {
        savedSessions.first { $0.id == id }
    }
    
    func fetchAffirmations(byIds ids: [UUID]) throws -> [Affirmation] {
        guard !ids.isEmpty else { return [] }
        let idToAffirmation = Dictionary(uniqueKeysWithValues: mockAffirmations.map { ($0.id, $0) })
        return ids.compactMap { idToAffirmation[$0] }
    }
    
    // MARK: - Counting
    
    func count() throws -> Int {
        savedSessions.count
    }
    
    func exists(withAffirmationIds ids: [UUID]) throws -> Bool {
        guard !ids.isEmpty else { return false }
        let targetSet = Set(ids)
        return savedSessions.contains { Set($0.affirmationIds) == targetSet }
    }
    
    // MARK: - Persistence
    
    func save(_ session: SavedSession) throws {
        session.sortOrder = savedSessions.count
        savedSessions.append(session)
    }
    
    func update(_ session: SavedSession) throws {
        // No-op for mock - object is already updated
    }
    
    func delete(_ session: SavedSession) throws {
        savedSessions.removeAll { $0.id == session.id }
    }
    
    // MARK: - Ordering
    
    func updateSortOrder(_ sessions: [SavedSession]) throws {
        for (index, session) in sessions.enumerated() {
            session.sortOrder = index
        }
    }
    
    // MARK: - Playback Tracking
    
    func recordPlayback(sessionId: UUID) throws {
        if let session = savedSessions.first(where: { $0.id == sessionId }) {
            session.recordPlayback()
        }
        // Mock: silently ignore if not found
    }
}
