//
//  MockAffirmationService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Affirmation Service

/// Mock implementation of affirmation service for previews and testing.
///
/// Generates placeholder affirmations without API calls.
final class MockAffirmationService: AffirmationServiceProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Simulated generation delay
    var generationDelay: Duration = .seconds(1)
    
    /// Whether to simulate offline mode
    var simulateOffline: Bool = false
    
    // MARK: - AffirmationServiceProtocol
    
    var isOnlineAvailable: Bool {
        get async { !simulateOffline }
    }
    
    func generateAffirmations(forGoals goals: [String], count: Int) async throws -> [String] {
        try await Task.sleep(for: generationDelay)
        
        return (0..<count).map { index in
            "I am affirmation \(index + 1) for goals: \(goals.joined(separator: ", "))"
        }
    }
    
    func generateAffirmations(fromPrompt prompt: String, count: Int) async throws -> [String] {
        try await Task.sleep(for: generationDelay)
        
        return (0..<count).map { index in
            "Custom affirmation \(index + 1) for: \(prompt)"
        }
    }
    
    func loadOfflineAffirmations(forCategories categories: [String]) -> [String] {
        // Return sample affirmations from Affirmation model
        Affirmation.samples.map(\.text)
    }
}
