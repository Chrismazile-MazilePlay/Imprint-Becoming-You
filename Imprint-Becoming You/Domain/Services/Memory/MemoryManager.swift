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
/// ## Session-Aware Background Strategy
/// Memory release is **tiered** based on whether a practice session (or summary
/// view) is active:
///
/// ### Active Session / Summary View
/// | Tier | Trigger | Action |
/// |------|---------|--------|
/// | T0   | Background entry | Cancel voice preview only. Cache + pipeline preserved. |
/// | T1   | 45s in background | Soft-release Kokoro pipeline (~800MB-1.5GB). Cache preserved. |
/// | T2   | 10 min in background | Full reset via `handleResetToHome()`. |
/// | —    | Memory warning | Hard-release everything immediately (safety valve). |
///
/// ### No Active Session
/// | Tier | Trigger | Action |
/// |------|---------|--------|
/// | T0   | Background entry | Clear stale TTS queue, repo cache, voice preview. |
/// | T1   | 5s in background | Soft-release Kokoro pipeline. |
/// | —    | Memory warning | Hard-release everything immediately. |
///
/// ## Lazy Restore
/// Kokoro is NOT eagerly reloaded on foreground. It loads on-demand when the
/// user starts a session via `prepareSession()`, or transparently reloads via
/// `ensurePipeline()` if soft-released.
///
/// ## Usage
/// ```swift
/// // At app launch, setup memory monitoring
/// MemoryManager.shared.startMonitoring(dependencies: container)
///
/// // At session start
/// MemoryManager.shared.sessionDidStart()
///
/// // At session end (dismiss summary, exit, or reset)
/// MemoryManager.shared.sessionDidEnd()
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

    /// Whether Kokoro was hard-released (memory warning) and needs `warmUp()`
    /// on foreground restore. Soft release (normal background) keeps Kokoro
    /// marked ready and doesn't need warm-up.
    private var needsKokoroWarmUp: Bool = false

    /// Whether an active practice session (or summary view) is in progress.
    ///
    /// Set by `PracticeStore` via `sessionDidStart()` / `sessionDidEnd()`.
    /// When `true`, the app enters background with a grace period before
    /// releasing the Kokoro pipeline, and the audio cache is never cleared
    /// by MemoryManager (only by PracticeStore on session teardown).
    ///
    /// The summary view counts as "active" because the user may repeat the
    /// session using cached audio.
    private(set) var hasActiveSession: Bool = false

    /// Delayed pipeline release task — cancelled when user returns to foreground.
    ///
    /// When the app enters background, pipeline release is deferred by a grace
    /// period (45s for active sessions, 5s otherwise). If the user returns before
    /// the grace period expires, this task is cancelled and the pipeline stays warm.
    private var delayedReleaseTask: Task<Void, Never>?

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

        // Cancel background check task and delayed release
        stopBackgroundMonitoring()
        delayedReleaseTask?.cancel()
        delayedReleaseTask = nil

        isMonitoring = false
        AppLogger.info("MemoryManager: Stopped monitoring", category: .memory)
    }

    // MARK: - Session Lifecycle

    /// Signals that a practice session (or summary view) has started.
    ///
    /// While active, background entry defers pipeline release and preserves
    /// the TTS audio cache for seamless resume.
    ///
    /// Called by `PracticeStore` at:
    /// - `startSession()` — session begins
    ///
    /// The session stays "active" through the summary view so cached audio
    /// is available for instant repeat. `sessionDidEnd()` is called when the
    /// user dismisses the summary, exits, or the 10-minute timeout fires.
    func sessionDidStart() {
        hasActiveSession = true
        AppLogger.debug("MemoryManager: Session started (hasActiveSession=true)", category: .memory)
    }

    /// Signals that the practice session lifecycle is complete.
    ///
    /// Called by `PracticeStore` at:
    /// - `handleDismissSummary()` — user taps Done on summary
    /// - `handleExitSession()` — user exits mid-session
    /// - `handleResetToHome()` — 10-minute background timeout
    func sessionDidEnd() {
        hasActiveSession = false
        AppLogger.debug("MemoryManager: Session ended (hasActiveSession=false)", category: .memory)
    }

    // MARK: - Memory Events

    /// Handles iOS memory warning notification.
    ///
    /// Cancels any pending delayed release and uses `releaseHard()` which fully
    /// disables Kokoro (sets `isKokoroReady = false`). Memory warnings override
    /// the grace period — iOS survival takes priority over user experience.
    private func handleMemoryWarning() async {
        AppLogger.warning("MEMORY WARNING received from iOS", category: .memory)

        // Cancel any pending delayed release — we're doing a hard release now
        delayedReleaseTask?.cancel()
        delayedReleaseTask = nil

        // Release everything possible — hard kill
        await releaseHard()

        // Log current memory state
        logMemoryUsage()
    }

    /// Handles app entering background with session-aware tiered release.
    ///
    /// ## Active Session Path
    /// When `hasActiveSession` is `true` (session in progress or summary view):
    /// - Cancel voice preview synthesis (not session-critical)
    /// - Schedule delayed pipeline release after `sessionPipelineGracePeriod` (45s)
    /// - Audio cache and repository cache are **untouched**
    ///
    /// ## No Session Path
    /// When `hasActiveSession` is `false` (browse mode, home, etc.):
    /// - Clear stale TTS queue and repository cache immediately
    /// - Cancel voice preview synthesis
    /// - Schedule delayed pipeline release after `nonSessionPipelineGracePeriod` (5s)
    ///
    /// In both paths, the delayed release uses a cancellable `Task.sleep`. If the
    /// user returns to foreground before the grace period expires, the task is
    /// cancelled in `handleWillEnterForeground()` and the pipeline stays warm.
    private func handleDidEnterBackground() {
        backgroundedAt = Date()
        AppLogger.info("App entered background (hasActiveSession=\(hasActiveSession))", category: .memory)

        // Cancel any existing delayed release from a previous background cycle
        delayedReleaseTask?.cancel()
        delayedReleaseTask = nil

        if hasActiveSession {
            // ── Active Session Path ──
            // Preserve audio cache and repo cache. Only cancel voice preview
            // (not session-critical) and schedule delayed pipeline release.
            dependencies?.voicePreviewCacheService.cancelSynthesis()
            AppLogger.info("  Cancelled voice preview synthesis (session active)", category: .memory)

            let gracePeriod = Constants.Background.sessionPipelineGracePeriod
            AppLogger.info("  Scheduling pipeline release in \(Int(gracePeriod))s (session active)", category: .memory)

            delayedReleaseTask = Task { @MainActor [weak self] in
                guard let self = self else { return }

                do {
                    try await Task.sleep(for: .seconds(gracePeriod))
                } catch {
                    // Cancelled — user returned to foreground
                    AppLogger.debug("Pipeline release cancelled (user returned)", category: .memory)
                    return
                }

                // Grace period expired — soft-release pipeline only
                AppLogger.info("Session pipeline grace period expired — releasing pipeline", category: .memory)
                let startMemory = self.currentMemoryUsageMB()

                if let ttsService = self.dependencies?.ttsService as? TTSService {
                    await ttsService.releasePipelineMemory()
                    AppLogger.info("  Released Kokoro pipeline memory (Kokoro still ready)", category: .memory)
                }

                self.hasReleasedForBackground = true
                NotificationCenter.default.post(name: .memoryReleasedForBackground, object: nil)

                let endMemory = self.currentMemoryUsageMB()
                let saved = startMemory - endMemory
                AppLogger.info(
                    "Delayed session release complete. Freed ~\(saved)MB (was \(startMemory)MB, now \(endMemory)MB)",
                    category: .memory
                )
            }
        } else {
            // ── No Session Path ──
            // No active session — clear stale caches immediately,
            // then schedule a short delayed pipeline release.
            dependencies?.voicePreviewCacheService.cancelSynthesis()
            AppLogger.info("  Cancelled voice preview synthesis", category: .memory)

            if let sessionQueue = dependencies?.sessionTTSQueueService as? SessionTTSQueueService {
                sessionQueue.clearQueue()
                AppLogger.info("  Cleared stale session TTS queue", category: .memory)
            }

            DependencyContainer.shared.clearRepositoryCache()
            AppLogger.info("  Cleared repository cache", category: .memory)

            let gracePeriod = Constants.Background.nonSessionPipelineGracePeriod
            AppLogger.info("  Scheduling pipeline release in \(Int(gracePeriod))s (no session)", category: .memory)

            delayedReleaseTask = Task { @MainActor [weak self] in
                guard let self = self else { return }

                do {
                    try await Task.sleep(for: .seconds(gracePeriod))
                } catch {
                    // Cancelled — user returned to foreground
                    AppLogger.debug("Pipeline release cancelled (user returned)", category: .memory)
                    return
                }

                // Grace period expired — soft-release pipeline
                AppLogger.info("Non-session pipeline grace period expired — releasing pipeline", category: .memory)
                let startMemory = self.currentMemoryUsageMB()

                if let ttsService = self.dependencies?.ttsService as? TTSService {
                    await ttsService.releasePipelineMemory()
                    AppLogger.info("  Released Kokoro pipeline memory (Kokoro still ready)", category: .memory)
                }

                self.hasReleasedForBackground = true
                NotificationCenter.default.post(name: .memoryReleasedForBackground, object: nil)

                let endMemory = self.currentMemoryUsageMB()
                let saved = startMemory - endMemory
                AppLogger.info(
                    "Delayed non-session release complete. Freed ~\(saved)MB (was \(startMemory)MB, now \(endMemory)MB)",
                    category: .memory
                )
            }
        }

        // Start periodic background checking for diagnostic logging
        startBackgroundMonitoring()
    }

    /// Handles app returning to foreground.
    ///
    /// Immediately cancels any pending delayed pipeline release, then restores
    /// resources if they were released during background.
    private func handleWillEnterForeground() async {
        // Cancel any pending delayed release FIRST — pipeline stays warm
        delayedReleaseTask?.cancel()
        delayedReleaseTask = nil

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

    /// Starts periodic background checks for session timeout tracking.
    ///
    /// This monitoring only logs elapsed time for diagnostic purposes and
    /// can be cancelled cleanly when the app returns to foreground.
    private func startBackgroundMonitoring() {
        // Cancel any existing task
        backgroundCheckTask?.cancel()

        backgroundCheckTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            let checkInterval = Constants.Background.backgroundCheckInterval

            AppLogger.debug(
                "Background monitoring started (check every \(Int(checkInterval))s)",
                category: .memory
            )

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(checkInterval))

                guard !Task.isCancelled else {
                    AppLogger.debug("Background monitoring cancelled during sleep", category: .memory)
                    return
                }

                guard let backgroundTime = self.backgroundedAt else {
                    AppLogger.debug("Background monitoring: no longer in background", category: .memory)
                    return
                }

                let elapsed = Date().timeIntervalSince(backgroundTime)
                AppLogger.debug(
                    "Background check: \(Int(elapsed))s elapsed",
                    category: .memory
                )
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
    /// Performs a full release of all non-essential resources:
    /// 1. Kokoro TTS ML pipeline (~800MB-1.5GB) via soft release
    /// 2. Voice preview synthesis
    /// 3. Session TTS audio cache (~20-40MB)
    /// 4. Repository instance cache
    ///
    /// This method is now primarily used by the non-session background path
    /// and by `releaseHard()`. The session-aware tiered release in
    /// `handleDidEnterBackground()` handles the common case.
    func releaseForBackground() async {
        guard !hasReleasedForBackground else {
            AppLogger.debug("Already released for background", category: .memory)
            return
        }

        AppLogger.info("Releasing resources for background...", category: .memory)
        let startMemory = currentMemoryUsageMB()

        // 1. Release Kokoro TTS pipeline memory (biggest savings ~800MB-1.5GB).
        // Uses releasePipelineMemory() which keeps isKokoroReady=true so the
        // pipeline transparently reloads on next synthesis. This preserves
        // the user's custom voice when resuming from background.
        if let ttsService = dependencies?.ttsService as? TTSService {
            await ttsService.releasePipelineMemory()
            AppLogger.info("  Released Kokoro pipeline memory (Kokoro still ready)", category: .memory)
        }

        // 2. Cancel any in-flight voice preview synthesis
        dependencies?.voicePreviewCacheService.cancelSynthesis()
        AppLogger.info("  Cancelled voice preview synthesis", category: .memory)

        // 3. Clear session TTS queue unconditionally.
        if let sessionQueue = dependencies?.sessionTTSQueueService as? SessionTTSQueueService {
            sessionQueue.clearQueue()
            AppLogger.info("  Cleared session TTS queue", category: .memory)
        }

        // 4. Clear repository instance cache to free references
        DependencyContainer.shared.clearRepositoryCache()
        AppLogger.info("  Cleared repository cache", category: .memory)

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
    ///
    /// ## Restore Strategy
    /// - **Soft release** (normal background): Kokoro pipeline was freed via
    ///   `releasePipelineMemory()` but `isKokoroReady` is still `true`. The pipeline
    ///   transparently reloads on next synthesis call. No warm-up needed.
    /// - **Hard release** (memory warning): Kokoro was fully disabled via
    ///   `releaseForBackground()`. Needs `warmUp()` to re-initialize.
    func restoreFromBackground() async {
        guard hasReleasedForBackground else {
            AppLogger.debug("Nothing to restore", category: .memory)
            return
        }

        AppLogger.info("Restoring from background...", category: .memory)

        // Only warm up Kokoro if it was hard-released (memory warning).
        // Normal background release keeps isKokoroReady=true and the
        // pipeline transparently reloads on next synthesis call.
        if needsKokoroWarmUp {
            if let ttsService = dependencies?.ttsService {
                await ttsService.warmUp()
                AppLogger.info("  Re-warmed Kokoro TTS (was hard-released)", category: .memory)
            }
            needsKokoroWarmUp = false
        }

        // Voice preview cache reloads on-demand from disk.
        // Session TTS queue rebuilds when session starts.
        // Repository cache rebuilds on-demand when repositories are requested.

        hasReleasedForBackground = false

        // Post notification for other components
        NotificationCenter.default.post(name: .memoryRestoredFromBackground, object: nil)

        AppLogger.info("Background restore complete", category: .memory)
    }

    /// Aggressively releases all resources including fully disabling Kokoro.
    ///
    /// Called on iOS memory warnings where the OS is actively threatening
    /// to kill the app. Unlike `releaseForBackground()`, this:
    /// - Calls `ttsService.releaseForBackground()` (sets `isKokoroReady = false`)
    /// - Requires `warmUp()` to restore Kokoro functionality
    ///
    /// The user's custom voice will need to be re-initialized on next session start.
    private func releaseHard() async {
        AppLogger.warning("Hard memory release (memory warning)...", category: .memory)
        let startMemory = currentMemoryUsageMB()

        // 1. Hard-release Kokoro (sets isKokoroReady = false)
        if let ttsService = dependencies?.ttsService as? TTSService {
            await ttsService.releaseForBackground()
            needsKokoroWarmUp = true
            AppLogger.info("  Hard-released Kokoro TTS (isKokoroReady=false)", category: .memory)
        }

        // 2. Cancel voice preview synthesis
        dependencies?.voicePreviewCacheService.cancelSynthesis()

        // 3. Clear session TTS queue unconditionally
        if let sessionQueue = dependencies?.sessionTTSQueueService as? SessionTTSQueueService {
            sessionQueue.clearQueue()
        }

        // 4. Clear repository cache
        DependencyContainer.shared.clearRepositoryCache()

        hasReleasedForBackground = true

        NotificationCenter.default.post(name: .memoryReleasedForBackground, object: nil)

        let endMemory = currentMemoryUsageMB()
        let saved = startMemory - endMemory
        AppLogger.warning(
            "Hard release complete. Freed ~\(saved)MB (was \(startMemory)MB, now \(endMemory)MB)",
            category: .memory
        )
    }

    /// Forces immediate release of all releasable resources.
    ///
    /// Use in extreme memory situations or for testing.
    func forceRelease() async {
        hasReleasedForBackground = false // Reset flag to allow release
        await releaseHard()
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
        print("💻 MemoryManager: Current usage = \(usage)MB")
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
