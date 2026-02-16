//
//  AudioSessionControllerProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import AVFoundation

// MARK: - AudioSessionControllerProtocol

/// Consumer-facing interface for centralized audio session management.
///
/// The sole mechanism through which any component may configure the
/// `AVAudioSession`. No direct `setCategory()` calls are permitted
/// elsewhere in the codebase.
///
/// ## Responsibilities
/// - One-time `.playAndRecord` configuration with `.allowBluetoothA2DP`
/// - Microphone and speech recognition permission management
/// - Audio route information
/// - System event handling (interruptions, route changes, media resets)
///
/// ## Thread Safety
/// All members are `@MainActor` isolated, matching `AudioService`.
@MainActor
protocol AudioSessionControllerProtocol: AnyObject {

    // MARK: - State

    /// Whether the audio session is currently interrupted (phone call, alarm, etc.).
    var isInterrupted: Bool { get }

    /// Whether the audio session is currently active.
    var isSessionActive: Bool { get }

    // MARK: - Permissions

    /// Whether microphone permission is currently granted.
    var hasMicrophonePermission: Bool { get }

    /// Whether speech recognition permission is currently granted.
    var hasSpeechRecognitionPermission: Bool { get }

    /// Requests microphone permission from the user.
    ///
    /// - Returns: `true` if permission was granted
    func requestMicrophonePermission() async -> Bool

    /// Requests speech recognition permission from the user.
    ///
    /// - Returns: `true` if permission was granted
    func requestSpeechRecognitionPermission() async -> Bool

    // MARK: - Route Info

    /// Whether headphones (wired or Bluetooth) are connected.
    var headphonesConnected: Bool { get }

    // MARK: - Configuration

    /// Configures the audio session for `.playAndRecord` with `.allowBluetoothA2DP`.
    ///
    /// Called once at the start of a practice session. Sets the category,
    /// activates the session, and begins listening for system notifications.
    /// Subsequent calls are no-ops if already configured.
    ///
    /// - Throws: `AppError.audioSessionConfigurationFailed` if `setCategory()`
    ///   or `setActive()` fails.
    func configure() async throws

    /// Deactivates the audio session.
    ///
    /// Called at the end of a practice session to release audio hardware
    /// and allow other apps to resume playback.
    ///
    /// - Parameter notifyOthers: Whether to notify other audio apps that
    ///   the session is being deactivated so they can resume playback.
    func deactivateSession(notifyOthers: Bool)

    // MARK: - Engine Registration

    /// Registers the shared `AVAudioEngine` for restart coordination.
    ///
    /// Called by `AudioService` after creating its engine. The controller
    /// holds a weak reference — the engine's lifetime is owned by
    /// `AudioService`. After system events (interruptions, media resets),
    /// the controller restarts the engine automatically.
    ///
    /// - Parameter engine: The shared `AVAudioEngine` instance.
    func registerEngine(_ engine: AVAudioEngine)

    // MARK: - Callbacks

    /// Called after the engine is restarted following a system event.
    ///
    /// Set by `AudioService` to re-schedule background music, since
    /// `engine.stop()` discards all scheduled buffers.
    var onEngineRestarted: (() -> Void)? { get set }

    /// Called when an audio interruption begins (phone call, alarm, etc.).
    ///
    /// Set by `AudioService` to pause background music and playback.
    var onInterruptionBegan: (() -> Void)? { get set }

    /// Called when an audio interruption ends.
    ///
    /// - Parameter shouldResume: Whether iOS recommends resuming playback.
    /// Set by `AudioService` to resume background music if appropriate.
    var onInterruptionEnded: ((Bool) -> Void)? { get set }
}
