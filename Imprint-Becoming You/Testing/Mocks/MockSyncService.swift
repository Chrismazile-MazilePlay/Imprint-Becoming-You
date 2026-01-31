//
//  MockSyncService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Sync Service

/// Mock implementation of sync service for previews and testing.
///
/// Simulates cloud synchronization without actual Firebase calls.
/// Uses `@MainActor` isolation consistent with the protocol.
@MainActor
final class MockSyncService: SyncServiceProtocol {
    
    // MARK: - State
    
    /// Whether sync is in progress - MainActor isolation provides thread safety
    private var _isSyncing: Bool = false
    
    /// Last successful sync date
    private var _lastSyncDate: Date?
    
    // MARK: - Configuration
    
    /// Simulated sync delay
    var syncDelay: Duration = .seconds(1)
    
    /// Whether to simulate sync errors
    var shouldSimulateError: Bool = false
    
    // MARK: - SyncServiceProtocol
    
    var isSyncing: Bool {
        _isSyncing
    }
    
    var lastSyncDate: Date? {
        _lastSyncDate
    }
    
    func syncToCloud(userId: String) async throws {
        if shouldSimulateError {
            throw AppError.syncFailed(reason: "Simulated sync error")
        }
        
        _isSyncing = true
        try await Task.sleep(for: syncDelay)
        _lastSyncDate = Date()
        _isSyncing = false
    }
    
    func syncFromCloud(userId: String) async throws {
        if shouldSimulateError {
            throw AppError.syncFailed(reason: "Simulated sync error")
        }
        
        _isSyncing = true
        try await Task.sleep(for: syncDelay)
        _lastSyncDate = Date()
        _isSyncing = false
    }
    
    func sync(_ dataType: SyncDataType, userId: String) async throws {
        if shouldSimulateError {
            throw AppError.syncFailed(reason: "Simulated sync error")
        }
        
        try await Task.sleep(for: .milliseconds(500))
    }
}
