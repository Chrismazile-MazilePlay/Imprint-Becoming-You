//
//  SavedSessionRepositoryProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import Foundation

// MARK: - SavedSessionRepositoryProtocol

/// Protocol defining data access operations for saved sessions.
///
/// ## Thread Safety
/// All methods are `@MainActor` isolated because SwiftData's `ModelContext`
/// must be accessed from the main thread.
///
/// ## Error Handling Contract
///
/// This protocol follows a consistent error handling strategy:
///
/// ### Fetch Methods
/// | Scenario | Pattern | Example |
/// |----------|---------|---------|
/// | Empty input (IDs array) | Return empty array | `fetchAffirmations(byIds: [])` → `[]` |
/// | Entity not found | Return `nil` | `fetchById(_:)` → `nil` |
/// | Database error | Throw `AppError.loadFailed` | SwiftData fetch failure |
///
/// ### Mutation Methods
/// | Scenario | Pattern | Example |
/// |----------|---------|---------|
/// | Database error on save | Throw `AppError.saveFailed` | SwiftData save failure |
/// | Database error on delete | Throw `AppError.saveFailed` | SwiftData delete failure |
///
/// ### Playback Tracking
/// | Scenario | Pattern | Example |
/// |----------|---------|---------|
/// | Session not found | Log + return gracefully | `recordPlayback` for deleted session |
/// | Database error | Throw `AppError.saveFailed` | SwiftData save failure |
///
/// The `recordPlayback` method is a "best effort" operation that logs and returns
/// gracefully when the session is not found, since the user action has already completed.
///
/// ## Usage
/// ```swift
/// // Fetch all saved sessions
/// let sessions = try repository.fetchAll()
///
/// // Save a new session
/// let session = SavedSession(name: "Morning", ...)
/// try repository.save(session)
///
/// // Get affirmations for playback
/// let affirmations = try repository.fetchAffirmations(byIds: session.affirmationIds)
/// ```
@MainActor
protocol SavedSessionRepositoryProtocol {
    
    // MARK: - Fetching
    
    /// Fetches all saved sessions ordered by sort order.
    ///
    /// - Returns: Array of saved sessions, sorted by `sortOrder` ascending
    /// - Throws: `AppError.loadFailed` if fetch fails
    func fetchAll() throws -> [SavedSession]
    
    /// Fetches a saved session by ID.
    ///
    /// - Parameter id: The saved session UUID
    /// - Returns: The saved session if found, `nil` otherwise
    /// - Throws: `AppError.loadFailed` if fetch fails
    /// - Note: Returns `nil` if not found (not an error)
    func fetchById(_ id: UUID) throws -> SavedSession?
    
    /// Fetches affirmations by their IDs in the specified order.
    ///
    /// Used when loading a saved session for playback - returns affirmations
    /// in the same order as the provided IDs array.
    ///
    /// - Parameter ids: Array of affirmation UUIDs in desired order
    /// - Returns: Array of affirmations matching the IDs, preserving order
    /// - Throws: `AppError.loadFailed` if fetch fails
    /// - Note: Returns empty array if `ids` is empty (not an error)
    func fetchAffirmations(byIds ids: [UUID]) throws -> [Affirmation]
    
    // MARK: - Counting
    
    /// Counts total number of saved sessions.
    ///
    /// - Returns: Count of saved sessions
    /// - Throws: `AppError.loadFailed` if count fails
    func count() throws -> Int
    
    /// Checks if a session with the given affirmation IDs already exists.
    ///
    /// Used to prevent duplicate saves of the same session.
    ///
    /// - Parameter ids: Array of affirmation UUIDs to check
    /// - Returns: `true` if a saved session with these exact IDs exists
    /// - Throws: `AppError.loadFailed` if check fails
    /// - Note: Returns `false` if `ids` is empty (not an error)
    func exists(withAffirmationIds ids: [UUID]) throws -> Bool
    
    // MARK: - Persistence
    
    /// Saves a new saved session to the database.
    ///
    /// Also establishes relationships with the referenced affirmations
    /// to enable reference counting protection.
    ///
    /// - Parameter session: The saved session to persist
    /// - Throws: `AppError.saveFailed` if save fails
    func save(_ session: SavedSession) throws
    
    /// Updates an existing saved session.
    ///
    /// - Parameter session: The saved session with updated values
    /// - Throws: `AppError.saveFailed` if update fails
    func update(_ session: SavedSession) throws
    
    /// Deletes a saved session.
    ///
    /// This also removes the affirmation relationships, potentially
    /// allowing those affirmations to be deleted if no longer protected.
    ///
    /// - Parameter session: The saved session to delete
    /// - Throws: `AppError.saveFailed` if deletion fails
    func delete(_ session: SavedSession) throws
    
    // MARK: - Ordering
    
    /// Updates the sort order of saved sessions.
    ///
    /// Used when user reorders sessions in the list.
    ///
    /// - Parameter sessions: Array of sessions in their new order
    /// - Throws: `AppError.saveFailed` if update fails
    func updateSortOrder(_ sessions: [SavedSession]) throws
    
    // MARK: - Playback Tracking
    
    /// Records that a saved session was played.
    ///
    /// Updates the `lastPlayedAt` timestamp.
    ///
    /// - Parameter sessionId: The ID of the session that was played
    /// - Throws: `AppError.saveFailed` if update fails
    /// - Note: Logs and returns gracefully if session not found (best effort operation)
    func recordPlayback(sessionId: UUID) throws
}
