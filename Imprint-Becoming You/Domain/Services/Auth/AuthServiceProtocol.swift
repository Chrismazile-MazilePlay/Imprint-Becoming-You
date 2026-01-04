//
//  AuthServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Auth Service Protocol

/// Protocol for authentication services.
///
/// Provides a unified interface for user authentication supporting
/// multiple sign-in methods including Apple, Google, and email/password.
///
/// ## Usage
/// ```swift
/// let auth: AuthServiceProtocol = AuthService()
///
/// // Sign in with Apple
/// let userId = try await auth.signInWithApple()
///
/// // Check authentication state
/// if auth.isAuthenticated {
///     print("User: \(auth.currentUserId ?? "unknown")")
/// }
///
/// // Listen for auth changes
/// for await userId in auth.authStateStream {
///     print("Auth state changed: \(userId ?? "signed out")")
/// }
/// ```
protocol AuthServiceProtocol: AnyObject, Sendable {
    
    /// Current authenticated user ID, or nil if not signed in
    var currentUserId: String? { get }
    
    /// Whether a user is currently authenticated
    var isAuthenticated: Bool { get }
    
    /// Signs in using Apple Sign In
    /// - Returns: The authenticated user ID
    /// - Throws: Authentication errors or `AppError.notImplemented`
    func signInWithApple() async throws -> String
    
    /// Signs in using Google Sign In
    /// - Returns: The authenticated user ID
    /// - Throws: Authentication errors or `AppError.notImplemented`
    func signInWithGoogle() async throws -> String
    
    /// Signs in with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    /// - Returns: The authenticated user ID
    /// - Throws: Authentication errors or `AppError.notImplemented`
    func signIn(email: String, password: String) async throws -> String
    
    /// Creates a new account with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's chosen password
    /// - Returns: The new user ID
    /// - Throws: Account creation errors or `AppError.notImplemented`
    func createAccount(email: String, password: String) async throws -> String
    
    /// Signs out the current user
    /// - Throws: Sign out errors
    func signOut() async throws
    
    /// Permanently deletes the current user's account
    /// - Throws: Account deletion errors
    func deleteAccount() async throws
    
    /// Sends a password reset email
    /// - Parameter email: The email address to send reset link to
    /// - Throws: Email sending errors
    func sendPasswordReset(to email: String) async throws
    
    /// Stream of authentication state changes
    /// Emits the current user ID when auth state changes, or nil on sign out
    var authStateStream: AsyncStream<String?> { get }
}
