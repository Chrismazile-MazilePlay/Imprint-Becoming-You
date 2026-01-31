//
//  AffirmationServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Affirmation Service Protocol

/// Protocol for affirmation generation and management.
///
/// Supports both online AI-powered generation and offline fallback
/// affirmations bundled with the app.
///
/// ## MainActor Isolation
/// This protocol is `@MainActor` isolated because:
/// 1. Generated affirmations are stored in SwiftData
/// 2. Results drive UI state updates
/// 3. Consistent with other service protocols
///
/// ## Usage
/// ```swift
/// let service: AffirmationServiceProtocol = AffirmationService()
///
/// // Generate from goals
/// let affirmations = try await service.generateAffirmations(
///     forGoals: ["confidence", "focus"],
///     count: 30
/// )
///
/// // Load offline fallback
/// let offline = service.loadOfflineAffirmations(forCategories: ["confidence"])
/// ```
@MainActor
protocol AffirmationServiceProtocol: AnyObject {
    
    /// Generates affirmations based on user's selected goals
    /// - Parameters:
    ///   - goals: Array of goal category identifiers
    ///   - count: Number of affirmations to generate
    /// - Returns: Array of affirmation text strings
    /// - Throws: `AppError.notImplemented` if online generation unavailable
    func generateAffirmations(forGoals goals: [String], count: Int) async throws -> [String]
    
    /// Generates affirmations from a custom prompt
    /// - Parameters:
    ///   - prompt: User's custom prompt text
    ///   - count: Number of affirmations to generate
    /// - Returns: Array of affirmation text strings
    /// - Throws: `AppError.notImplemented` if online generation unavailable
    func generateAffirmations(fromPrompt prompt: String, count: Int) async throws -> [String]
    
    /// Loads offline affirmations for the given categories
    /// - Parameter categories: Array of category identifiers
    /// - Returns: Array of affirmation text strings from bundled content
    func loadOfflineAffirmations(forCategories categories: [String]) -> [String]
    
    /// Whether online generation is available
    var isOnlineAvailable: Bool { get async }
}
