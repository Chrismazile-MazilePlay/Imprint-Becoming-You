//
//  AudioCoordinatorState.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/10/26.
//

import AVFoundation

// MARK: - AudioCoordinatorError

/// Errors from the audio coordinator
/// Defined FIRST because AudioCoordinatorState references it
enum AudioCoordinatorError: Error, Equatable, Sendable, CustomStringConvertible {
    case sessionConfigurationFailed(String)
    case sessionActivationFailed(String)
    case engineStartFailed(String)
    case ttsNotAvailable
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case mediaServerReset
    case interruptionNotRecoverable
    case alreadyInUse(currentState: String)
    
    var description: String {
        switch self {
        case .sessionConfigurationFailed(let reason): return "sessionConfigurationFailed(\(reason))"
        case .sessionActivationFailed(let reason): return "sessionActivationFailed(\(reason))"
        case .engineStartFailed(let reason): return "engineStartFailed(\(reason))"
        case .ttsNotAvailable: return "ttsNotAvailable"
        case .microphonePermissionDenied: return "microphonePermissionDenied"
        case .speechRecognitionPermissionDenied: return "speechRecognitionPermissionDenied"
        case .mediaServerReset: return "mediaServerReset"
        case .interruptionNotRecoverable: return "interruptionNotRecoverable"
        case .alreadyInUse(let state): return "alreadyInUse(\(state))"
        }
    }
}

// MARK: - AudioCoordinatorState

/// Represents the current state of the audio system.
///
/// Uses `indirect` for recursive cases to avoid infinite size.
enum AudioCoordinatorState: Equatable, Sendable, CustomStringConvertible {
    /// No audio activity
    case idle
    
    /// Text-to-speech is playing
    case playingTTS
    
    /// Microphone capture + speech recognition active
    case listening
    
    /// TTS playing, will transition to listening when done
    case playingTTSThenListen
    
    /// System interrupted our audio (phone call, alarm, etc.)
    /// Marked `indirect` because it references AudioCoordinatorState recursively
    indirect case interrupted(previousState: AudioCoordinatorState)
    
    /// Recovering from interruption
    case recovering
    
    /// Media server reset - requires full reconstruction
    case mediaReset
    
    /// Error state
    case error(AudioCoordinatorError)
    
    var description: String {
        switch self {
        case .idle: return "idle"
        case .playingTTS: return "playingTTS"
        case .listening: return "listening"
        case .playingTTSThenListen: return "playingTTSThenListen"
        case .interrupted(let prev): return "interrupted(was: \(prev))"
        case .recovering: return "recovering"
        case .mediaReset: return "mediaReset"
        case .error(let err): return "error(\(err))"
        }
    }
    
    static func == (lhs: AudioCoordinatorState, rhs: AudioCoordinatorState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.playingTTS, .playingTTS): return true
        case (.listening, .listening): return true
        case (.playingTTSThenListen, .playingTTSThenListen): return true
        case (.recovering, .recovering): return true
        case (.mediaReset, .mediaReset): return true
        case (.interrupted(let a), .interrupted(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - AudioRouteChange

/// Describes an audio route change
enum AudioRouteChange: Sendable, CustomStringConvertible {
    case deviceConnected(String)
    case deviceDisconnected(String)
    case categoryChanged
    case configurationChanged
    
    var description: String {
        switch self {
        case .deviceConnected(let device): return "deviceConnected(\(device))"
        case .deviceDisconnected(let device): return "deviceDisconnected(\(device))"
        case .categoryChanged: return "categoryChanged"
        case .configurationChanged: return "configurationChanged"
        }
    }
}

// MARK: - AudioCoordinatorEvent

/// Events emitted by the coordinator for UI binding
enum AudioCoordinatorEvent: Sendable {
    case stateChanged(AudioCoordinatorState)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(AudioRouteChange)
    case errorOccurred(AudioCoordinatorError)
    case ttsStarted
    case ttsFinished
    case ttsProgress(word: String, progress: Float)
    case listeningStarted
    case listeningStopped
    case transcriptionReceived(String)
}
