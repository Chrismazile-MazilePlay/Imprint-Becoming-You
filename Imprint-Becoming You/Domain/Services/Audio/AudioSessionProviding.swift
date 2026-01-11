//
//  AudioSessionProviding.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/10/26.
//

import AVFoundation

// MARK: - AudioSessionProviding

/// Core protocol for audio session configuration and lifecycle.
///
/// ## Design
/// - Follows Interface Segregation Principle (ISP)
/// - Provides minimum interface needed for audio session management
/// - Implementations can be AudioCoordinator (production) or mocks (testing)
@MainActor
protocol AudioSessionProviding: Sendable {
    
    // MARK: - Session Configuration
    
    /// Configures audio session for playback only (TTS, binaural)
    func configureForPlayback() throws
    
    /// Configures audio session for playback and recording (speech recognition)
    func configureForPlaybackAndRecording() throws
    
    /// Configures audio session for recording only (voice calibration)
    func configureForRecording() throws
    
    // MARK: - Session Activation
    
    /// Activates the audio session
    func activateSession() throws
    
    /// Deactivates the audio session
    func deactivateSession(notifyOthers: Bool)
    
    /// Whether the audio session is currently active
    var isSessionActive: Bool { get }
}

// MARK: - AudioPermissionProviding

/// Protocol for audio-related permissions.
@MainActor
protocol AudioPermissionProviding: Sendable {
    
    /// Whether microphone permission is granted
    var hasMicrophonePermission: Bool { get }
    
    /// Whether speech recognition permission is granted
    var hasSpeechRecognitionPermission: Bool { get }
    
    /// Requests microphone permission
    func requestMicrophonePermission() async -> Bool
    
    /// Requests speech recognition permission
    func requestSpeechRecognitionPermission() async -> Bool
}

// MARK: - AudioRouteProviding

/// Protocol for audio route information.
@MainActor
protocol AudioRouteProviding: Sendable {
    
    /// Current audio output route description
    var currentRoute: String { get }
    
    /// Whether headphones are connected
    var headphonesConnected: Bool { get }
    
    /// Current hardware sample rate
    var sampleRate: Double { get }
}

// MARK: - AudioInterruptionHandling

/// Protocol for handling audio interruptions.
@MainActor
protocol AudioInterruptionHandling: Sendable {
    
    /// Stream of audio coordinator events
    var eventStream: AsyncStream<AudioCoordinatorEvent> { get }
    
    /// Current state of the audio coordinator
    var state: AudioCoordinatorState { get }
}

// MARK: - FullAudioSessionProviding

/// Full audio session provider combining all capabilities.
/// Use this for components that need complete audio session access.
@MainActor
protocol FullAudioSessionProviding: AudioSessionProviding,
                                      AudioPermissionProviding,
                                      AudioRouteProviding,
                                      AudioInterruptionHandling {}

// MARK: - Legacy Compatibility Types

/// Events representing audio session interruptions.
/// Preserved for backward compatibility with existing code.
enum AudioInterruptionEvent: Sendable {
    /// Interruption began (e.g., phone call)
    case began
    /// Interruption ended
    case ended(shouldResume: Bool)
}

/// Reasons for audio route changes.
/// Preserved for backward compatibility.
enum AudioRouteChangeReason: Sendable {
    case deviceConnected
    case deviceDisconnected
    case categoryChanged
}

/// Delegate protocol for receiving audio session events.
/// Preserved for backward compatibility - prefer using eventStream instead.
protocol AudioSessionDelegate: AnyObject, Sendable {
    /// Called when audio session is interrupted
    func audioSessionWasInterrupted()
    
    /// Called when audio session interruption ends
    func audioSessionInterruptionEnded(shouldResume: Bool)
    
    /// Called when audio route changes
    func audioRouteChanged(reason: AudioRouteChangeReason)
}

extension AudioSessionDelegate {
    func audioSessionWasInterrupted() {}
    func audioSessionInterruptionEnded(shouldResume: Bool) {}
    func audioRouteChanged(reason: AudioRouteChangeReason) {}
}
