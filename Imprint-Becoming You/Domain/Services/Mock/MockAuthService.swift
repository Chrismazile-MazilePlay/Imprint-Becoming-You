//
//  MockAuthService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Auth Service

/// Mock implementation of authentication service for previews and testing.
///
/// Simulates authentication flows without actual Firebase calls.
final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    
    // MARK: - Thread Safety
    
    private let stateQueue = DispatchQueue(label: "com.imprint.mockauth")
    private var _currentUserId: String?
    
    // MARK: - Configuration
    
    /// Whether to start in authenticated state
    var startAuthenticated: Bool = false {
        didSet {
            if startAuthenticated {
                stateQueue.sync { _currentUserId = "mock-user-\(UUID().uuidString.prefix(8))" }
            } else {
                stateQueue.sync { _currentUserId = nil }
            }
        }
    }
    
    /// Simulated sign-in delay
    var signInDelay: Duration = .milliseconds(500)
    
    // MARK: - AuthServiceProtocol
    
    var currentUserId: String? {
        stateQueue.sync { _currentUserId }
    }
    
    var isAuthenticated: Bool {
        currentUserId != nil
    }
    
    lazy var authStateStream: AsyncStream<String?> = {
        AsyncStream { _ in
            // Mock doesn't emit auth state changes
        }
    }()
    
    func signInWithApple() async throws -> String {
        try await Task.sleep(for: signInDelay)
        let id = "apple-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func signInWithGoogle() async throws -> String {
        try await Task.sleep(for: signInDelay)
        let id = "google-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func signIn(email: String, password: String) async throws -> String {
        try await Task.sleep(for: signInDelay)
        let id = "email-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func createAccount(email: String, password: String) async throws -> String {
        try await Task.sleep(for: signInDelay)
        let id = "email-\(UUID().uuidString)"
        stateQueue.sync { _currentUserId = id }
        return id
    }
    
    func signOut() async throws {
        stateQueue.sync { _currentUserId = nil }
    }
    
    func deleteAccount() async throws {
        stateQueue.sync { _currentUserId = nil }
    }
    
    func sendPasswordReset(to email: String) async throws {
        // No-op for mock
    }
}
