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
/// ## Affirmation Protection
/// When a saved session is created, relationships are established with
/// the referenced affirmations. This enables `Affirmation.isProtected`
/// to return true, preventing deletion of those affirmations.
@MainActor
final class SavedSessionRepository: SavedSessionRepositoryProtocol {
    
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
    
    func fetchById(_ id: UUID) throws -> SavedSession? {
        do {
            let descriptor = FetchDescriptor<SavedSession>(
                predicate: #Predicate<SavedSession> { session in
                    session.id == id
                }
            )
            return try modelContext.fetch(descriptor).first
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch saved session: \(error.localizedDescription)")
        }
    }
    
    func fetchAffirmations(byIds ids: [UUID]) throws -> [Affirmation] {
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
    
    func count() throws -> Int {
        do {
            let descriptor = FetchDescriptor<SavedSession>()
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw AppError.loadFailed(reason: "Failed to count saved sessions: \(error.localizedDescription)")
        }
    }
    
    func exists(withAffirmationIds ids: [UUID]) throws -> Bool {
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
            
            #if DEBUG
            print("[OK] SavedSessionRepository: Saved session '\(session.name)' with \(affirmations.count) affirmations")
            #endif
            
        } catch let appError as AppError {
            throw appError
        } catch {
            throw AppError.saveFailed(reason: "Failed to save session: \(error.localizedDescription)")
        }
    }
    
    func update(_ session: SavedSession) throws {
        do {
            try modelContext.save()
            
            #if DEBUG
            print("[OK] SavedSessionRepository: Updated session '\(session.name)'")
            #endif
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to update session: \(error.localizedDescription)")
        }
    }
    
    func delete(_ session: SavedSession) throws {
        do {
            // Clear relationships first
            session.affirmations = []
            
            modelContext.delete(session)
            try modelContext.save()
            
            #if DEBUG
            print("[OK] SavedSessionRepository: Deleted session '\(session.name)'")
            #endif
            
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
            
            #if DEBUG
            print("[OK] SavedSessionRepository: Updated sort order for \(sessions.count) sessions")
            #endif
            
        } catch {
            throw AppError.saveFailed(reason: "Failed to update sort order: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Playback Tracking
    
    func recordPlayback(sessionId: UUID) throws {
        do {
            guard let session = try fetchById(sessionId) else {
                #if DEBUG
                print("[WARN] SavedSessionRepository: Session not found for playback recording")
                #endif
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
        let idToAffirmation = Dictionary(uniqueKeysWithValues: mockAffirmations.map { ($0.id, $0) })
        return ids.compactMap { idToAffirmation[$0] }
    }
    
    // MARK: - Counting
    
    func count() throws -> Int {
        savedSessions.count
    }
    
    func exists(withAffirmationIds ids: [UUID]) throws -> Bool {
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
    }
}
