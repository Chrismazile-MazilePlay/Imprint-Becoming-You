//
//  SyncServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Sync Service Protocol

/// Protocol for data synchronization with Firebase.
///
/// Manages bidirectional sync between local SwiftData storage
/// and Firebase Firestore cloud storage.
///
/// ## Usage
/// ```swift
/// let sync: SyncServiceProtocol = SyncService()
///
/// // Full sync
/// try await sync.syncToCloud(userId: "user123")
/// try await sync.syncFromCloud(userId: "user123")
///
/// // Sync specific data type
/// try await sync.sync(.customPrompts, userId: "user123")
/// ```
protocol SyncServiceProtocol: AnyObject, Sendable {
    
    /// Uploads local data to the cloud
    /// - Parameter userId: The authenticated user's ID
    /// - Throws: Sync errors or `AppError.notImplemented`
    func syncToCloud(userId: String) async throws
    
    /// Downloads cloud data to local storage
    /// - Parameter userId: The authenticated user's ID
    /// - Throws: Sync errors or `AppError.notImplemented`
    func syncFromCloud(userId: String) async throws
    
    /// Syncs a specific data type
    /// - Parameters:
    ///   - dataType: The type of data to sync
    ///   - userId: The authenticated user's ID
    /// - Throws: Sync errors or `AppError.notImplemented`
    func sync(_ dataType: SyncDataType, userId: String) async throws
    
    /// Whether a sync operation is currently in progress
    var isSyncing: Bool { get }
    
    /// Date of the last successful sync, or nil if never synced
    var lastSyncDate: Date? { get }
}

// MARK: - Sync Data Type

/// Types of data that can be synced with the cloud
enum SyncDataType: String, Sendable {
    /// User profile and preferences
    case userProfile
    
    /// Custom AI prompts created by the user
    case customPrompts
    
    /// Generated and favorited affirmations
    case affirmations
    
    /// Session progress and statistics
    case progress
    
    /// Voice clone configurations
    case voiceProfiles
}
