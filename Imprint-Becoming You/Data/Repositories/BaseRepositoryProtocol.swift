//
//  BaseRepositoryProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/31/26.
//

import Foundation
import SwiftData

// MARK: - Identifiable Model Protocol

/// Protocol for SwiftData models that have a UUID identifier.
///
/// This protocol enables generic repository operations by guaranteeing
/// that conforming models have a consistent `id` property.
///
/// ## Conformance
/// SwiftData `@Model` classes with a `var id: UUID` property can conform:
/// ```swift
/// extension Affirmation: IdentifiableModel {}
/// extension SavedSession: IdentifiableModel {}
/// ```
///
/// ## Usage
/// Used as a constraint for `BaseRepositoryProtocol` to enable
/// generic CRUD operations across different model types.
protocol IdentifiableModel: PersistentModel {
    /// Unique identifier for the model instance
    var id: UUID { get }
}

// MARK: - Model Conformances

/// Affirmation conforms to IdentifiableModel for generic repository operations.
extension Affirmation: IdentifiableModel {}

/// SavedSession conforms to IdentifiableModel for generic repository operations.
extension SavedSession: IdentifiableModel {}

/// UserProfile conforms to IdentifiableModel for generic repository operations.
extension UserProfile: IdentifiableModel {}

/// CustomPrompt conforms to IdentifiableModel for generic repository operations.
extension CustomPrompt: IdentifiableModel {}

// MARK: - Base Repository Protocol

/// Base protocol for SwiftData repositories with common CRUD operations.
///
/// Provides a consistent interface for data access across different model types,
/// reducing code duplication and ensuring uniform error handling patterns.
///
/// ## Thread Safety
/// This protocol is `@MainActor` isolated because SwiftData's `ModelContext`
/// must be accessed from the main thread. All operations are synchronous.
///
/// ## Generic Type
/// The `Model` associated type must conform to `IdentifiableModel`,
/// ensuring the model has a UUID identifier for lookup operations.
///
/// ## Default Implementations
/// The protocol extension provides default implementations for:
/// - `fetchAll()` - Fetches all model instances
/// - `count()` - Counts total model instances
/// - `insert(_:)` - Inserts a new model instance
/// - `delete(_:)` - Deletes a model instance
/// - `save()` - Saves pending changes to the context
///
/// ## Predicate-Based Methods
/// Methods requiring predicates (like `fetchById`) cannot have default
/// implementations due to Swift macro limitations with generic types.
/// Conforming repositories must implement these directly.
///
/// ## Usage
/// ```swift
/// @MainActor
/// final class AffirmationRepository: BaseRepositoryProtocol, AffirmationRepositoryProtocol {
///     typealias Model = Affirmation
///     let modelContext: ModelContext
///
///     // Inherits fetchAll(), count(), insert(), delete(), save()
///     // Must implement fetchById() and domain-specific methods
/// }
/// ```
@MainActor
protocol BaseRepositoryProtocol<Model> {
    
    /// The SwiftData model type this repository manages.
    associatedtype Model: IdentifiableModel
    
    /// The SwiftData model context for database operations.
    ///
    /// Must be accessible (not private) for protocol extension defaults.
    var modelContext: ModelContext { get }
    
    // MARK: - Read Operations
    
    /// Fetches a model instance by its unique identifier.
    ///
    /// - Parameter id: The UUID of the model to fetch
    /// - Returns: The model if found, `nil` otherwise
    /// - Throws: `AppError.loadFailed` if the fetch operation fails
    ///
    /// - Note: This method cannot have a default implementation due to
    ///   Swift macro limitations with generic predicate types.
    func fetchById(_ id: UUID) throws -> Model?
    
    /// Fetches all model instances.
    ///
    /// - Returns: Array of all model instances
    /// - Throws: `AppError.loadFailed` if the fetch operation fails
    func fetchAll() throws -> [Model]
    
    /// Counts total model instances in the database.
    ///
    /// - Returns: Total count of model instances
    /// - Throws: `AppError.loadFailed` if the count operation fails
    func count() throws -> Int
    
    // MARK: - Write Operations
    
    /// Inserts a new model instance into the database.
    ///
    /// - Parameter model: The model instance to insert
    /// - Throws: `AppError.saveFailed` if the insert operation fails
    func insert(_ model: Model) throws
    
    /// Deletes a model instance from the database.
    ///
    /// - Parameter model: The model instance to delete
    /// - Throws: `AppError.saveFailed` if the delete operation fails
    func delete(_ model: Model) throws
    
    /// Saves any pending changes to the model context.
    ///
    /// - Throws: `AppError.saveFailed` if the save operation fails
    func save() throws
}

// MARK: - Default Implementations

extension BaseRepositoryProtocol {
    
    /// Default implementation: Fetches all model instances.
    ///
    /// - Returns: Array of all model instances, empty if none exist
    /// - Throws: `AppError.loadFailed` if the fetch operation fails
    func fetchAll() throws -> [Model] {
        do {
            let descriptor = FetchDescriptor<Model>()
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.loadFailed(reason: "Failed to fetch all \(Model.self): \(error.localizedDescription)")
        }
    }
    
    /// Default implementation: Counts total model instances.
    ///
    /// - Returns: Total count of model instances
    /// - Throws: `AppError.loadFailed` if the count operation fails
    func count() throws -> Int {
        do {
            let descriptor = FetchDescriptor<Model>()
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw AppError.loadFailed(reason: "Failed to count \(Model.self): \(error.localizedDescription)")
        }
    }
    
    /// Default implementation: Inserts a new model instance.
    ///
    /// - Parameter model: The model instance to insert
    /// - Throws: `AppError.saveFailed` if the operation fails
    func insert(_ model: Model) throws {
        do {
            modelContext.insert(model)
            try modelContext.save()
        } catch {
            throw AppError.saveFailed(reason: "Failed to insert \(Model.self): \(error.localizedDescription)")
        }
    }
    
    /// Default implementation: Deletes a model instance.
    ///
    /// - Parameter model: The model instance to delete
    /// - Throws: `AppError.saveFailed` if the operation fails
    func delete(_ model: Model) throws {
        do {
            modelContext.delete(model)
            try modelContext.save()
        } catch {
            throw AppError.saveFailed(reason: "Failed to delete \(Model.self): \(error.localizedDescription)")
        }
    }
    
    /// Default implementation: Saves pending changes.
    ///
    /// - Throws: `AppError.saveFailed` if the save operation fails
    func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw AppError.saveFailed(reason: "Failed to save \(Model.self) context: \(error.localizedDescription)")
        }
    }
}
