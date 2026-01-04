//
//  AffirmationService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Affirmation Service

/// Production implementation of affirmation generation service.
///
/// Currently provides offline fallback affirmations.
/// Online AI generation will be added in Phase 3.
///
/// ## Features (Planned)
/// - Claude API integration for personalized generation
/// - Firebase proxy for secure API key management
/// - Offline bundle with curated affirmations
final class AffirmationService: AffirmationServiceProtocol, @unchecked Sendable {
    
    // MARK: - AffirmationServiceProtocol
    
    var isOnlineAvailable: Bool {
        get async { false }  // TODO: Phase 3 - Check network + API availability
    }
    
    func generateAffirmations(forGoals goals: [String], count: Int) async throws -> [String] {
        // TODO: Phase 3 - Claude API integration
        throw AppError.notImplemented(feature: "Affirmation Generation")
    }
    
    func generateAffirmations(fromPrompt prompt: String, count: Int) async throws -> [String] {
        // TODO: Phase 3 - Claude API integration
        throw AppError.notImplemented(feature: "Affirmation Generation")
    }
    
    func loadOfflineAffirmations(forCategories categories: [String]) -> [String] {
        // TODO: Load from bundled JSON file
        // For now, return empty - offline affirmations bundled in Phase 3
        []
    }
}
