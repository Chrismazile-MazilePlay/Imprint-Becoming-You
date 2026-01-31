//
//  ModelContainerFactory.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/30/26.
//

import Foundation
import SwiftData
import os.log

// MARK: - Logger

private let containerLog = Logger(subsystem: "com.imprint.data", category: "ModelContainerFactory")

// MARK: - Model Container Result

/// Result of model container creation attempt.
///
/// This enum captures the three possible outcomes of SwiftData initialization:
/// - Success: Normal operation with persistent storage
/// - Fallback: Running with in-memory storage (data won't persist)
/// - Failure: Complete failure requiring recovery UI
enum ModelContainerResult: Sendable {
    
    /// Successfully created persistent container
    case success(ModelContainer)
    
    /// Created in-memory fallback (data won't persist between sessions)
    case fallback(ModelContainer, originalError: String)
    
    /// Complete failure - must show recovery UI
    case failure(String)
    
    /// Returns the container if available (success or fallback)
    var container: ModelContainer? {
        switch self {
        case .success(let container), .fallback(let container, _):
            return container
        case .failure:
            return nil
        }
    }
    
    /// Whether the app is running in fallback mode (in-memory only)
    var isUsingFallback: Bool {
        if case .fallback = self { return true }
        return false
    }
    
    /// Whether initialization completely failed
    var isFailed: Bool {
        if case .failure = self { return true }
        return false
    }
    
    /// The error message if not successful
    var errorMessage: String? {
        switch self {
        case .success:
            return nil
        case .fallback(_, let error):
            return error
        case .failure(let error):
            return error
        }
    }
}

// MARK: - Model Container Factory

/// Factory for creating SwiftData model containers with recovery handling.
///
/// ## Recovery Strategy
/// 1. Attempt normal persistent storage initialization
/// 2. On failure, attempt in-memory fallback (allows app to function)
/// 3. On complete failure, return failure for UI recovery handling
///
/// ## Usage
/// ```swift
/// let result = await ModelContainerFactory.createContainer()
/// switch result {
/// case .success(let container):
///     // Normal operation
/// case .fallback(let container, let error):
///     // Warn user data won't persist
/// case .failure(let error):
///     // Show recovery UI
/// }
/// ```
///
/// ## Thread Safety
/// All methods are `@MainActor` isolated since SwiftData ModelContainer
/// initialization must occur on the main thread.
@MainActor
enum ModelContainerFactory {
    
    // MARK: - Schema Definition
    
    /// All model types in the schema.
    ///
    /// CRITICAL: This list must include ALL `@Model` types used in the app.
    /// Missing types will cause runtime crashes when SwiftData encounters them.
    static var schema: Schema {
        Schema([
            UserProfile.self,
            Affirmation.self,
            CustomPrompt.self,
            ProgressData.self,
            SavedSession.self,
            VoiceRecord.self,
            VoiceUsageRecord.self
        ])
    }
    
    // MARK: - Factory Method
    
    /// Creates a model container with fallback handling.
    ///
    /// This method implements a two-tier recovery strategy:
    /// 1. First attempts normal persistent storage
    /// 2. If that fails, falls back to in-memory storage
    /// 3. If both fail, returns a failure result
    ///
    /// - Returns: Result indicating success, fallback, or failure
    static func createContainer() -> ModelContainerResult {
        containerLog.info("Creating SwiftData container...")
        
        // Attempt 1: Normal persistent storage
        do {
            let container = try createPersistentContainer()
            containerLog.info("SwiftData initialized successfully (persistent)")
            return .success(container)
            
        } catch {
            let persistentErrorMessage = error.localizedDescription
            containerLog.error("Persistent storage failed: \(persistentErrorMessage)")
            
            // Attempt 2: In-memory fallback
            do {
                let fallbackContainer = try createInMemoryContainer()
                containerLog.warning("SwiftData fell back to in-memory storage")
                return .fallback(fallbackContainer, originalError: persistentErrorMessage)
                
            } catch {
                let fallbackErrorMessage = error.localizedDescription
                containerLog.error("In-memory fallback also failed: \(fallbackErrorMessage)")
                return .failure(persistentErrorMessage)
            }
        }
    }
    
    // MARK: - Container Creation
    
    /// Creates a persistent model container.
    ///
    /// - Throws: SwiftData initialization errors
    /// - Returns: Configured ModelContainer with persistent storage
    private static func createPersistentContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
    
    /// Creates an in-memory model container.
    ///
    /// Used as a fallback when persistent storage fails.
    /// Data will not persist between app launches.
    ///
    /// - Throws: SwiftData initialization errors
    /// - Returns: Configured ModelContainer with in-memory storage
    private static func createInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
    
    // MARK: - Recovery Actions
    
    /// Attempts to reset the database by deleting existing files.
    ///
    /// Use when user chooses to reset their data after corruption is detected.
    /// This deletes all SwiftData files and attempts fresh initialization.
    ///
    /// - Returns: New initialization result after reset attempt
    static func resetDatabase() -> ModelContainerResult {
        containerLog.warning("User initiated database reset")
        
        // Get the default store URL
        let storeURL = URL.applicationSupportDirectory
            .appending(path: "default.store")
        
        // Attempt to delete existing database files
        do {
            try deleteStoreFiles(at: storeURL)
        } catch {
            containerLog.error("Failed to delete store files: \(error.localizedDescription)")
            // Continue anyway - initialization might still work
        }
        
        // Re-attempt initialization
        let result = createContainer()
        
        if case .success = result {
            containerLog.info("Database reset successful")
        }
        
        return result
    }
    
    /// Deletes all files associated with a SwiftData store.
    ///
    /// - Parameter storeURL: Base URL of the store (without extensions)
    /// - Throws: FileManager errors if deletion fails
    private static func deleteStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        
        // SwiftData creates multiple files for a store
        let storeFiles = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal")
        ]
        
        for file in storeFiles {
            if fileManager.fileExists(atPath: file.path) {
                try fileManager.removeItem(at: file)
                containerLog.info("Deleted: \(file.lastPathComponent)")
            }
        }
    }
    
    // MARK: - Diagnostics
    
    /// Returns diagnostic information about the store location.
    ///
    /// Useful for debugging and support purposes.
    static var storeDiagnostics: String {
        let storeURL = URL.applicationSupportDirectory
            .appending(path: "default.store")
        
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: storeURL.path)
        
        var diagnostics = "Store URL: \(storeURL.path)\n"
        diagnostics += "Exists: \(exists)\n"
        
        if exists {
            if let attributes = try? fileManager.attributesOfItem(atPath: storeURL.path) {
                if let size = attributes[.size] as? Int64 {
                    diagnostics += "Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))\n"
                }
                if let modDate = attributes[.modificationDate] as? Date {
                    diagnostics += "Modified: \(modDate)\n"
                }
            }
        }
        
        return diagnostics
    }
}
