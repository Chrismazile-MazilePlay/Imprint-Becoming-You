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
/// This protocol abstracts `AudioSessionController`, enabling mock injection
/// for tests and previews. It is the **sole** mechanism through which any
/// component may reconfigure the `AVAudioSession` — no direct `setCategory()`
/// calls are permitted elsewhere in the codebase.
///
/// ## Responsibilities
/// - Audio session category transitions (coordinated with engine lifecycle)
/// - Microphone and speech recognition permission management
/// - Audio route information
/// - Interruption / media-reset reactive state
///
/// ## Architecture
/// ```
/// AudioSessionControllerProtocol
/// ├── AudioSessionController (Production)
/// └── MockAudioSessionController (Testing)
/// ```
///
/// ## Thread Safety
/// All members are `@MainActor` isolated, matching `AudioService`.
@MainActor
protocol AudioSessionControllerProtocol: AnyObject {

    // MARK: - Reactive State

    /// Whether the audio session is currently interrupted (phone call, alarm, etc.).
    var isInterrupted: Bool { get }

    /// Whether the audio session is currently active.
    var isSessionActive: Bool { get }

    /// Current audio session category (`nil` if not yet configured).
    var currentCategory: AVAudioSession.Category? { get }

    /// Current audio session mode (`nil` if not yet configured).
    var currentMode: AVAudioSession.Mode? { get }

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

    // MARK: - Session Transitions

    /// Transitions the audio session to a new category/mode/options configuration.
    ///
    /// This is the **sole** method in the codebase that calls
    /// `AVAudioSession.setCategory()`. All other components must route
    /// session configuration through this method.
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
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions,
        engineAction: AudioSessionController.EngineAction
    ) async throws

    /// Deactivates the audio session.
    ///
    /// - Parameter notifyOthers: Whether to notify other audio apps that the
    ///   session is being deactivated so they can resume playback.
    func deactivateSession(notifyOthers: Bool)

    /// Resets tracked category/mode/options state.
    ///
    /// Call when iOS resets the audio session (interruption began, media
    /// services reset). The next ``transition(to:mode:options:engineAction:)``
    /// call will perform a full reconfiguration instead of short-circuiting.
    func resetTracking()

    // MARK: - Engine Registration

    /// Registers the shared `AVAudioEngine` for pause/restart coordination.
    ///
    /// Called by `AudioService` after creating its engine. The controller
    /// holds a weak reference — the engine's lifetime is owned by
    /// `AudioService`.
    ///
    /// - Parameter engine: The shared `AVAudioEngine` instance.
    func registerEngine(_ engine: AVAudioEngine)

    /// Callback invoked after the engine is restarted following a **full stop**
    /// (recording category transition). Set by `AudioService` to re-schedule
    /// background music, since `engine.stop()` discards all scheduled buffers.
    var onEngineRestartedAfterFullStop: (() -> Void)? { get set }

    // MARK: - Interruption Callbacks

    /// Callback invoked when an audio interruption begins (phone call, alarm, etc.).
    ///
    /// Set by `AudioService` to pause background music and other playback.
    var onInterruptionBegan: (() -> Void)? { get set }

    /// Callback invoked when an audio interruption ends.
    ///
    /// - Parameter shouldResume: Whether iOS recommends resuming playback.
    /// Set by `AudioService` to resume background music if appropriate.
    var onInterruptionEnded: ((Bool) -> Void)? { get set }
}
