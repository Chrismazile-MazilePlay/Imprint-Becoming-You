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
    
    /// Full app-level reset after extended background (>10 min).
    ///
    /// Resets from ANY state (summary, profile, active session) back to
    /// home (Practice page, Read Only mode). Clears all session state.
    case resetToHome
    
    /// Start/restart the flow for current affirmation
    case startFlow
    
    /// Pause the current flow (app backgrounded, interruption)
    case pauseFlow
    
    /// Resume a paused flow
    case resumeFlow
    
    /// Pause session when app enters background (stops TTS/listening, preserves state)
    case pauseSession
    
    /// Resume session when app returns from background
    case resumeSession
    
    // MARK: - Session Preparation Events
    
    /// Session preparation completed successfully
    case sessionPreparationCompleted
    
    /// Session preparation failed
    case sessionPreparationFailed(PracticeError)
    
    /// User cancelled session preparation
    case cancelSessionPreparation
    
    // MARK: - Session Summary Events
    
    /// User dismissed the summary, return to home
    case dismissSummary
    
    /// User tapped repeat session (with current loop/shuffle config)
    case repeatSession
    
    /// User tapped repeat session with custom mode/loop/shuffle/spaced-rep from summary dock.
    ///
    /// Routes through `prepareAndStartSession` to ensure TTS is properly prepared
    /// when the mode changes (e.g. Speak Only -> Read Aloud on repeat).
    case repeatSessionWithConfig(mode: SessionMode, loopCount: Int, shuffle: Bool, spacedRepetition: Bool)
    
    /// User toggled favorite on an affirmation in the summary
    /// - Parameter affirmationId: The ID of the affirmation to toggle
    case toggleFavoriteInSummary(UUID)
    
    // MARK: - Loop & Shuffle Events
    
    /// User cycled the loop count (1 -> 3 -> 5 -> 1)
    case cycleLoopCount
    
    /// User toggled shuffle on/off
    case toggleShuffle
    
    /// Current loop iteration completed, check for more loops
    case loopIterationCompleted
    
    // MARK: - Saved Session Events
    
    /// User tapped play on a saved session
    case startSavedSession(SavedSession)
    
    /// Clear saved session context (when session ends)
    case clearSavedSessionContext
    
    /// User wants to save current session
    case saveSession(name: String)
    
    // MARK: - Favorites Session Events

    /// User tapped play on favorites list.
    ///
    /// Follows the same synchronous event-driven pattern as `startSavedSession`.
    /// Affirmations are pre-fetched by `FavoritesFullListView` and passed directly,
    /// avoiding unnecessary `async` suspension that could cause voice ID staleness.
    case startFavoritesSession(affirmations: [Affirmation], mode: SessionMode, shuffle: Bool)

    // MARK: - Remote Session Start Events

    /// Start a session from a remote page (Favorites or Saved Sessions).
    ///
    /// Replaces the old "Stage, Navigate, Execute" pattern. The fullScreenCover
    /// presents immediately, then session data loads inside the cover.
    /// No navigation choreography needed — the cover is a separate view hierarchy.
    case startRemoteSession(source: RemoteSessionSource, loopConfiguration: LoopConfiguration)

    // MARK: - Session Cover Lifecycle

    /// Fired from the fullScreenCover's `onDismiss` callback after dismiss animation completes.
    ///
    /// Performs consolidated cleanup: stops audio, clears session state, resets flow to home,
    /// releases TTS resources, and resets all presentation flags.
    case sessionCoverDismissed
    
    // MARK: - TTS Events
    
    /// TTS synthesis started
    case ttsStarted
    
    /// TTS playback progress updated
    case ttsProgress(Double)
    
    /// TTS playback completed normally
    case ttsCompleted
    
    /// TTS failed with error
    case ttsFailed(PracticeError)
    
    /// TTS was cancelled (user action)
    case ttsCancelled
    
    // MARK: - Speech Recognition Events
    
    /// Speech recognition started (microphone active)
    case listeningStarted
    
    /// Speech recognition update (partial results, audio level)
    case listeningUpdate(ListeningContext)
    
    /// Speech recognition completed with final text and voice analytics
    case listeningCompleted(recognizedText: String, duration: TimeInterval, voiceAnalytics: VoiceAnalyticsSummary)
    
    /// Speech recognition failed
    case listeningFailed(PracticeError)
    
    /// Speech recognition was cancelled
    case listeningCancelled
    
    /// Speech recognition timed out (no speech detected)
    case listeningTimedOut
    
    /// User tapped retry after timeout
    case retryListening
    
    /// User tapped skip after timeout
    case skipAffirmation
    
    // MARK: - Permission Events
    
    /// A required permission was denied
    case permissionDenied(PermissionType)
    
    /// User chose to open Settings for permission
    case openSettings
    
    /// User chose to continue without the permission
    case continueWithoutPermission
    
    // MARK: - Score Events
    
    /// Score analysis started
    case analysisStarted
    
    /// Score was calculated
    case scoreCalculated(ScoreResult)
    
    /// Score calculation failed
    case scoreFailed(PracticeError)
    
    /// Score display timer expired, ready to advance
    case scoreDisplayCompleted
    
    // MARK: - Segment Timer Events
    
    /// Dock's segment animation timer completed (triggers auto-advance)
    ///
    /// This event is fired by the DockModule when a progress segment fills
    /// from 0% to 100% over its configured duration WITHOUT user interruption.
    /// The host should trigger auto-advance to the next affirmation.
    case segmentTimerCompleted
    
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
    
    // MARK: - Legacy Aliases
    
    /// @deprecated Use `repeatSession` instead. Kept for compatibility.
    static var retrySession: PracticeEvent { .repeatSession }
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
    
    /// Another app (call, Zoom, FaceTime) is using the microphone
    case audioSessionBusy
    
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
        case .audioSessionBusy:
            return "The microphone is being used by another app. End your call or meeting to use speech practice."
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
        case .audioSessionBusy:
            return false // Requires user to end call/meeting
        case .networkError:
            return true // Can retry
        default:
            return true
        }
    }
}

// MARK: - Event Categorization

// Note: PermissionType is defined in AppError.swift

extension PracticeEvent {
    
    /// Whether this event cancels current activity
    var cancelsCurrentActivity: Bool {
        switch self {
        case .userNavigated, .navigateViaButton, .goToIndex, .exitSession, .resetToHome:
            return true
        case .ttsCancelled, .listeningCancelled:
            return true
        case .listeningTimedOut, .skipAffirmation:
            return true
        case .repeatSession, .repeatSessionWithConfig, .startSavedSession, .startFavoritesSession:
            return true
        case .startRemoteSession:
            return true
        case .sessionCoverDismissed:
            return true
        case .cancelSessionPreparation:
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
        case .cycleLoopCount, .toggleShuffle:
            return true
        case .repeatSession, .repeatSessionWithConfig, .startSavedSession, .startFavoritesSession, .saveSession:
            return true
        case .startRemoteSession:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event is a flow lifecycle event
    var isFlowEvent: Bool {
        switch self {
        case .startFlow, .pauseFlow, .resumeFlow, .pauseSession, .resumeSession:
            return true
        case .ttsStarted, .ttsProgress, .ttsCompleted, .ttsFailed, .ttsCancelled:
            return true
        case .listeningStarted, .listeningUpdate, .listeningCompleted, .listeningFailed, .listeningCancelled:
            return true
        case .listeningTimedOut, .retryListening, .skipAffirmation:
            return true
        case .analysisStarted, .scoreCalculated, .scoreFailed, .scoreDisplayCompleted:
            return true
        case .autoAdvanceCompleted, .loopIterationCompleted, .segmentTimerCompleted:
            return true
        case .sessionPreparationCompleted, .sessionPreparationFailed, .cancelSessionPreparation:
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
        case .loopIterationCompleted, .segmentTimerCompleted:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event is related to loop/shuffle functionality
    var isLoopEvent: Bool {
        switch self {
        case .cycleLoopCount, .toggleShuffle, .loopIterationCompleted, .repeatSession, .repeatSessionWithConfig:
            return true
        default:
            return false
        }
    }
    
    /// Whether this event is related to saved sessions
    var isSavedSessionEvent: Bool {
        switch self {
        case .startSavedSession, .clearSavedSessionContext, .saveSession:
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
        case .resetToHome:
            return "resetToHome"
        case .dismissSummary:
            return "dismissSummary"
        case .repeatSession:
            return "repeatSession"
        case .repeatSessionWithConfig(let mode, let loopCount, let shuffle, let spacedRepetition):
            return "repeatSessionWithConfig(\(mode.rawValue), loops: \(loopCount), shuffle: \(shuffle), spacedRep: \(spacedRepetition))"
        case .toggleFavoriteInSummary(let id):
            return "toggleFavoriteInSummary(\(id.uuidString.prefix(8)))"
        case .cycleLoopCount:
            return "cycleLoopCount"
        case .toggleShuffle:
            return "toggleShuffle"
        case .loopIterationCompleted:
            return "loopIterationCompleted"
        case .startSavedSession(let session):
            return "startSavedSession(\(session.name))"
        case .clearSavedSessionContext:
            return "clearSavedSessionContext"
        case .saveSession(let name):
            return "saveSession(\(name))"
        case .startFavoritesSession(let affs, let mode, let shuffle):
            return "startFavoritesSession(\(affs.count) affirmations, \(mode.rawValue), shuffle: \(shuffle))"
        case .startRemoteSession(let source, _):
            switch source {
            case .favorites(let affs, let mode, _):
                return "startRemoteSession(favorites: \(affs.count) affirmations, \(mode.rawValue))"
            case .savedSession(let session):
                return "startRemoteSession(savedSession: \(session.name))"
            }
        case .sessionCoverDismissed:
            return "sessionCoverDismissed"
        case .startFlow:
            return "startFlow"
        case .pauseFlow:
            return "pauseFlow"
        case .resumeFlow:
            return "resumeFlow"
        case .pauseSession:
            return "pauseSession"
        case .resumeSession:
            return "resumeSession"
        case .sessionPreparationCompleted:
            return "sessionPreparationCompleted"
        case .sessionPreparationFailed(let err):
            return "sessionPreparationFailed(\(err))"
        case .cancelSessionPreparation:
            return "cancelSessionPreparation"
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
        case .listeningCompleted(let text, let dur, let analytics):
            return "listeningCompleted(\(text.prefix(20))..., \(String(format: "%.1f", dur))s, segments: \(analytics.segmentCount))"
        case .listeningFailed(let err):
            return "listeningFailed(\(err))"
        case .listeningCancelled:
            return "listeningCancelled"
        case .listeningTimedOut:
            return "listeningTimedOut"
        case .retryListening:
            return "retryListening"
        case .skipAffirmation:
            return "skipAffirmation"
        case .permissionDenied(let type):
            return "permissionDenied(\(type))"
        case .openSettings:
            return "openSettings"
        case .continueWithoutPermission:
            return "continueWithoutPermission"
        case .analysisStarted:
            return "analysisStarted"
        case .scoreCalculated(let result):
            return "scoreCalculated(\(result.percentScore)%)"
        case .scoreFailed(let err):
            return "scoreFailed(\(err))"
        case .scoreDisplayCompleted:
            return "scoreDisplayCompleted"
        case .segmentTimerCompleted:
            return "segmentTimerCompleted"
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
