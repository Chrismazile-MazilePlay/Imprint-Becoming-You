//
//  MemoryManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import Foundation
import UIKit

// MARK: - Memory Manager

/// Centralized memory management coordinator for the Imprint app.
///
/// Handles memory pressure events, background transitions, and coordinates
/// memory release across services to prevent iOS from terminating the app.
///
/// ## Memory Thresholds
/// - Normal: App uses typical memory (~200-400MB)
/// - Warning: iOS signals low memory, release caches
/// - Critical: App backgrounded >5min or memory warning, release ML models
///
/// ## Coordinated Cleanup
/// When the app enters background or receives memory warnings, MemoryManager:
/// 1. Releases Kokoro TTS ML pipelines (~500MB-1GB)
/// 2. Clears voice preview memory cache (~5MB)
/// 3. Clears pre-synthesis queues
/// 4. Releases audio engines not in use
///
/// ## Periodic Background Monitoring
/// Instead of using a single long `Task.sleep` (which can drift and doesn't
/// respond to state changes), the MemoryManager uses periodic checks at
/// `Constants.Background.backgroundCheckInterval` (60 seconds).
/// Benefits:
/// - Better timing precision
/// - Responsive cancellation when app returns to foreground
/// - Lower memory overhead from shorter-lived tasks
///
/// ## Usage
/// ```swift
/// // At app launch, setup memory monitoring
/// MemoryManager.shared.startMonitoring()
///
/// // When entering background
/// await MemoryManager.shared.releaseForBackground()
///
/// // When returning to foreground
/// await MemoryManager.shared.restoreFromBackground()
/// ```
@MainActor
final class MemoryManager {
    
    // MARK: - Singleton
    
    static let shared = MemoryManager()
    
    // MARK: - State
    
    /// Whether memory monitoring is active
    private(set) var isMonitoring: Bool = false
    
    /// When the app entered background (nil if foreground)
    private var backgroundedAt: Date?
    
    /// Whether we've released heavy resources
    private(set) var hasReleasedForBackground: Bool = false
    
    /// Memory warning observer
    private var memoryWarningObserver: NSObjectProtocol?
    
    /// Background/foreground observers
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    
    /// Task for periodic background checks.
    ///
    /// This task runs periodic checks while the app is in background,
    /// using `Constants.Background.backgroundCheckInterval` between checks.
    /// Cancelled when app returns to foreground.
    private var backgroundCheckTask: Task<Void, Never>?
    
    // MARK: - Dependencies (weak to avoid retain cycles)
    
    /// Dependencies container (set during setup)
    private weak var dependencies: DependencyContainer?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Setup
    
    /// Starts memory monitoring and registers for system notifications.
    ///
    /// Call this once at app launch from the App entry point.
    ///
    /// - Parameter dependencies: The dependency container for service access
    func startMonitoring(dependencies: DependencyContainer) {
        guard !isMonitoring else { return }
        
        self.dependencies = dependencies
        
        // Memory warning observer
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleMemoryWarning()
            }
        }
        
        // Background observer
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }
        
        // Foreground observer
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleWillEnterForeground()
            }
        }
        
        isMonitoring = true
        AppLogger.info("MemoryManager: Started monitoring", category: .memory)
    }
    
    /// Stops memory monitoring.
    func stopMonitoring() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        
        // Cancel background check task
        stopBackgroundMonitoring()
        
        isMonitoring = false
        AppLogger.info("MemoryManager: Stopped monitoring", category: .memory)
    }
    
    // MARK: - Memory Events
    
    /// Handles iOS memory warning notification.
    private func handleMemoryWarning() async {
        AppLogger.warning("MEMORY WARNING received from iOS", category: .memory)
        
        // Release everything possible
        await releaseForBackground()
        
        // Log current memory state
        logMemoryUsage()
    }
    
    /// Handles app entering background.
    ///
    /// Starts periodic background monitoring instead of a single long sleep.
    /// This provides better timing precision and responsive cancellation.
    private func handleDidEnterBackground() {
        backgroundedAt = Date()
        AppLogger.info("App entered background", category: .memory)
        
        // Start periodic background checking
        startBackgroundMonitoring()
    }
    
    /// Handles app returning to foreground.
    private func handleWillEnterForeground() async {
        // Cancel background monitoring immediately
        stopBackgroundMonitoring()
        
        let timeInBackground: TimeInterval
        if let backgroundTime = backgroundedAt {
            timeInBackground = Date().timeIntervalSince(backgroundTime)
        } else {
            timeInBackground = 0
        }
        
        backgroundedAt = nil
        AppLogger.info("App entering foreground (was background for \(Int(timeInBackground))s)", category: .memory)
        
        // Restore if we released resources
        if hasReleasedForBackground {
            await restoreFromBackground()
        }
    }
    
    // MARK: - Background Monitoring
    
    /// Starts periodic checks while app is in background.
    ///
    /// Uses `Constants.Background.backgroundCheckInterval` between checks,
    /// rather than sleeping for the entire `memoryReleaseThreshold`.
    /// This provides:
    /// - Timing precision (avoids drift from long sleeps)
    /// - Responsive cancellation when returning to foreground
    /// - Lower memory overhead from shorter-lived tasks
    private func startBackgroundMonitoring() {
        // Cancel any existing task
        backgroundCheckTask?.cancel()
        
        backgroundCheckTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            let checkInterval = Constants.Background.backgroundCheckInterval
            let releaseThreshold = Constants.Background.memoryReleaseThreshold
            
            AppLogger.debug(
                "Background monitoring started (check every \(Int(checkInterval))s, release at \(Int(releaseThreshold))s)",
                category: .memory
            )
            
            while !Task.isCancelled {
                // Wait for check interval using Duration-based sleep
                try? await Task.sleep(for: .seconds(checkInterval))
                
                // Check if cancelled during sleep
                guard !Task.isCancelled else {
                    AppLogger.debug("Background monitoring cancelled during sleep", category: .memory)
                    return
                }
                
                // Check if we're still in background and threshold reached
                guard let backgroundTime = self.backgroundedAt else {
                    // No longer in background (shouldn't happen, but handle gracefully)
                    AppLogger.debug("Background monitoring: no longer in background", category: .memory)
                    return
                }
                
                let elapsed = Date().timeIntervalSince(backgroundTime)
                AppLogger.debug(
                    "Background check: \(Int(elapsed))s elapsed (threshold: \(Int(releaseThreshold))s)",
                    category: .memory
                )
                
                if elapsed >= releaseThreshold {
                    AppLogger.info(
                        "Background threshold reached (\(Int(elapsed))s), releasing resources",
                        category: .memory
                    )
                    await self.releaseForBackground()
                    
                    // Stop monitoring after release (no need to keep checking)
                    return
                }
            }
            
            AppLogger.debug("Background monitoring loop exited", category: .memory)
        }
    }
    
    /// Stops background monitoring.
    ///
    /// Called when app returns to foreground or monitoring is stopped entirely.
    private func stopBackgroundMonitoring() {
        backgroundCheckTask?.cancel()
        backgroundCheckTask = nil
        AppLogger.debug("Background monitoring stopped", category: .memory)
    }
    
    // MARK: - Public API
    
    /// Releases heavy resources for background state.
    ///
    /// Called when:
    /// - App enters background for extended period
    /// - iOS sends memory warning
    /// - MainPracticeView detects long background duration
    ///
    /// This releases:
    /// - Kokoro TTS ML pipelines (~500MB-1GB)
    /// - Voice preview memory cache
    /// - Pre-synthesis queue
    func releaseForBackground() async {
        guard !hasReleasedForBackground else {
            AppLogger.debug("Already released for background", category: .memory)
            return
        }
        
        AppLogger.info("Releasing resources for background...", category: .memory)
        let startMemory = currentMemoryUsageMB()
        
        // 1. Release Kokoro TTS pipelines (biggest savings)
        if let ttsService = dependencies?.ttsService as? TTSService {
            await ttsService.releaseForBackground()
            AppLogger.info("  ✅ Released Kokoro TTS pipelines", category: .memory)
        }
        
        // 2. Clear voice preview memory cache (keep disk cache)
        if let voiceCache = dependencies?.voicePreviewCacheService as? VoicePreviewCacheService {
            voiceCache.clearMemoryCache()
            AppLogger.info("  ✅ Cleared voice preview memory cache", category: .memory)
        }
        
        // 3. Clear session TTS queue
        if let sessionQueue = dependencies?.sessionTTSQueueService as? SessionTTSQueueService {
            sessionQueue.clearQueue()
            AppLogger.info("  ✅ Cleared session TTS queue", category: .memory)
        }
        
        hasReleasedForBackground = true
        
        // Post notification for other components
        NotificationCenter.default.post(name: .memoryReleasedForBackground, object: nil)
        
        let endMemory = currentMemoryUsageMB()
        let saved = startMemory - endMemory
        AppLogger.info(
            "Background release complete. Freed ~\(saved)MB (was \(startMemory)MB, now \(endMemory)MB)",
            category: .memory
        )
    }
    
    /// Restores resources after returning from background.
    ///
    /// Called when app returns to foreground after resources were released.
    /// Re-warms Kokoro TTS for smooth user experience.
    func restoreFromBackground() async {
        guard hasReleasedForBackground else {
            AppLogger.debug("Nothing to restore", category: .memory)
            return
        }
        
        AppLogger.info("Restoring resources from background...", category: .memory)
        
        // Re-warm Kokoro TTS (the main thing we need to restore)
        if let ttsService = dependencies?.ttsService {
            await ttsService.warmUp()
            AppLogger.info("  ✅ Re-warmed Kokoro TTS", category: .memory)
        }
        
        // Voice preview cache will reload on-demand from disk
        // Session TTS queue will be rebuilt when session starts
        
        hasReleasedForBackground = false
        
        // Post notification for other components
        NotificationCenter.default.post(name: .memoryRestoredFromBackground, object: nil)
        
        AppLogger.info("Background restore complete", category: .memory)
    }
    
    /// Forces immediate release of all releasable resources.
    ///
    /// Use in extreme memory situations or for testing.
    func forceRelease() async {
        hasReleasedForBackground = false // Reset flag to allow release
        await releaseForBackground()
    }
    
    // MARK: - Memory Diagnostics
    
    /// Returns current memory usage in MB.
    func currentMemoryUsageMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0
        }
        
        return Int(info.resident_size / (1024 * 1024))
    }
    
    /// Logs current memory usage for debugging.
    func logMemoryUsage() {
        let usage = currentMemoryUsageMB()
        AppLogger.info("Current memory usage: \(usage)MB", category: .memory)
        
        #if DEBUG
        print("📊 MemoryManager: Current usage = \(usage)MB")
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when MemoryManager releases resources for background
    static let memoryReleasedForBackground = Notification.Name("com.imprint.memoryReleasedForBackground")
    
    /// Posted when MemoryManager restores resources from background
    static let memoryRestoredFromBackground = Notification.Name("com.imprint.memoryRestoredFromBackground")
}
