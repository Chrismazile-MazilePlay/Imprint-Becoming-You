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
/// Centralizes all `setCategory()` calls, manages system notification observers
/// (interruption, route change, configuration change, media reset/lost), and
/// exposes permissions and route info.
///
/// ## Configuration
/// The app permanently uses `.playAndRecord` with `.allowBluetoothA2DP`.
/// ``configure()`` is called once at session start and sets this category.
/// Subsequent calls are no-ops.
///
/// ## Engine Lifecycle
/// After system events (interruptions, media resets), the controller
/// automatically restarts the registered engine and notifies consumers
/// via ``onEngineRestarted``.
@MainActor
final class AudioSessionController: AudioSessionControllerProtocol, Sendable {

    // MARK: - State

    /// Whether the audio session is currently interrupted.
    private(set) var isInterrupted: Bool = false

    /// Whether the audio session is currently active.
    private(set) var isSessionActive: Bool = false

    /// Whether configure() has been called successfully.
    private var isConfigured: Bool = false

    // MARK: - Engine Reference

    /// Weak reference to the shared `AVAudioEngine` managed by `AudioService`.
    private weak var sharedEngine: AVAudioEngine?

    // MARK: - Callbacks

    /// Called after the engine is restarted following a system event.
    var onEngineRestarted: (() -> Void)?

    /// Called when an audio interruption begins.
    var onInterruptionBegan: (() -> Void)?

    /// Called when an audio interruption ends.
    var onInterruptionEnded: ((Bool) -> Void)?

    // MARK: - Notification Observers

    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var routeChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var configurationChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaResetObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaLostObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
        sessionLog.info("AudioSessionController initialized")
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

        // 1. Audio session interruption (phone call, alarm, Siri)
        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }

        // 2. Audio route change (headphones, Bluetooth connect/disconnect)
        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        }

        // 3. Audio engine configuration change (sample rate, channel count)
        configurationChangeObserver = nc.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }

        // 4. Media services were reset (rare — all audio objects orphaned)
        mediaResetObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMediaServicesReset() }
        }

        // 5. Media services were lost (server unavailable — wait for reset)
        mediaLostObserver = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMediaServicesLost() }
        }
    }

    // MARK: - Configuration

    /// Configures the audio session for `.playAndRecord` with `.allowBluetoothA2DP`.
    ///
    /// Called once at the start of a practice session. Subsequent calls are no-ops.
    func configure() async throws {
        guard !isConfigured else {
            sessionLog.debug("Audio session already configured — skipping")
            return
        }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            isConfigured = true
            isSessionActive = true
            sessionLog.info("Audio session configured: .playAndRecord + .allowBluetoothA2DP")
        } catch {
            sessionLog.error("Failed to configure audio session: \(error.localizedDescription)")
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to configure audio session: \(error.localizedDescription)"
            )
        }
    }

    /// Deactivates the audio session.
    func deactivateSession(notifyOthers: Bool = true) {
        guard isSessionActive else { return }

        do {
            let options: AVAudioSession.SetActiveOptions = notifyOthers
                ? [.notifyOthersOnDeactivation] : []
            try AVAudioSession.sharedInstance().setActive(false, options: options)
            isSessionActive = false
            isConfigured = false
            sessionLog.info("Audio session deactivated")
        } catch {
            sessionLog.warning("Failed to deactivate session: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine Registration

    /// Registers the shared `AVAudioEngine` for restart coordination.
    func registerEngine(_ engine: AVAudioEngine) {
        sharedEngine = engine
        sessionLog.debug("Shared engine registered")
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
    func requestMicrophonePermission() async -> Bool {
        sessionLog.info("Requesting microphone permission")
        let granted = await AVAudioApplication.requestRecordPermission()
        sessionLog.info("Microphone permission: \(granted ? "granted" : "denied")")
        return granted
    }

    /// Requests speech recognition permission from the user.
    func requestSpeechRecognitionPermission() async -> Bool {
        sessionLog.info("Requesting speech recognition permission")

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let granted = status == .authorized
                sessionLog.info("Speech recognition permission: \(granted ? "granted" : "denied")")
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

    // MARK: - Notification Handlers

    /// Handles audio session interruptions (phone call, alarm, Siri, etc.).
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            sessionLog.warning("Could not parse interruption notification")
            return
        }

        switch type {
        case .began:
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

            sessionLog.warning("INTERRUPTION BEGAN")
            isInterrupted = true
            isSessionActive = false
            isConfigured = false
            onInterruptionBegan?()

        case .ended:
            let shouldResume: Bool
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            } else {
                shouldResume = false
            }

            sessionLog.info("INTERRUPTION ENDED (shouldResume: \(shouldResume))")
            isInterrupted = false

            // Reconfigure the session and restart the engine
            if shouldResume {
                Task {
                    try? await configure()
                    restartEngineIfNeeded()
                }
            }

            onInterruptionEnded?(shouldResume)

        @unknown default:
            sessionLog.warning("Unknown interruption type")
        }
    }

    /// Handles audio route changes (headphones, Bluetooth, etc.).
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
               let output = previousRoute.outputs.first {
                sessionLog.warning("Device disconnected: \(output.portName)")
            }

        case .newDeviceAvailable:
            let output = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Unknown"
            sessionLog.info("Device connected: \(output)")

        case .categoryChange:
            sessionLog.debug("Category change notification (external)")

        case .override, .routeConfigurationChange:
            sessionLog.debug("Route configuration changed")

        default:
            break
        }
    }

    /// Handles audio engine configuration changes (sample rate, channel count).
    private func handleConfigurationChange() {
        sessionLog.warning("AUDIO ENGINE CONFIGURATION CHANGED")
        restartEngineIfNeeded()
    }

    /// Handles media services reset (rare — all audio objects orphaned).
    private func handleMediaServicesReset() {
        sessionLog.error("MEDIA SERVICES WERE RESET")
        isSessionActive = false
        isInterrupted = false
        isConfigured = false
    }

    /// Handles media services lost (server unavailable).
    private func handleMediaServicesLost() {
        sessionLog.error("MEDIA SERVICES LOST")
        isSessionActive = false
        isConfigured = false
    }

    // MARK: - Engine Restart

    /// Restarts the registered engine if it's not currently running.
    private func restartEngineIfNeeded() {
        guard let engine = sharedEngine, !engine.isRunning else { return }

        do {
            engine.prepare()
            try engine.start()
            sessionLog.info("Engine restarted after system event")
            onEngineRestarted?()
        } catch {
            sessionLog.error("Failed to restart engine: \(error.localizedDescription)")
        }
    }
}
