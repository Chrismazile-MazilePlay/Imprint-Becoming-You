//
//  PracticeStore.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/3/26.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - PracticeStore

/// The single source of truth for the practice experience.
///
/// ## Architecture
/// - All state is centralized here
/// - All mutations go through `send(_ event:)`
/// - Views bind to this store and call `send()` for interactions
/// - Async effects (TTS, listening, etc.) are managed internally
/// - All services accessed via `DependencyContainer` for testability
///
/// ## File Organization
/// This file contains only state definitions and computed properties.
/// Behavior is organized into focused extensions:
/// - `+Events` - Event dispatch routing
/// - `+Handlers` - Synchronous state mutations
/// - `+FlowExecution` - Async TTS/listening flows
/// - `+Session` - Queue and session lifecycle
/// - `+DataLoading` - Repository interactions
/// - `+Previews` - Development support
@MainActor
@Observable
final class PracticeStore {
    
    // MARK: - Flow State
    
    /// The current flow state (mode + phase)
    private(set) var flow: PracticeFlow = .home
    
    /// Progress through current segment (0.0 - 1.0)
    private(set) var segmentProgress: CGFloat = 0
    
    /// Pending auto-advance direction (triggers VerticalPager animation)
    var pendingAutoAdvance: NavigationDirection? = nil
    
    /// Whether navigation is temporarily locked (during score display)
    private(set) var isNavigationLocked: Bool = false
    
    // MARK: - Browse Queue State (Default Mode)
    
    /// Affirmations for browse mode (batch of 30).
    private(set) var browseAffirmations: [Affirmation] = []
    
    /// Current index in browse queue.
    private(set) var browseIndex: Int = 0
    
    /// Total affirmations consumed from browse batch.
    private(set) var browseBatchConsumed: Int = 0
    
    /// Whether a browse batch refresh is in progress
    var isBrowseBatchRefreshInProgress: Bool = false
    
    /// IDs of affirmations already viewed in current browse batch.
    var viewedBrowseAffirmationIds: Set<UUID> = []
    
    // MARK: - Session Queue State (Non-Default Modes)
    
    /// Affirmations for current session (10 items).
    private(set) var sessionAffirmations: [Affirmation] = []
    
    /// Current index in session queue (0-9).
    private(set) var sessionIndex: Int = 0
    
    /// Number of unique affirmations practiced in current session.
    var sessionProgress: Int {
        sessionResults.count
    }
    
    // MARK: - Session Summary State
    
    /// Whether the results summary is being shown
    private(set) var isShowingSummary: Bool = false
    
    /// Results collected during the session for summary display
    private(set) var sessionResults: [SessionAffirmationResult] = []
    
    /// The mode used for the session (for retry functionality)
    var sessionMode: SessionMode = .readOnly
    
    /// Timestamp when session started
    var sessionStartTime: Date = Date()
    
    /// Complete session summary for display
    var sessionSummary: SessionSummary {
        SessionSummary(
            mode: sessionMode,
            results: sessionResults,
            startedAt: sessionStartTime
        )
    }
    
    // MARK: - Audio State
    
    /// Current binaural preset
    private(set) var binauralPreset: BinauralPreset = .off
    
    /// Last recorded resonance score
    private(set) var lastResonanceRecord: ResonanceRecord? = nil
    
    // MARK: - UI State
    
    /// Whether mode selector is expanded
    var isModeSelectorExpanded: Bool = false
    
    /// Whether binaural selector is expanded
    var isBinauralSelectorExpanded: Bool = false
    
    /// Current error (if any)
    private(set) var error: PracticeError? = nil
    
    // MARK: - Internal State
    
    /// Active flow task (cancellable)
    var activeFlowTask: Task<Void, Never>? = nil
    
    /// Flow generation counter - incremented on each mode/index change.
    var flowGeneration: Int = 0
    
    /// Last user interaction timestamp
    var lastInteractionTime: Date = Date()
    
    /// Categories used for loading
    var loadedCategories: [String] = []
    
    // MARK: - Speech Capture Service
    
    /// Speech capture service backing storage
    @ObservationIgnored
    private var _speechCaptureService: SpeechCaptureService?
    
    /// Speech capture service for recognition (lazily created)
    var speechCaptureService: SpeechCaptureService {
        if let existing = _speechCaptureService {
            return existing
        }
        let service = SpeechCaptureService()
        _speechCaptureService = service
        return service
    }
    
    /// Active listening task
    var listeningTask: Task<Void, Never>?
    
    /// Listening start time for timeout tracking
    var listeningStartTime: Date?
    
    /// Whether the timeout alert is showing
    private(set) var isShowingTimeoutAlert: Bool = false
    
    /// Whether the permission denied alert is showing
    private(set) var isShowingPermissionAlert: Bool = false
    
    /// Type of permission that was denied
    private(set) var deniedPermissionType: PermissionType = .microphone
    
    /// User's calibration data
    var calibrationData: CalibrationData?
    
    // MARK: - Dependencies
    
    /// Service dependencies (injected via DependencyContainer).
    let dependencies: DependencyContainer
    
    /// Repository for affirmation data access
    var repository: (any AffirmationRepositoryProtocol)?
    
    // MARK: - Initialization
    
    /// Creates a new practice store with the shared dependency container
    convenience init() {
        self.init(dependencies: .shared)
    }
    
    /// Creates a new practice store with custom dependencies
    /// - Parameter dependencies: Service container for dependency injection
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    // MARK: - Computed Properties (Active Queue Routing)
    
    /// The affirmations for the currently active queue.
    var affirmations: [Affirmation] {
        isSessionActive ? sessionAffirmations : browseAffirmations
    }
    
    /// The current index in the active queue.
    var currentIndex: Int {
        isSessionActive ? sessionIndex : browseIndex
    }
    
    /// The currently displayed affirmation
    var currentAffirmation: Affirmation? {
        let queue = affirmations
        let index = currentIndex
        guard queue.indices.contains(index) else { return nil }
        return queue[index]
    }
    
    /// Whether we can navigate to previous affirmation
    var canGoPrevious: Bool {
        currentIndex > 0
    }
    
    /// Whether we can navigate to next affirmation
    var canGoNext: Bool {
        if isSessionActive {
            return sessionIndex < Constants.Session.sessionSize - 1
        }
        return browseIndex < browseAffirmations.count - 1
    }
    
    /// Total count of affirmations in active queue
    var totalCount: Int {
        affirmations.count
    }
    
    /// Progress fraction (0.0 - 1.0)
    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(currentIndex + 1) / Double(totalCount)
    }
    
    /// Progress text (e.g., "3 / 10")
    var progressText: String {
        "\(currentIndex + 1) / \(totalCount)"
    }
    
    // MARK: - Computed Properties (Session)
    
    /// Whether we're in an active session (not home)
    var isSessionActive: Bool {
        flow.isActiveMode
    }
    
    /// The current session mode
    var currentMode: SessionMode {
        flow.sessionMode
    }
    
    /// Whether navigation should be blocked
    var shouldBlockNavigation: Bool {
        isNavigationLocked || flow.shouldBlockNavigation
    }
    
    /// Real-time score for dock display
    var realtimeScore: Double {
        flow.scoreResult?.score ?? 0
    }
    
    /// Session progress text
    var sessionProgressText: String {
        "\(sessionProgress) / \(Constants.Session.sessionSize)"
    }
    
    // MARK: - Computed Properties (Dock Display)
    
    /// Total count for dock progress bar display.
    var displayTotalCount: Int {
        isSessionActive ? Constants.Session.sessionSize : browseAffirmations.count
    }
    
    /// Current index for dock progress bar display.
    var displayCurrentIndex: Int {
        isSessionActive ? sessionIndex : browseIndex
    }
    
    // MARK: - Computed Properties (Background)
    
    /// Background state for morphing gradient
    var background: BackgroundState {
        BackgroundState(
            currentCategory: currentAffirmation?.goalCategory,
            previousCategory: previousAffirmation?.goalCategory
        )
    }
    
    /// Previous affirmation (for background transitions)
    private var previousAffirmation: Affirmation? {
        let queue = affirmations
        let index = currentIndex
        guard index > 0 else { return nil }
        return queue[index - 1]
    }
    
    // MARK: - State Mutation Helpers
    
    /// Updates the flow state
    func setFlow(_ newFlow: PracticeFlow) {
        flow = newFlow
    }
    
    /// Updates segment progress
    func setSegmentProgress(_ progress: CGFloat) {
        segmentProgress = progress
    }
    
    /// Updates navigation lock
    func setNavigationLocked(_ locked: Bool) {
        isNavigationLocked = locked
    }
    
    /// Updates browse queue state
    func setBrowseState(affirmations: [Affirmation]? = nil, index: Int? = nil, consumed: Int? = nil) {
        if let affirmations = affirmations { browseAffirmations = affirmations }
        if let index = index { browseIndex = index }
        if let consumed = consumed { browseBatchConsumed = consumed }
    }
    
    /// Updates session queue state
    func setSessionState(affirmations: [Affirmation]? = nil, index: Int? = nil) {
        if let affirmations = affirmations { sessionAffirmations = affirmations }
        if let index = index { sessionIndex = index }
    }
    
    /// Updates session results
    func setSessionResults(_ results: [SessionAffirmationResult]) {
        sessionResults = results
    }
    
    /// Appends a session result
    func appendSessionResult(_ result: SessionAffirmationResult) {
        sessionResults.append(result)
    }
    
    /// Updates a session result at index
    func updateSessionResult(at index: Int, score: Int? = nil, isFavorited: Bool? = nil) {
        if let score = score { sessionResults[index].score = score }
        if let isFavorited = isFavorited { sessionResults[index].isFavorited = isFavorited }
    }
    
    /// Updates summary visibility
    func setShowingSummary(_ showing: Bool) {
        isShowingSummary = showing
    }
    
    /// Updates binaural preset
    func setBinauralPreset(_ preset: BinauralPreset) {
        binauralPreset = preset
    }
    
    /// Updates last resonance record
    func setLastResonanceRecord(_ record: ResonanceRecord?) {
        lastResonanceRecord = record
    }
    
    /// Updates error state
    func setError(_ error: PracticeError?) {
        self.error = error
    }
    
    /// Updates timeout alert visibility
    func setShowingTimeoutAlert(_ showing: Bool) {
        isShowingTimeoutAlert = showing
    }
    
    /// Updates permission alert state
    func setPermissionAlert(showing: Bool, type: PermissionType? = nil) {
        isShowingPermissionAlert = showing
        if let type = type { deniedPermissionType = type }
    }
}
