//
//  PracticeEvent.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/3/26.
//

import Foundation

// MARK: - Practice Event

/// All events that can occur in the practice experience.
///
/// Events are categorized by source:
/// - **User Events**: Direct user interactions (taps, swipes)
/// - **Flow Events**: Lifecycle events from audio/speech services
/// - **System Events**: App lifecycle, errors, etc.
///
/// ## Usage
/// ```swift
/// store.send(.selectMode(.readAloud))
/// store.send(.navigate(.next))
/// store.send(.ttsCompleted)
/// ```
///
/// ## Design Decisions
/// - Events carry all data needed to process them
/// - Events are past-tense or imperative (what happened / what should happen)
/// - No ambiguity - each event has one clear meaning
///
/// ## Sendable Safety
/// Marked `@unchecked Sendable` because `Affirmation` is a SwiftData `@Model`
/// (non-Sendable reference type). This is safe because `PracticeStore` is
/// `@MainActor` isolated and all events are processed on the main actor.
enum PracticeEvent: Equatable, @unchecked Sendable {
    
    // MARK: - Mode Selection
    
    /// User selected a practice mode
    case selectMode(SessionMode)
    
    /// User selected a binaural preset
    case selectBinaural(BinauralPreset)
    
    /// User toggled the mode selector expansion
    case toggleModeSelector
    
    /// User toggled the binaural selector expansion
    case toggleBinauralSelector
    
    /// Close all selectors (tapped outside)
    case closeSelectors
    
    // MARK: - Navigation
    
    /// User navigated via swipe gesture (index already changed)
    case userNavigated(NavigationDirection)
    
    /// User tapped skip/previous button (triggers animated transition)
    case navigateViaButton(NavigationDirection)
    
    /// Auto-advance animation completed, continue flow
    case autoAdvanceCompleted
    
    /// Jump to specific affirmation index
    case goToIndex(Int)
    
    // MARK: - Session Control
    
    /// Exit active session, return to home
    case exitSession
    
    /// Start/restart the flow for current affirmation
    case startFlow
    
    /// Pause the current flow (app backgrounded, interruption)
    case pauseFlow
    
    /// Resume a paused flow
    case resumeFlow
    
    // MARK: - TTS Events
    
    /// TTS playback started
    case ttsStarted
    
    /// TTS playback progress updated
    case ttsProgress(Double)
    
    /// TTS playback completed successfully
    case ttsCompleted
    
    /// TTS playback failed
    case ttsFailed(PracticeError)
    
    /// TTS was cancelled (user navigation)
    case ttsCancelled
    
    // MARK: - Speech Recognition Events
    
    /// Started listening for user speech
    case listeningStarted
    
    /// Live update during listening
    case listeningUpdate(ListeningContext)
    
    /// User finished speaking (silence detected or manual stop)
    case listeningCompleted(recognizedText: String, duration: TimeInterval)
    
    /// Speech recognition failed
    case listeningFailed(PracticeError)
    
    /// Listening was cancelled (user navigation)
    case listeningCancelled
    
    // MARK: - Score Events
    
    /// Score calculation started
    case analysisStarted
    
    /// Score calculation completed
    case scoreCalculated(ScoreResult)
    
    /// Score calculation failed
    case scoreFailed(PracticeError)
    
    /// Score display timer expired, ready to advance
    case scoreDisplayCompleted
    
    // MARK: - Affirmation Events
    
    /// User toggled favorite on current affirmation
    case toggleFavorite
    
    /// User tapped share on current affirmation
    case shareAffirmation
    
    /// Record that affirmation was viewed
    case recordView
    
    // MARK: - UI Events
    
    /// Dismiss any displayed error
    case dismissError
    
    /// View appeared
    case viewAppeared
    
    /// View disappeared
    case viewDisappeared
    
    // MARK: - Data Events
    
    /// Affirmations were loaded
    case affirmationsLoaded([Affirmation])
    
    /// Affirmation loading failed
    case affirmationsLoadFailed(PracticeError)
}

// MARK: - Practice Error

/// Errors specific to the practice flow.
///
/// These wrap underlying service errors with context for
/// user-facing error messages.
enum PracticeError: Error, Equatable, Sendable {
    
    /// TTS service error
    case ttsError(String)
    
    /// Speech recognition error
    case speechRecognitionError(String)
    
    /// Microphone access denied
    case microphoneAccessDenied
    
    /// Score calculation error
    case scoreCalculationError(String)
    
    /// Data loading error
    case dataLoadError(String)
    
    /// Audio session error
    case audioSessionError(String)
    
    /// Network error (for cloud TTS)
    case networkError(String)
    
    /// Unknown/unexpected error
    case unknown(String)
    
    /// User-facing error message
    var userMessage: String {
        switch self {
        case .ttsError(let msg):
            return "Unable to play audio: \(msg)"
        case .speechRecognitionError(let msg):
            return "Speech recognition error: \(msg)"
        case .microphoneAccessDenied:
            return "Microphone access is required. Please enable it in Settings."
        case .scoreCalculationError(let msg):
            return "Unable to calculate score: \(msg)"
        case .dataLoadError(let msg):
            return "Unable to load affirmations: \(msg)"
        case .audioSessionError(let msg):
            return "Audio error: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .unknown(let msg):
            return "An error occurred: \(msg)"
        }
    }
    
    /// Whether this error is recoverable
    var isRecoverable: Bool {
        switch self {
        case .microphoneAccessDenied:
            return false // Requires user action in Settings
        case .networkError:
            return true // Can retry
        default:
            return true
        }
    }
}

// MARK: - Event Categorization

extension PracticeEvent {
    
    /// Whether this event cancels current activity
    var cancelsCurrentActivity: Bool {
        switch self {
        case .userNavigated, .navigateViaButton, .goToIndex, .exitSession:
            return true
        case .ttsCancelled, .listeningCancelled:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event is a user interaction (for analytics)
    var isUserInteraction: Bool {
        switch self {
        case .selectMode, .selectBinaural:
            return true
        case .toggleModeSelector, .toggleBinauralSelector, .closeSelectors:
            return true
        case .userNavigated, .navigateViaButton, .goToIndex:
            return true
        case .exitSession:
            return true
        case .toggleFavorite, .shareAffirmation:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event is a flow lifecycle event
    var isFlowEvent: Bool {
        switch self {
        case .startFlow, .pauseFlow, .resumeFlow:
            return true
        case .ttsStarted, .ttsProgress, .ttsCompleted, .ttsFailed, .ttsCancelled:
            return true
        case .listeningStarted, .listeningUpdate, .listeningCompleted, .listeningFailed, .listeningCancelled:
            return true
        case .analysisStarted, .scoreCalculated, .scoreFailed, .scoreDisplayCompleted:
            return true
        case .autoAdvanceCompleted:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event affects navigation state
    var affectsNavigation: Bool {
        switch self {
        case .userNavigated, .navigateViaButton, .goToIndex, .autoAdvanceCompleted:
            return true
        default:
            return false
        }
    }
}

// MARK: - Event Descriptions

extension PracticeEvent: CustomStringConvertible {
    var description: String {
        switch self {
        case .selectMode(let mode):
            return "selectMode(\(mode.rawValue))"
        case .selectBinaural(let preset):
            return "selectBinaural(\(preset.rawValue))"
        case .toggleModeSelector:
            return "toggleModeSelector"
        case .toggleBinauralSelector:
            return "toggleBinauralSelector"
        case .closeSelectors:
            return "closeSelectors"
        case .userNavigated(let dir):
            return "userNavigated(\(dir))"
        case .navigateViaButton(let dir):
            return "navigateViaButton(\(dir))"
        case .autoAdvanceCompleted:
            return "autoAdvanceCompleted"
        case .goToIndex(let idx):
            return "goToIndex(\(idx))"
        case .exitSession:
            return "exitSession"
        case .startFlow:
            return "startFlow"
        case .pauseFlow:
            return "pauseFlow"
        case .resumeFlow:
            return "resumeFlow"
        case .ttsStarted:
            return "ttsStarted"
        case .ttsProgress(let p):
            return "ttsProgress(\(Int(p * 100))%)"
        case .ttsCompleted:
            return "ttsCompleted"
        case .ttsFailed(let err):
            return "ttsFailed(\(err))"
        case .ttsCancelled:
            return "ttsCancelled"
        case .listeningStarted:
            return "listeningStarted"
        case .listeningUpdate(let ctx):
            return "listeningUpdate(level: \(String(format: "%.2f", ctx.audioLevel)))"
        case .listeningCompleted(let text, let dur):
            return "listeningCompleted(\(text.prefix(20))..., \(String(format: "%.1f", dur))s)"
        case .listeningFailed(let err):
            return "listeningFailed(\(err))"
        case .listeningCancelled:
            return "listeningCancelled"
        case .analysisStarted:
            return "analysisStarted"
        case .scoreCalculated(let result):
            return "scoreCalculated(\(result.percentScore)%)"
        case .scoreFailed(let err):
            return "scoreFailed(\(err))"
        case .scoreDisplayCompleted:
            return "scoreDisplayCompleted"
        case .toggleFavorite:
            return "toggleFavorite"
        case .shareAffirmation:
            return "shareAffirmation"
        case .recordView:
            return "recordView"
        case .dismissError:
            return "dismissError"
        case .viewAppeared:
            return "viewAppeared"
        case .viewDisappeared:
            return "viewDisappeared"
        case .affirmationsLoaded(let affs):
            return "affirmationsLoaded(\(affs.count) items)"
        case .affirmationsLoadFailed(let err):
            return "affirmationsLoadFailed(\(err))"
        }
    }
}
