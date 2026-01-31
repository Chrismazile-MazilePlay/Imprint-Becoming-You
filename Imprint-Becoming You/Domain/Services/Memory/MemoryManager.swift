//
//  MemoryManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import Foundation
import UIKit
import os.log

// MARK: - Logger

private let memoryLog = Logger(subsystem: "com.imprint.memory", category: "MemoryManager")

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
    
    // MARK: - Configuration
    
    /// Time in background after which we release ML models (5 minutes)
    private static let backgroundReleaseThreshold: TimeInterval = 300
    
    /// Time in background for aggressive cleanup (10 minutes)
    private static let aggressiveCleanupThreshold: TimeInterval = 600
    
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
        memoryLog.info("✅ MemoryManager: Started monitoring")
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
        
        isMonitoring = false
        memoryLog.info("🛑 MemoryManager: Stopped monitoring")
    }
    
    // MARK: - Memory Events
    
    /// Handles iOS memory warning notification.
    private func handleMemoryWarning() async {
        memoryLog.warning("⚠️ MEMORY WARNING received from iOS")
        
        // Release everything possible
        await releaseForBackground()
        
        // Log current memory state
        logMemoryUsage()
    }
    
    /// Handles app entering background.
    private func handleDidEnterBackground() {
        backgroundedAt = Date()
        memoryLog.info("📱 App entered background")
        
        // Schedule delayed cleanup if we stay in background
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.backgroundReleaseThreshold))
            
            // Check if we're still in background
            if let backgroundTime = backgroundedAt {
                let elapsed = Date().timeIntervalSince(backgroundTime)
                if elapsed >= Self.backgroundReleaseThreshold {
                    memoryLog.info("⏰ Background threshold reached (\(Int(elapsed))s), releasing resources")
                    await releaseForBackground()
                }
            }
        }
    }
    
    /// Handles app returning to foreground.
    private func handleWillEnterForeground() async {
        let timeInBackground: TimeInterval
        if let backgroundTime = backgroundedAt {
            timeInBackground = Date().timeIntervalSince(backgroundTime)
        } else {
            timeInBackground = 0
        }
        
        backgroundedAt = nil
        memoryLog.info("📱 App entering foreground (was background for \(Int(timeInBackground))s)")
        
        // Restore if we released resources
        if hasReleasedForBackground {
            await restoreFromBackground()
        }
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
            memoryLog.debug("Already released for background")
            return
        }
        
        memoryLog.info("🧹 Releasing resources for background...")
        let startMemory = currentMemoryUsageMB()
        
        // 1. Release Kokoro TTS pipelines (biggest savings)
        if let ttsService = dependencies?.ttsService as? TTSService {
            await ttsService.releaseForBackground()
            memoryLog.info("  ✅ Released Kokoro TTS pipelines")
        }
        
        // 2. Clear voice preview memory cache (keep disk cache)
        if let voiceCache = dependencies?.voicePreviewCacheService as? VoicePreviewCacheService {
            voiceCache.clearMemoryCache()
            memoryLog.info("  ✅ Cleared voice preview memory cache")
        }
        
        // 3. Clear session TTS queue
        if let sessionQueue = dependencies?.sessionTTSQueueService as? SessionTTSQueueService {
            sessionQueue.clearQueue()
            memoryLog.info("  ✅ Cleared session TTS queue")
        }
        
        hasReleasedForBackground = true
        
        let endMemory = currentMemoryUsageMB()
        let saved = startMemory - endMemory
        memoryLog.info("✅ Background release complete. Freed ~\(saved)MB (was \(startMemory)MB, now \(endMemory)MB)")
    }
    
    /// Restores resources after returning from background.
    ///
    /// Called when app returns to foreground after resources were released.
    /// Re-warms Kokoro TTS for smooth user experience.
    func restoreFromBackground() async {
        guard hasReleasedForBackground else {
            memoryLog.debug("Nothing to restore")
            return
        }
        
        memoryLog.info("🔄 Restoring resources from background...")
        
        // Re-warm Kokoro TTS (the main thing we need to restore)
        if let ttsService = dependencies?.ttsService {
            await ttsService.warmUp()
            memoryLog.info("  ✅ Re-warmed Kokoro TTS")
        }
        
        // Voice preview cache will reload on-demand from disk
        // Session TTS queue will be rebuilt when session starts
        
        hasReleasedForBackground = false
        memoryLog.info("✅ Background restore complete")
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
        memoryLog.info("📊 Current memory usage: \(usage)MB")
        
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
