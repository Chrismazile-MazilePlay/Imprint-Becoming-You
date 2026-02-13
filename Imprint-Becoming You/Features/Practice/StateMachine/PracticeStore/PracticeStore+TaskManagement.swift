//
//  PracticeStore+TaskManagement.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/30/26.
//

import Foundation

// MARK: - Task Management

/// Centralized task lifecycle management for PracticeStore.
///
/// ## Design Philosophy
///
/// This extension provides centralized management for all active tasks in PracticeStore.
/// The approach follows the TaskManagement ADR recommendation:
///
/// - **Tracked Tasks**: Long-running, cancellable operations (`activeFlowTask`, `listeningTask`, `sessionPreparationTask`)
/// - **Fire-and-Forget**: Short-lived operations (< 3s) that self-terminate or use `flowGeneration` checks
///
/// ## Task Lifecycle
///
/// All tracked tasks are registered in the `allManagedTasks` computed property.
/// This ensures:
/// 1. Single point for bulk cancellation
/// 2. Debug visibility into active tasks
/// 3. Clean cleanup on state transitions
///
/// ## Usage
///
/// ```swift
/// // Cancel specific task
/// cancelFlowTask()
///
/// // Cancel all tracked tasks
/// cancelAllManagedTasks()
///
/// // Replace task (cancel old, start new)
/// replaceFlowTask {
///     await self.executeCurrentFlow(generation: generation)
/// }
/// ```
extension PracticeStore {
    
    // MARK: - Task Registry
    
    /// All managed tasks that need lifecycle tracking.
    ///
    /// Add new task properties here to ensure they're included in bulk cancellation.
    /// Only include tasks that:
    /// - May run for extended periods (> 3 seconds)
    /// - Need explicit cancellation on state transitions
    /// - Should be cancelled when leaving the view
    private var allManagedTasks: [Task<Void, Never>?] {
        [
            activeFlowTask,
            listeningTask,
            sessionPreparationTask
        ]
    }
    
    // MARK: - Bulk Operations
    
    /// Cancels all managed tasks.
    ///
    /// Call this on:
    /// - View disappearance
    /// - Session exit
    /// - Mode changes
    /// - Error recovery
    func cancelAllManagedTasks() {
        for task in allManagedTasks {
            task?.cancel()
        }
        
        // Clear task references
        activeFlowTask = nil
        listeningTask = nil
        sessionPreparationTask = nil
        
        AppLogger.debug("Cancelled all managed tasks", category: .practice)
    }
    
    // MARK: - Flow Task Management
    
    /// Cancels the active flow task if running.
    func cancelFlowTask() {
        activeFlowTask?.cancel()
        activeFlowTask = nil
    }
    
    /// Replaces the active flow task with a new one.
    ///
    /// This is the safe way to start a new flow - it guarantees the old task
    /// is cancelled before starting the new one.
    ///
    /// - Parameter operation: The async operation to run as the new flow task
    func replaceFlowTask(_ operation: @escaping @Sendable () async -> Void) {
        // Cancel existing
        activeFlowTask?.cancel()
        
        // Increment generation to invalidate any stale closures
        flowGeneration += 1
        
        // Start new task
        activeFlowTask = Task { [weak self] in
            guard self != nil else { return }
            await operation()
        }
    }
    
    // MARK: - Listening Task Management
    
    /// Cancels the active listening task if running.
    func cancelListeningTask() {
        listeningTask?.cancel()
        listeningTask = nil
        listeningStartTime = nil
    }
    
    /// Replaces the listening task with a new one.
    ///
    /// - Parameter operation: The async operation to run as the new listening task
    func replaceListeningTask(_ operation: @escaping @Sendable () async -> Void) {
        // Cancel existing
        listeningTask?.cancel()
        listeningStartTime = Date()
        
        // Start new task
        listeningTask = Task { [weak self] in
            guard self != nil else { return }
            await operation()
        }
    }
    
    // MARK: - Session Preparation Task Management
    
    /// Cancels the session preparation task if running.
    func cancelSessionPreparationTask() {
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
    }
    
    /// Replaces the session preparation task with a new one.
    ///
    /// - Parameter operation: The async operation to run as the new preparation task
    func replaceSessionPreparationTask(_ operation: @escaping @Sendable () async -> Void) {
        // Cancel existing
        sessionPreparationTask?.cancel()
        
        // Start new task
        sessionPreparationTask = Task { [weak self] in
            guard self != nil else { return }
            await operation()
        }
    }
    
    // MARK: - Debug Support
    
    /// Logs the current state of all managed tasks (DEBUG only).
    func debugLogTaskState() {
        #if DEBUG
        let activeCount = allManagedTasks.compactMap { $0 }.count
        let taskStates = [
            "flowTask: \(activeFlowTask != nil ? "active" : "nil")",
            "listeningTask: \(listeningTask != nil ? "active" : "nil")",
            "prepTask: \(sessionPreparationTask != nil ? "active" : "nil")"
        ]
        AppLogger.debug("PracticeStore Tasks (\(activeCount) active): \(taskStates.joined(separator: ", "))", category: .practice)
        #endif
    }
}

// MARK: - Task Cancellation Checks

extension PracticeStore {
    
    /// Checks if the current flow task should continue executing.
    ///
    /// Use this at the start of async operations and before state mutations
    /// to ensure stale tasks don't affect state.
    ///
    /// - Parameter generation: The generation captured when the task started
    /// - Returns: `true` if the task should continue, `false` if it should exit
    func shouldContinueFlow(generation: Int) -> Bool {
        guard !Task.isCancelled else {
            AppLogger.debug("Flow cancelled (Task.isCancelled)", category: .practice)
            return false
        }
        guard generation == flowGeneration else {
            AppLogger.debug("Flow stale (generation \(generation) != \(flowGeneration))", category: .practice)
            return false
        }
        return true
    }
}
