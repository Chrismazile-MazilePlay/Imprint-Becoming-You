//
//  AffirmationDeletionHelper.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/12/26.
//

import Foundation
import SwiftData

// MARK: - AffirmationDeletionHelper

/// Helper for validating and performing affirmation deletions.
///
/// Ensures that protected affirmations (seeded or referenced by saved sessions)
/// cannot be deleted.
///
/// ## Protection Rules
/// An affirmation is protected if:
/// - It is seeded content (`source == .seeded`)
/// - It belongs to any saved session (`!savedSessions.isEmpty`)
///
/// ## Usage
/// ```swift
/// // Check before deletion
/// let result = AffirmationDeletionHelper.canDelete(affirmation)
/// if result.canDelete {
///     modelContext.delete(affirmation)
/// } else {
///     print("Cannot delete: \(result.reason ?? "Protected")")
/// }
///
/// // Batch filter
/// let deletable = AffirmationDeletionHelper.filterDeletable(affirmations)
/// ```
enum AffirmationDeletionHelper {
    
    // MARK: - Deletion Result
    
    /// Result of a deletion validation check
    struct DeletionResult {
        /// Whether the affirmation can be deleted
        let canDelete: Bool
        
        /// Reason for protection (if not deletable)
        let reason: String?
        
        /// Creates a result indicating deletion is allowed
        static var allowed: DeletionResult {
            DeletionResult(canDelete: true, reason: nil)
        }
        
        /// Creates a result indicating deletion is blocked
        static func blocked(reason: String) -> DeletionResult {
            DeletionResult(canDelete: false, reason: reason)
        }
    }
    
    // MARK: - Single Affirmation Validation
    
    /// Checks if an affirmation can be safely deleted.
    ///
    /// - Parameter affirmation: The affirmation to check
    /// - Returns: A result indicating whether deletion is allowed
    static func canDelete(_ affirmation: Affirmation) -> DeletionResult {
        // Check if seeded (bundled content)
        if affirmation.isSeeded {
            return .blocked(reason: "Seeded affirmations cannot be deleted.")
        }
        
        // Check if referenced by saved sessions
        if !affirmation.savedSessions.isEmpty {
            let sessionCount = affirmation.savedSessions.count
            let sessionText = sessionCount == 1 ? "session" : "sessions"
            return .blocked(
                reason: "This affirmation is used in \(sessionCount) saved \(sessionText) and cannot be deleted."
            )
        }
        
        // Check the combined isProtected property (catches any edge cases)
        if affirmation.isProtected {
            return .blocked(reason: "This affirmation is protected and cannot be deleted.")
        }
        
        return .allowed
    }
    
    // MARK: - Batch Validation
    
    /// Filters a collection of affirmations to only those that can be deleted.
    ///
    /// - Parameter affirmations: The affirmations to filter
    /// - Returns: Array of affirmations that can be safely deleted
    static func filterDeletable(_ affirmations: [Affirmation]) -> [Affirmation] {
        affirmations.filter { canDelete($0).canDelete }
    }
    
    /// Filters a collection of affirmations to only those that are protected.
    ///
    /// - Parameter affirmations: The affirmations to filter
    /// - Returns: Array of protected affirmations
    static func filterProtected(_ affirmations: [Affirmation]) -> [Affirmation] {
        affirmations.filter { !canDelete($0).canDelete }
    }
    
    /// Checks if any affirmations in a collection are protected.
    ///
    /// - Parameter affirmations: The affirmations to check
    /// - Returns: True if any affirmation is protected
    static func anyProtected(in affirmations: [Affirmation]) -> Bool {
        affirmations.contains { !canDelete($0).canDelete }
    }
    
    // MARK: - Safe Deletion
    
    /// Safely deletes an affirmation if allowed.
    ///
    /// - Parameters:
    ///   - affirmation: The affirmation to delete
    ///   - context: The model context for deletion
    /// - Returns: Result indicating success or failure reason
    @MainActor
    static func safeDelete(
        _ affirmation: Affirmation,
        from context: ModelContext
    ) -> DeletionResult {
        let result = canDelete(affirmation)
        
        guard result.canDelete else {
            return result
        }
        
        context.delete(affirmation)
        
        #if DEBUG
        print("[OK] AffirmationDeletionHelper: Deleted affirmation \(affirmation.id)")
        #endif
        
        return .allowed
    }
    
    /// Safely deletes multiple affirmations, skipping protected ones.
    ///
    /// - Parameters:
    ///   - affirmations: The affirmations to delete
    ///   - context: The model context for deletion
    /// - Returns: Tuple of (deleted count, skipped count, skipped reasons)
    @MainActor
    static func safeDeleteBatch(
        _ affirmations: [Affirmation],
        from context: ModelContext
    ) -> (deleted: Int, skipped: Int, reasons: [String]) {
        var deleted = 0
        var skipped = 0
        var reasons: [String] = []
        
        for affirmation in affirmations {
            let result = canDelete(affirmation)
            
            if result.canDelete {
                context.delete(affirmation)
                deleted += 1
            } else {
                skipped += 1
                if let reason = result.reason, !reasons.contains(reason) {
                    reasons.append(reason)
                }
            }
        }
        
        #if DEBUG
        print("[OK] AffirmationDeletionHelper: Batch delete - \(deleted) deleted, \(skipped) skipped")
        #endif
        
        return (deleted, skipped, reasons)
    }
    
    // MARK: - Expiration Cleanup
    
    /// Deletes expired affirmations that are not protected.
    ///
    /// This is the safe way to clean up old content while respecting
    /// saved session references.
    ///
    /// - Parameter context: The model context for deletion
    /// - Returns: Number of affirmations deleted
    @MainActor
    static func deleteExpiredUnprotected(from context: ModelContext) throws -> Int {
        let now = Date()
        
        // Fetch all expired affirmations
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate<Affirmation> { affirmation in
                affirmation.expiresAt < now
            }
        )
        
        let allExpired = try context.fetch(descriptor)
        
        // Filter in memory to non-seeded and not protected
        let deletable = allExpired.filter { affirmation in
            !affirmation.isSeeded && canDelete(affirmation).canDelete
        }
        
        for affirmation in deletable {
            context.delete(affirmation)
        }
        
        #if DEBUG
        print("[OK] AffirmationDeletionHelper: Cleaned up \(deletable.count) expired affirmations (\(allExpired.count - deletable.count) protected/seeded)")
        #endif
        
        return deletable.count
    }
}

// MARK: - Affirmation Extension

extension Affirmation {
    
    /// Checks if this affirmation can be deleted.
    ///
    /// Convenience wrapper around `AffirmationDeletionHelper.canDelete(_:)`.
    var deletionResult: AffirmationDeletionHelper.DeletionResult {
        AffirmationDeletionHelper.canDelete(self)
    }
    
    /// Human-readable reason why this affirmation is protected.
    ///
    /// Returns nil if the affirmation can be deleted.
    var protectionReason: String? {
        AffirmationDeletionHelper.canDelete(self).reason
    }
}
