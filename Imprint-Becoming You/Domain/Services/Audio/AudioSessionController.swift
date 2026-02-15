//
//  AudioSessionController.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import AVFoundation
@preconcurrency import Speech
import os.log

// MARK: - Logger

private let sessionLog = Logger(subsystem: "com.imprint.audio", category: "AudioSessionController")

// MARK: - AudioSessionController

/// Single source of truth for `AVAudioSession` configuration and system notifications.
///
/// This controller centralizes **all** `setCategory()` calls, manages system
/// notification observers (interruption, route change, media reset), and exposes
/// permissions and route info. It fully replaces the legacy `AudioCoordinator`
/// singleton.
///
/// ## Responsibilities
/// - Sole owner of `AVAudioSession.setCategory()` — no other component may call it
/// - Engine lifecycle coordination around HAL reconfigurations
/// - System notification handling (interruption, route change, media reset/lost)
/// - Microphone and speech recognition permission management
/// - Audio route information (headphones, Bluetooth)
///
/// ## Engine Lifecycle
/// - **Playback-only transitions** (`.playback` ↔ `.playback`):
///   `pause()` / `start()` — preserves scheduled audio buffers
/// - **Recording transitions** (→ `.playAndRecord` or ← `.playAndRecord`):
///   `stop()` / `start()` — full teardown/rebuild so the input node reinitializes
/// - **Background dispatch**: `setCategory()` blocks 50–200ms; dispatched off MainActor
///
/// ## Usage
/// ```swift
/// let controller = AudioSessionController()
///
/// // Initial setup (no engine management)
/// try await controller.transition(
///     to: .playback, mode: .spokenAudio,
///     options: [.mixWithOthers], engineAction: .none
/// )
///
/// // Transition to recording (engine stop/restart)
/// try await controller.transition(
///     to: .playAndRecord, mode: .default,
///     options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
/// )
/// ```
@MainActor
final class AudioSessionController: AudioSessionControllerProtocol, Sendable {

    // MARK: - Engine Action

    /// Determines how the shared `AVAudioEngine` is managed during a
    /// category transition.
    enum EngineAction: Sendable {
        /// Automatically choose the appropriate engine lifecycle strategy:
        /// - **Playback-only transitions**: `pause()` / `start()` — preserves buffers
        /// - **Recording transitions**: `stop()` / `start()` — full teardown/rebuild
        case pauseAndResume

        /// Do not touch the engine. Use for initial configuration before the
        /// engine has started, or when the caller manages lifecycle externally.
        case none
    }

    // MARK: - Tracked State

    /// Current audio session category (nil = unknown / not yet configured).
    private(set) var currentCategory: AVAudioSession.Category?

    /// Current audio session mode.
    private(set) var currentMode: AVAudioSession.Mode?

    /// Current audio session category options.
    private(set) var currentOptions: AVAudioSession.CategoryOptions?

    /// Whether the audio session is currently interrupted.
    private(set) var isInterrupted: Bool = false

    /// Whether the audio session is currently active.
    private(set) var isSessionActive: Bool = false

    // MARK: - Engine Reference

    /// Weak reference to the shared `AVAudioEngine` managed by `AudioService`.
    private weak var sharedEngine: AVAudioEngine?

    /// Callback invoked after the engine is restarted following a **full stop**
    /// (recording category transition). Set by `AudioService` to re-schedule
    /// background music, since `engine.stop()` discards all scheduled buffers.
    var onEngineRestartedAfterFullStop: (() -> Void)?

    // MARK: - Interruption Callbacks

    /// Callback invoked when an audio interruption begins.
    var onInterruptionBegan: (() -> Void)?

    /// Callback invoked when an audio interruption ends.
    var onInterruptionEnded: ((Bool) -> Void)?

    // MARK: - Notification Observers

    /// Storage for notification observers (nonisolated access for deinit).
    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var routeChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var configurationChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaResetObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaLostObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
        sessionLog.info("✅ AudioSessionController initialized")
    }

    deinit {
        let nc = NotificationCenter.default
        if let observer = interruptionObserver { nc.removeObserver(observer) }
        if let observer = routeChangeObserver { nc.removeObserver(observer) }
        if let observer = configurationChangeObserver { nc.removeObserver(observer) }
        if let observer = mediaResetObserver { nc.removeObserver(observer) }
        if let observer = mediaLostObserver { nc.removeObserver(observer) }
    }

    // MARK: - Notification Setup

    /// Registers observers for all audio session system notifications.
    private func setupNotificationObservers() {
        let nc = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()

        // Audio session interruption (phone call, alarm, Siri, etc.)
        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }

        // Audio route change (headphones plugged/unplugged, Bluetooth connect/disconnect)
        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }

        // Audio engine configuration change (sample rate, channel count changed by OS)
        configurationChangeObserver = nc.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleConfigurationChange(notification)
            }
        }

        // Media services were reset (rare — all audio objects are orphaned)
        mediaResetObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleMediaServicesReset(notification)
            }
        }

        // Media services were lost (server unavailable — wait for reset)
        mediaLostObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMediaServicesLost()
            }
        }

        sessionLog.debug("📡 Notification observers registered")
    }

    // MARK: - Engine Registration

    /// Registers the shared `AVAudioEngine` for pause/restart coordination.
    ///
    /// Called by `AudioService` after creating its engine. The controller
    /// holds a weak reference — the engine's lifetime is owned by
    /// `AudioService`.
    ///
    /// - Parameter engine: The shared `AVAudioEngine` instance.
    func registerEngine(_ engine: AVAudioEngine) {
        sharedEngine = engine
        sessionLog.debug("🔗 Shared engine registered")
    }

    // MARK: - Permissions

    /// Whether microphone permission is currently granted.
    var hasMicrophonePermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// Whether speech recognition permission is currently granted.
    var hasSpeechRecognitionPermission: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Requests microphone permission from the user.
    ///
    /// - Returns: `true` if permission was granted
    func requestMicrophonePermission() async -> Bool {
        sessionLog.info("🎙️ Requesting microphone permission")
        let granted = await AVAudioApplication.requestRecordPermission()
        sessionLog.info("🎙️ Microphone permission: \(granted ? "granted" : "denied")")
        return granted
    }

    /// Requests speech recognition permission from the user.
    ///
    /// - Returns: `true` if permission was granted
    func requestSpeechRecognitionPermission() async -> Bool {
        sessionLog.info("🗣️ Requesting speech recognition permission")

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let granted = status == .authorized
                sessionLog.info("🗣️ Speech recognition permission: \(granted ? "granted" : "denied")")
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Route Info

    /// Whether headphones (wired or Bluetooth) are connected.
    var headphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
                .contains(output.portType)
        }
    }

    // MARK: - Category Transition

    /// Transitions the audio session to a new category/mode/options configuration.
    ///
    /// This is the **sole** method in the codebase that calls
    /// `AVAudioSession.setCategory()`. All other components must route
    /// session configuration through this method.
    ///
    /// ## Behavior
    ///
    /// 1. **Fast path**: If the requested configuration matches the current
    ///    state, returns immediately (~0ms).
    /// 2. **Engine coordination**: When `engineAction` is `.pauseAndResume`
    ///    and the shared engine is running:
    ///    - For transitions involving `.playAndRecord` (either entering or
    ///      leaving), the engine is **stopped** to force a full audio graph
    ///      teardown/rebuild.
    ///    - For playback-only transitions, the engine is **paused** to
    ///      preserve scheduled audio buffers (background music continues).
    /// 3. **Background dispatch**: The actual `setCategory()` call runs on
    ///    a `.userInitiated` background queue to avoid blocking MainActor.
    ///
    /// - Parameters:
    ///   - category: The desired `AVAudioSession.Category`.
    ///   - mode: The desired `AVAudioSession.Mode` (default: `.default`).
    ///   - options: The desired `AVAudioSession.CategoryOptions` (default: `[]`).
    ///   - engineAction: How to manage the shared engine during transition
    ///     (default: `.pauseAndResume`).
    /// - Throws: `AppError.audioSessionConfigurationFailed` if `setCategory()`
    ///   or `setActive()` fails.
    func transition(
        to category: AVAudioSession.Category,
        mode: AVAudioSession.Mode = .default,
        options: AVAudioSession.CategoryOptions = [],
        engineAction: EngineAction = .pauseAndResume
    ) async throws {
        // Fast path: skip if configuration is identical
        if category == currentCategory && mode == currentMode && options == currentOptions {
            sessionLog.debug("⚡ Session already \(category.rawValue)/\(mode.rawValue) — skipping")
            return
        }

        sessionLog.info(
            "🔄 Transitioning: \(self.currentCategory?.rawValue ?? "nil") → \(category.rawValue), mode: \(mode.rawValue)"
        )

        // Determine whether a full stop is needed. Transitions involving
        // `.playAndRecord` (entering or leaving) require the engine to be
        // stopped and restarted so the input node's HAL connection is
        // properly initialized (or torn down).
        let involvesRecording = category == .playAndRecord || currentCategory == .playAndRecord
        let needsFullStop = involvesRecording

        // Phase 1: Manage engine before HAL reconfiguration
        let engineWasRunning: Bool
        if engineAction == .pauseAndResume, let engine = sharedEngine, engine.isRunning {
            if needsFullStop {
                engine.stop()
                sessionLog.debug("⏹ Engine stopped for recording category transition")
            } else {
                engine.pause()
                sessionLog.debug("⏸ Engine paused for category transition")
            }
            engineWasRunning = true
        } else {
            engineWasRunning = false
        }

        // Phase 2: Set category on background queue (blocks 50-200ms)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(category, mode: mode, options: options)
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AppError.audioSessionConfigurationFailed(
                        reason: "Failed to set category \(category.rawValue): \(error.localizedDescription)"
                    ))
                }
            }
        }

        // Phase 3: Update tracked state
        currentCategory = category
        currentMode = mode
        currentOptions = options
        isSessionActive = true

        // Phase 4: Restart engine after HAL reconfiguration.
        if engineWasRunning, let engine = sharedEngine {
            // After a full stop, allow the HAL to stabilize before restarting.
            // 100ms provides sufficient time on most devices for the microphone
            // hardware path to initialize and report a valid sample rate.
            if needsFullStop {
                try? await Task.sleep(for: .milliseconds(100))
            }

            do {
                try engine.start()
                sessionLog.debug("▶️ Engine restarted after category transition")
            } catch {
                // Retry once after a longer delay
                sessionLog.warning("⚠️ Engine restart failed, retrying in 200ms: \(error.localizedDescription)")
                try? await Task.sleep(for: .milliseconds(200))
                do {
                    try engine.start()
                    sessionLog.info("▶️ Engine restarted on retry")
                } catch {
                    sessionLog.error("❌ Engine restart failed after retry: \(error.localizedDescription)")
                    throw AppError.audioEngineInitializationFailed(
                        reason: "Engine failed to restart after category transition: \(error.localizedDescription)"
                    )
                }
            }

            // After a full stop/start, allow a brief settle time before consumers
            // query the input node format.
            if needsFullStop {
                try? await Task.sleep(for: .milliseconds(50))
            }

            // After a full stop/start, scheduled audio buffers were discarded.
            // Notify AudioService to re-schedule background music.
            if needsFullStop {
                onEngineRestartedAfterFullStop?()
                sessionLog.debug("📢 Notified AudioService of full-stop restart")
            }
        }
    }

    // MARK: - Session Deactivation

    /// Deactivates the audio session.
    ///
    /// - Parameter notifyOthers: Whether to notify other audio apps to resume.
    func deactivateSession(notifyOthers: Bool = true) {
        guard isSessionActive else { return }

        do {
            let options: AVAudioSession.SetActiveOptions = notifyOthers
                ? [.notifyOthersOnDeactivation] : []
            try AVAudioSession.sharedInstance().setActive(false, options: options)
            isSessionActive = false
            sessionLog.info("✅ Audio session deactivated")
        } catch {
            sessionLog.warning("⚠️ Failed to deactivate session: \(error.localizedDescription)")
        }
    }

    // MARK: - State Reset

    /// Resets tracked category/mode/options state.
    ///
    /// Call when iOS resets the audio session (interruption began, media
    /// services reset). The next ``transition(to:mode:options:engineAction:)``
    /// call will perform a full reconfiguration instead of short-circuiting.
    func resetTracking() {
        currentCategory = nil
        currentMode = nil
        currentOptions = nil
        sessionLog.debug("🔄 Session tracking reset")
    }

    // MARK: - Notification Handlers

    /// Handles audio session interruptions (phone call, alarm, Siri, etc.).
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            sessionLog.warning("⚠️ Could not parse interruption notification")
            return
        }

        switch type {
        case .began:
            sessionLog.warning("⚠️ INTERRUPTION BEGAN")

            // Check interruption reason (iOS 14.5+)
            if let reasonValue = userInfo[AVAudioSessionInterruptionReasonKey] as? UInt,
               let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
                switch reason {
                case .appWasSuspended:
                    sessionLog.debug("Ignoring app-was-suspended interruption")
                    return
                case .builtInMicMuted:
                    sessionLog.debug("Built-in mic was muted")
                case .default:
                    sessionLog.debug("Default interruption reason")
                case .routeDisconnected:
                    sessionLog.debug("Route was disconnected")
                @unknown default:
                    sessionLog.debug("Unknown interruption reason")
                }
            }

            isInterrupted = true
            isSessionActive = false
            resetTracking()

            // Notify AudioService to pause music and playback
            onInterruptionBegan?()

        case .ended:
            sessionLog.info("✅ INTERRUPTION ENDED")

            let shouldResume: Bool
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            } else {
                shouldResume = false
            }

            sessionLog.info("Should resume: \(shouldResume)")
            isInterrupted = false

            // Notify AudioService to resume if appropriate
            onInterruptionEnded?(shouldResume)

        @unknown default:
            sessionLog.warning("⚠️ Unknown interruption type")
        }
    }

    /// Handles audio route changes (headphones, Bluetooth, etc.).
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        sessionLog.info("🔀 Route change: \(String(describing: reason))")

        switch reason {
        case .oldDeviceUnavailable:
            if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
               let output = previousRoute.outputs.first {
                sessionLog.warning("⚠️ Device disconnected: \(output.portName)")
            }

        case .newDeviceAvailable:
            let output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Unknown"
            sessionLog.info("🎧 Device connected: \(output)")

        case .categoryChange:
            sessionLog.info("📂 Category changed externally")
            // iOS changed the category externally — reset tracking so next
            // transition() performs a full reconfiguration
            resetTracking()

        case .override, .routeConfigurationChange:
            sessionLog.debug("Route configuration changed")

        default:
            break
        }
    }

    /// Handles audio engine configuration changes (sample rate, channel count).
    private func handleConfigurationChange(_ notification: Notification) {
        sessionLog.warning("⚠️ AUDIO ENGINE CONFIGURATION CHANGED")

        // If the shared engine was stopped by iOS, attempt to restart it
        if let engine = sharedEngine, !engine.isRunning {
            do {
                try engine.start()
                sessionLog.info("✅ Engine restarted after configuration change")
                onEngineRestartedAfterFullStop?()
            } catch {
                sessionLog.error("❌ Failed to restart engine after config change: \(error.localizedDescription)")
            }
        }
    }

    /// Handles media services reset (rare — all audio objects orphaned).
    private func handleMediaServicesReset(_ notification: Notification) {
        sessionLog.error("🔴 MEDIA SERVICES WERE RESET")

        isSessionActive = false
        isInterrupted = false
        resetTracking()

        sessionLog.info("Audio system needs rebuild after media reset")
    }

    /// Handles media services lost (server unavailable).
    private func handleMediaServicesLost() {
        sessionLog.error("🔴 MEDIA SERVICES LOST")

        isSessionActive = false
        resetTracking()
    }
}
