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
/// - `+LoopSession` - Loop, shuffle, and saved session handling
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
    
    /// Generation counter for segment reset signaling.
    ///
    /// Increment this to signal DockSegmentsView to restart its timer.
    /// The dock observes this via the adapter and resets when it changes.
    private(set) var segmentGeneration: Int = 0
    
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
    
    /// Original session affirmation order (before any shuffles).
    /// Used for saved session reference and de-duplication.
    private(set) var originalSessionAffirmationIds: [UUID] = []
    
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
    
    // MARK: - Loop Configuration State
    
    /// Current loop configuration (count, shuffle, iteration)
    private(set) var loopConfiguration: LoopConfiguration = .default
    
    /// ID of the saved session currently being played (if any)
    private(set) var playingSavedSessionId: UUID? = nil
    
    /// Title of the saved session currently being played (if any)
    private(set) var playingSavedSessionTitle: String? = nil
    
    /// Whether the current session was started from Favorites
    private(set) var isFavoritesSession: Bool = false
    
    // MARK: - Session Preparation State
    
    /// Whether TTS preparation is in progress for a new session
    private(set) var isPreparingSession: Bool = false
    
    /// Progress of session TTS preparation (0.0 - 1.0)
    private(set) var sessionPreparationProgress: Float = 0
    
    /// Number of affirmations prepared for current session
    private(set) var sessionPreparedCount: Int = 0
    
    /// Target number of affirmations to prepare before starting
    private(set) var sessionPreparationTarget: Int = 0
    
    /// Mode pending for session start (set during preparation)
    private(set) var pendingSessionMode: SessionMode? = nil
    
    /// Active preparation task (for cancellation)
    var sessionPreparationTask: Task<Void, Never>?
    
    // MARK: - Loop Computed Properties
    
    /// Progress text for loop display (e.g., "Loop 2 of 3")
    /// Returns nil if not looping (single play)
    var loopProgressText: String? {
        loopConfiguration.progressText
    }
    
    /// Whether we're currently playing a saved session
    var isPlayingSavedSession: Bool {
        playingSavedSessionId != nil
    }
    
    // MARK: - Session Summary Computed Property
    
    /// Complete session summary for display
    var sessionSummary: SessionSummary {
        SessionSummary(
            mode: sessionMode,
            results: sessionResults,
            startedAt: sessionStartTime,
            loopCount: loopConfiguration.loopCount,
            savedSessionId: playingSavedSessionId,
            savedSessionTitle: playingSavedSessionTitle
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
    
    // MARK: - Voice Configuration
    
    /// The TTS voice ID to use for playback (raw Kokoro format, e.g., "af_heart").
    /// Set by MainPracticeView from UserProfile.selectedVoiceId.
    var selectedVoiceId: String? = nil
    
    // MARK: - Dependencies
    
    /// Service dependencies (injected via DependencyContainer).
    let dependencies: DependencyContainer
    
    /// Repository for affirmation data access
    var repository: (any AffirmationRepositoryProtocol)?
    
    /// Repository for saved session data access
    var savedSessionRepository: (any SavedSessionRepositoryProtocol)?
    
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
    
    /// The current affirmation (if any).
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
            return sessionIndex < sessionAffirmations.count - 1
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
        isSessionActive ? sessionAffirmations.count : browseAffirmations.count
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
    
    /// Increments the segment generation counter to trigger a timer reset.
    ///
    /// Call this when the current segment should restart from the beginning:
    /// - Returning from background
    /// - Retrying after timeout
    /// - Any interruption requiring a fresh start
    func incrementSegmentGeneration() {
        segmentGeneration += 1
        #if DEBUG
        print("[DEBUG] PracticeStore: Segment generation incremented to \(segmentGeneration)")
        #endif
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
        if let affirmations = affirmations {
            sessionAffirmations = affirmations
            // Capture original order when first setting affirmations
            if originalSessionAffirmationIds.isEmpty {
                originalSessionAffirmationIds = affirmations.map(\.id)
            }
        }
        if let index = index { sessionIndex = index }
    }
    
    /// Updates session affirmations without capturing original IDs.
    ///
    /// Used for shuffle operations where we want to preserve the original
    /// order for saved session reference.
    func setSessionAffirmationsForShuffle(_ affirmations: [Affirmation]) {
        sessionAffirmations = affirmations
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
        guard sessionResults.indices.contains(index) else { return }
        
        var result = sessionResults[index]
        if let score = score { result.score = score }
        if let isFavorited = isFavorited { result.isFavorited = isFavorited }
        sessionResults[index] = result
        
        #if DEBUG
        if let score = score {
            print("[OK] PracticeStore: Updated score=\(score) for result at index \(index), loopScores=\(result.loopScores)")
        }
        #endif
    }
    
    /// Adds a loop score to a session result at index
    func addLoopScoreToResult(at index: Int, score: Int) {
        guard sessionResults.indices.contains(index) else { return }
        
        var result = sessionResults[index]
        result.addLoopScore(score)
        sessionResults[index] = result
        
        #if DEBUG
        print("[OK] PracticeStore: Added loop score=\(score) for result at index \(index), loopScores=\(result.loopScores)")
        #endif
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
    
    // MARK: - Loop Configuration Helpers
    
    /// Updates loop configuration
    func setLoopConfiguration(_ config: LoopConfiguration) {
        loopConfiguration = config
    }
    
    /// Resets loop configuration to defaults
    func resetLoopConfiguration() {
        loopConfiguration = .default
    }
    
    /// Resets loop iteration to 1 (for starting a new repeat, keeping loop/shuffle settings)
    func resetLoopIteration() {
        loopConfiguration.resetIteration()
    }
    
    /// Advances to the next loop iteration
    func advanceLoopIteration() {
        loopConfiguration.advanceLoop()
    }
    
    /// Sets saved session context
    func setSavedSessionContext(id: UUID?, title: String?) {
        playingSavedSessionId = id
        playingSavedSessionTitle = title
    }
    
    /// Clears saved session context
    func clearSavedSessionContext() {
        playingSavedSessionId = nil
        playingSavedSessionTitle = nil
        isFavoritesSession = false
    }
    
    /// Sets favorites session flag
    func setFavoritesSession(_ value: Bool) {
        isFavoritesSession = value
    }
    
    /// Clears original session affirmation IDs (for new session)
    func clearOriginalSessionAffirmationIds() {
        originalSessionAffirmationIds = []
    }
    
    // MARK: - Session Preparation Helpers
    
    /// Updates session preparation state
    func setSessionPreparation(
        isActive: Bool,
        progress: Float? = nil,
        preparedCount: Int? = nil,
        target: Int? = nil
    ) {
        isPreparingSession = isActive
        if let progress = progress { sessionPreparationProgress = progress }
        if let preparedCount = preparedCount { sessionPreparedCount = preparedCount }
        if let target = target { sessionPreparationTarget = target }
    }
    
    /// Sets the pending session mode (during preparation)
    func setPendingSessionMode(_ mode: SessionMode?) {
        pendingSessionMode = mode
    }
    
    /// Clears session preparation state
    func clearSessionPreparation() {
        isPreparingSession = false
        sessionPreparationProgress = 0
        sessionPreparedCount = 0
        sessionPreparationTarget = 0
        pendingSessionMode = nil
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
    }
}
