//
//  SessionVoiceConfiguration.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/5/26.
//

import Foundation

// MARK: - Session Voice Configuration

/// Immutable snapshot of voice settings for a TTS session.
///
/// Captures the voice ID, voice settings, and System TTS fallback flag
/// at session start. These values remain constant for the entire session
/// duration, ensuring consistent audio even if the user changes settings
/// mid-session.
///
/// ## Usage
/// ```swift
/// // Load at session start
/// let config = SessionVoiceConfiguration.load(
///     voiceId: "kokoro_af_heart",
///     forceSystemTTS: false
/// )
///
/// // Use throughout session
/// let audio = try await engine.synthesize(text: text, config: config)
/// ```
///
/// ## Sendable
/// Fully `Sendable` — safe to pass across async boundaries in TaskGroup
/// synthesis. All fields are immutable value types.
struct SessionVoiceConfiguration: Sendable, Equatable {

    // MARK: - Properties

    /// The voice ID for Kokoro synthesis (e.g., "kokoro_af_heart").
    /// `nil` uses the default voice.
    let voiceId: String?

    /// Voice modulation settings (speed, pitch, expressiveness).
    /// Loaded from `VoiceSettingsManager` at session start.
    let voiceSettings: VoiceSettings

    /// Whether to bypass Kokoro and use System TTS for this session.
    /// Set when user explicitly chooses System TTS from the Kokoro timeout UI.
    let forceSystemTTS: Bool

    // MARK: - Defaults

    /// Default configuration with no voice ID, default settings, Kokoro enabled.
    static let `default` = SessionVoiceConfiguration(
        voiceId: nil,
        voiceSettings: .default,
        forceSystemTTS: false
    )

    // MARK: - Factory

    /// Creates a voice configuration by loading settings from `VoiceSettingsManager`.
    ///
    /// Call this once at session start. The returned configuration is immutable
    /// and captures the user's current voice settings as a snapshot.
    ///
    /// - Parameters:
    ///   - voiceId: The voice ID to use (nil for default)
    ///   - forceSystemTTS: Whether to bypass Kokoro and use System TTS
    /// - Returns: A frozen voice configuration for the session
    @MainActor
    static func load(voiceId: String?, forceSystemTTS: Bool) -> SessionVoiceConfiguration {
        let settings: VoiceSettings
        if let voiceId {
            settings = VoiceSettingsManager.shared.settings(for: voiceId)
        } else {
            settings = .default
        }

        return SessionVoiceConfiguration(
            voiceId: voiceId,
            voiceSettings: settings,
            forceSystemTTS: forceSystemTTS
        )
    }
}
