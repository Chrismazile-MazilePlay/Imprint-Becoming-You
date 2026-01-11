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
///
/// ## Dual Queue Architecture
/// The store maintains two independent queues:
///
/// ### Browse Queue (Default Mode)
/// - `browseAffirmations`: 30 affirmations for casual browsing
/// - `browseIndex`: User's position, preserved across sessions
/// - Supports batch refresh when nearing end
///
/// ### Session Queue (Non-Default Modes)
/// - `sessionAffirmations`: 10 fresh affirmations for focused practice
/// - `sessionIndex`: Position within session (0-9)
/// - Generated on session start, excludes recently browsed
/// - Cleared when session ends
///
/// ## Queue Independence
/// - Starting a session doesn't affect browse queue position
/// - Exiting a session returns user to their browse position
/// - Session queue is always fresh (avoids showing same affirmations)
///
/// ## Source Priority
/// Session queue prioritizes:
/// 1. AI-generated content (most personalized)
/// 2. Backend content (curated)
/// 3. Seeded content (offline fallback)
///
/// ## Usage
/// ```swift
/// @Bindable var store: PracticeStore
///
/// // Read state (automatically routes to active queue)
/// Text(store.currentAffirmation?.text ?? "")
/// if store.flow.isListening { ListeningIndicator() }
///
/// // Send events
/// Button("Next") { store.send(.navigateViaButton(.next)) }
/// ```
@MainActor
@Observable
final class PracticeStore {
    
    // MARK: - Flow State
    
    /// The current flow state (mode + phase)
    private(set) var flow: PracticeFlow = .home
    
    /// Progress through current segment (0.0 - 1.0)
    /// This is explicitly managed and resets when index changes.
    /// Decoupled from flow state to prevent timing issues.
    private(set) var segmentProgress: CGFloat = 0
    
    /// Pending auto-advance direction (triggers VerticalPager animation)
    var pendingAutoAdvance: NavigationDirection? = nil
    
    /// Whether navigation is temporarily locked (during score display)
    private(set) var isNavigationLocked: Bool = false
    
    // MARK: - Browse Queue State (Default Mode)
    
    /// Affirmations for browse mode (batch of 30).
    /// This queue persists across session entries/exits.
    private(set) var browseAffirmations: [Affirmation] = []
    
    /// Current index in browse queue.
    /// Preserved when entering a session, restored when exiting.
    private(set) var browseIndex: Int = 0
    
    /// Total affirmations consumed from browse batch.
    /// Used for triggering batch refresh.
    private(set) var browseBatchConsumed: Int = 0
    
    /// Whether a browse batch refresh is in progress
    private var isBrowseBatchRefreshInProgress: Bool = false
    
    /// IDs of affirmations already viewed in current browse batch.
    /// Used to track unique views - only new views increment consumption.
    private var viewedBrowseAffirmationIds: Set<UUID> = []
    
    // MARK: - Session Queue State (Non-Default Modes)
    
    /// Affirmations for current session (10 items).
    /// Generated fresh on session start, cleared on exit.
    private(set) var sessionAffirmations: [Affirmation] = []
    
    /// Current index in session queue (0-9).
    /// This is the POSITION in the queue, not completion count.
    private(set) var sessionIndex: Int = 0
    
    /// Number of unique affirmations practiced in current session.
    /// Computed from `sessionResults` which tracks unique practiced affirmations.
    /// This is the COMPLETION COUNT, not position.
    var sessionProgress: Int {
        sessionResults.count
    }
    
    // MARK: - Session Summary State
    
    /// Whether the results summary is being shown
    private(set) var isShowingSummary: Bool = false
    
    /// Results collected during the session for summary display
    private(set) var sessionResults: [SessionAffirmationResult] = []
    
    /// The mode used for the session (for retry functionality)
    private var sessionMode: SessionMode = .readOnly
    
    /// Timestamp when session started
    private var sessionStartTime: Date = Date()
    
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
    private var activeFlowTask: Task<Void, Never>? = nil
    
    /// Flow generation counter - incremented on each mode/index change.
    /// Progress updates only apply if they match the current generation.
    /// This prevents stale updates from cancelled tasks.
    private var flowGeneration: Int = 0
    
    /// Last user interaction timestamp
    private var lastInteractionTime: Date = Date()
    
    /// Categories used for loading (needed for batch refresh and session generation)
    private var loadedCategories: [String] = []
    
    // MARK: - Real Services State
    
    /// System TTS service backing storage
    @ObservationIgnored
    private var _systemTTS: SystemTTSService?
    
    /// System TTS service for speech synthesis (lazily created)
    private var systemTTS: SystemTTSService {
        if let existing = _systemTTS {
            return existing
        }
        let service = SystemTTSService()
        service.speechRate = 0.48  // Slightly slower for clear affirmation delivery
        service.pitchMultiplier = 1.0
        _systemTTS = service
        return service
    }
    
    /// Speech capture service backing storage
    @ObservationIgnored
    private var _speechCaptureService: SpeechCaptureService?
    
    /// Speech capture service for recognition (lazily created)
    private var speechCaptureService: SpeechCaptureService {
        if let existing = _speechCaptureService {
            return existing
        }
        let service = SpeechCaptureService()
        _speechCaptureService = service
        return service
    }
    
    /// Active listening task
    private var listeningTask: Task<Void, Never>?
    
    /// Listening start time for timeout tracking
    private var listeningStartTime: Date?
    
    /// Whether the timeout alert is showing
    private(set) var isShowingTimeoutAlert: Bool = false
    
    /// Whether the permission denied alert is showing
    private(set) var isShowingPermissionAlert: Bool = false
    
    /// Type of permission that was denied (for alert display)
    private(set) var deniedPermissionType: PermissionType = .microphone
    
    /// User's calibration data (loaded from profile)
    private var calibrationData: CalibrationData?
    
    // MARK: - Dependencies
    
    /// Service dependencies (injected)
    private let dependencies: DependencyContainer
    
    /// Repository for affirmation data access (set during load)
    private var repository: (any AffirmationRepositoryProtocol)?
    
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
    /// Routes to session queue when in session, browse queue otherwise.
    var affirmations: [Affirmation] {
        isSessionActive ? sessionAffirmations : browseAffirmations
    }
    
    /// The current index in the active queue.
    /// Routes to session index when in session, browse index otherwise.
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
            // In session, limited to session size
            return sessionIndex < Constants.Session.sessionSize - 1
        }
        // In browse mode, limited to batch
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
    
    /// Session progress text showing unique affirmations practiced (e.g., "3 / 10")
    /// Note: This shows COMPLETION count, not current position.
    var sessionProgressText: String {
        "\(sessionProgress) / \(Constants.Session.sessionSize)"
    }
    
    // MARK: - Computed Properties (Dock Display)
    
    /// Total count for dock progress bar display.
    /// Returns session size (10) for active modes, batch count for browse.
    var displayTotalCount: Int {
        if isSessionActive {
            return Constants.Session.sessionSize
        }
        return browseAffirmations.count
    }
    
    /// Current index for dock progress bar display.
    /// Returns sessionIndex (POSITION) for active modes, browseIndex for browse.
    /// This is the user's current viewing position, NOT completion count.
    var displayCurrentIndex: Int {
        if isSessionActive {
            return sessionIndex
        }
        return browseIndex
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
}

// MARK: - Event Handling

extension PracticeStore {
    
    /// Single entry point for all state changes.
    ///
    /// All user interactions and system events come through here.
    /// This makes state changes predictable and traceable.
    ///
    /// - Parameter event: The event to process
    func send(_ event: PracticeEvent) {
        #if DEBUG
        print("[LOG] PracticeStore.send: \(event)")
        #endif
        
        if event.isUserInteraction {
            lastInteractionTime = Date()
        }
        
        switch event {
            
        // MARK: Mode Selection
        case .selectMode(let mode):
            handleSelectMode(mode)
            
        case .selectBinaural(let preset):
            handleSelectBinaural(preset)
            
        case .toggleModeSelector:
            withAnimation(AppTheme.Animation.standard) {
                isModeSelectorExpanded.toggle()
                if isModeSelectorExpanded {
                    isBinauralSelectorExpanded = false
                }
            }
            
        case .toggleBinauralSelector:
            withAnimation(AppTheme.Animation.standard) {
                isBinauralSelectorExpanded.toggle()
                if isBinauralSelectorExpanded {
                    isModeSelectorExpanded = false
                }
            }
            
        case .closeSelectors:
            withAnimation(AppTheme.Animation.standard) {
                isModeSelectorExpanded = false
                isBinauralSelectorExpanded = false
            }
            
        // MARK: Navigation
        case .userNavigated(let direction):
            handleUserNavigated(direction)
            
        case .navigateViaButton(let direction):
            handleNavigateViaButton(direction)
            
        case .autoAdvanceCompleted:
            handleAutoAdvanceCompleted()
            
        case .goToIndex(let index):
            handleGoToIndex(index)
            
        // MARK: Session Control
        case .exitSession:
            handleExitSession()
            
        case .startFlow:
            startFlowForCurrentAffirmation()
            
        case .pauseFlow:
            cancelCurrentActivity()
            
        case .resumeFlow:
            if isSessionActive {
                startFlowForCurrentAffirmation()
            }
            
        // MARK: Session Summary Events
        case .dismissSummary:
            handleDismissSummary()
            
        case .retrySession:
            handleRetrySession()
            
        case .toggleFavoriteInSummary(let affirmationId):
            handleToggleFavoriteInSummary(affirmationId: affirmationId)
            
        // MARK: TTS Events
        case .ttsStarted:
            break
            
        case .ttsProgress(let progress):
            updateTTSProgress(progress)
            
        case .ttsCompleted:
            handleTTSCompleted()
            
        case .ttsFailed(let error):
            self.error = error
            resetToIdle()
            
        case .ttsCancelled:
            resetToIdle()
            
        // MARK: Listening Events
        case .listeningStarted:
            break
            
        case .listeningUpdate(let context):
            updateListeningContext(context)
            
        case .listeningCompleted(let text, let duration):
            handleListeningCompleted(text: text, duration: duration)
            
        case .listeningFailed(let error):
            // For route-change interruptions, show the timeout alert (has Retry option)
            // instead of a generic error, which provides a better UX
            if case .speechRecognitionError(let msg) = error,
               msg.contains("route") || msg.contains("Audio") {
                #if DEBUG
                print("[LOG] PracticeStore: Treating route change error as timeout")
                #endif
                handleListeningTimedOut()
            } else {
                self.error = error
                resetToIdle()
            }
            
        case .listeningCancelled:
            resetToIdle()
            
        // MARK: Timeout Events
        case .listeningTimedOut:
            handleListeningTimedOut()
            
        case .retryListening:
            handleRetryListening()
            
        case .skipAffirmation:
            handleSkipAffirmation()
            
        // MARK: Permission Events
        case .permissionDenied(let type):
            handlePermissionDenied(type)
            
        case .openSettings:
            handleOpenSettings()
            
        case .continueWithoutPermission:
            handleContinueWithoutPermission()
            
        // MARK: Score Events
        case .analysisStarted:
            transitionToAnalyzing()
            
        case .scoreCalculated(let result):
            handleScoreCalculated(result)
            
        case .scoreFailed(let error):
            self.error = error
            resetToIdle()
            
        case .scoreDisplayCompleted:
            handleScoreDisplayCompleted()
            
        // MARK: Affirmation Events
        case .toggleFavorite:
            handleToggleFavorite()
            
        case .shareAffirmation:
            handleShareAffirmation()
            
        case .recordView:
            recordAffirmationView()
            
        // MARK: UI Events
        case .dismissError:
            error = nil
            
        case .viewAppeared:
            break
            
        case .viewDisappeared:
            cancelCurrentActivity()
            
        // MARK: Data Events
        case .affirmationsLoaded(let newAffirmations):
            browseAffirmations = newAffirmations
            browseIndex = 0
            browseBatchConsumed = 0
            viewedBrowseAffirmationIds = []
            if let firstAffirmation = newAffirmations.first {
                viewedBrowseAffirmationIds.insert(firstAffirmation.id)
                browseBatchConsumed = 1
            }
            
        case .affirmationsLoadFailed(let error):
            self.error = error
            browseAffirmations = Affirmation.samples
            browseIndex = 0
            viewedBrowseAffirmationIds = []
            if let firstSample = Affirmation.samples.first {
                viewedBrowseAffirmationIds.insert(firstSample.id)
                browseBatchConsumed = 1
            }
        }
    }
}

// MARK: - Event Handlers (Mode Selection)

private extension PracticeStore {
    
    func handleSelectMode(_ mode: SessionMode) {
        cancelCurrentActivity()
        flowGeneration += 1
        segmentProgress = 0
        
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        if mode == .readOnly {
            withAnimation(AppTheme.Animation.standard) {
                flow = .home
            }
            sessionAffirmations = []
            sessionIndex = 0
            sessionResults = []
        } else {
            generateSessionQueue(forMode: mode)
        }
    }
    
    func generateSessionQueue(forMode mode: SessionMode) {
        guard let repo = repository else {
            #if DEBUG
            print("[WARN] PracticeStore: No repository for session queue generation")
            #endif
            sessionAffirmations = Array(browseAffirmations.prefix(Constants.Session.sessionSize))
            startSession(mode: mode)
            return
        }
        
        let recentlyBrowsedIds = Set(browseAffirmations.prefix(20).map { $0.id })
        
        do {
            let freshQueue = try repo.fetchSessionQueue(
                forCategories: loadedCategories,
                excluding: recentlyBrowsedIds,
                limit: Constants.Session.sessionSize
            )
            
            if freshQueue.isEmpty {
                sessionAffirmations = Array(browseAffirmations.prefix(Constants.Session.sessionSize))
            } else {
                sessionAffirmations = freshQueue
            }
            
            #if DEBUG
            print("[OK] PracticeStore: Generated session queue with \(sessionAffirmations.count) fresh affirmations")
            #endif
            
        } catch {
            #if DEBUG
            print("[WARN] PracticeStore: Session queue generation failed: \(error)")
            #endif
            sessionAffirmations = Array(browseAffirmations.prefix(Constants.Session.sessionSize))
        }
        
        startSession(mode: mode)
    }
    
    func startSession(mode: SessionMode) {
        sessionIndex = 0
        sessionResults = []
        sessionMode = mode
        sessionStartTime = Date()
        
        withAnimation(AppTheme.Animation.standard) {
            switch mode {
            case .readOnly:
                flow = .home
            case .readAloud:
                flow = .readAloud(.idle)
            case .readThenSpeak:
                flow = .readAndSpeak(.idle)
            case .speakOnly:
                flow = .speakOnly(.idle)
            }
        }
        
        startFlowForCurrentAffirmation()
    }
    
    func handleSelectBinaural(_ preset: BinauralPreset) {
        withAnimation(AppTheme.Animation.standard) {
            binauralPreset = preset
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        Task {
            do {
                if preset == .off {
                    await dependencies.audioService.stopBinauralBeats()
                } else {
                    try await dependencies.audioService.startBinauralBeats(preset: preset)
                }
            } catch {
                self.error = .audioSessionError(error.localizedDescription)
            }
        }
    }
}

// MARK: - Event Handlers (Navigation)

private extension PracticeStore {
    
    func handleUserNavigated(_ direction: NavigationDirection) {
        cancelCurrentActivity()
        
        if isSessionActive {
            recordEngagement(.view)
            startFlowForCurrentAffirmation()
        } else {
            trackUniqueBrowseView()
            recordEngagement(.view)
        }
    }
    
    func handleNavigateViaButton(_ direction: NavigationDirection) {
        switch direction {
        case .next:
            guard canGoNext else { return }
        case .previous:
            guard canGoPrevious else { return }
        }
        
        cancelCurrentActivity()
        resetToIdle()
        isNavigationLocked = false
        
        pendingAutoAdvance = direction
    }
    
    func handleAutoAdvanceCompleted() {
        pendingAutoAdvance = nil
        
        if isSessionActive {
            recordEngagement(.view)
            startFlowForCurrentAffirmation()
        } else {
            trackUniqueBrowseView()
            recordEngagement(.view)
        }
    }
    
    func handleGoToIndex(_ index: Int) {
        guard affirmations.indices.contains(index) else { return }
        guard !shouldBlockNavigation else { return }
        
        cancelCurrentActivity()
        
        if isSessionActive {
            sessionIndex = index
        } else {
            browseIndex = index
        }
        
        resetToIdle()
        recordEngagement(.view)
        
        if isSessionActive {
            startFlowForCurrentAffirmation()
        } else {
            trackUniqueBrowseView()
        }
    }
    
    func handleExitSession() {
        cancelCurrentActivity()
        resetToIdle()
        
        isShowingTimeoutAlert = false
        isShowingPermissionAlert = false
        
        sessionAffirmations = []
        sessionIndex = 0
        sessionResults = []
        
        withAnimation(AppTheme.Animation.standard) {
            flow = .home
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
}

// MARK: - Event Handlers (TTS)

private extension PracticeStore {
    
    func updateTTSProgress(_ progress: Double) {
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .readAloud:
                flow = .readAloud(.playing(progress: progress))
                segmentProgress = CGFloat(progress)
            case .readAndSpeak:
                flow = .readAndSpeak(.ttsPlaying(progress: progress))
                segmentProgress = CGFloat(progress) * 0.25
            default:
                break
            }
        }
    }
    
    func handleTTSCompleted() {
        switch flow {
        case .readAloud:
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAloud(.complete)
                segmentProgress = 1.0
            }
            scheduleAutoAdvance()
            
        default:
            break
        }
    }
}

// MARK: - Event Handlers (Listening)

private extension PracticeStore {
    
    func updateListeningContext(_ context: ListeningContext) {
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .readAndSpeak:
                flow = .readAndSpeak(.listening(context))
                segmentProgress = 0.65
            case .speakOnly:
                flow = .speakOnly(.listening(context))
                segmentProgress = 0.5
            default:
                break
            }
        }
    }
    
    func handleListeningCompleted(text: String, duration: TimeInterval) {
        // CRITICAL: Guard against empty or whitespace-only transcription
        // This can happen when route changes (e.g., AirPods connect) interrupt capture
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            #if DEBUG
            print("[WARN] PracticeStore: Empty transcription received, showing timeout alert")
            #endif
            handleListeningTimedOut()
            return
        }
        
        transitionToAnalyzing()
        
        Task {
            try? await Task.sleep(for: PracticeTiming.analysisDuration)
            
            guard !Task.isCancelled else { return }
            
            let score: Double
            let components: ScoreComponents
            
            if let record = lastResonanceRecord {
                score = Double(record.overallScore)
                components = ScoreComponents(
                    textAccuracy: Double(record.textAccuracy),
                    vocalEnergy: Double(record.vocalEnergy),
                    pitchStability: Double(record.pitchStability)
                )
            } else {
                // Fallback: compute basic text accuracy score
                // Guard: ensure we have valid expected text
                guard let expectedText = currentAffirmation?.text, !expectedText.isEmpty else {
                    #if DEBUG
                    print("[ERROR] PracticeStore: No affirmation text for score calculation")
                    #endif
                    await MainActor.run {
                        handleListeningTimedOut()
                    }
                    return
                }
                
                let accuracy = TextAccuracyCalculator.calculate(
                    expected: expectedText,
                    recognized: trimmedText
                )
                score = Double(accuracy)
                components = ScoreComponents(
                    textAccuracy: Double(accuracy),
                    vocalEnergy: 0.7,
                    pitchStability: 0.7
                )
                
                #if DEBUG
                print("[WARN] PracticeStore: Using fallback score calculation")
                #endif
            }
            
            let result = ScoreResult(
                score: score,
                components: components,
                duration: duration,
                mode: currentMode,
                recognizedText: trimmedText
            )
            
            await MainActor.run {
                send(.scoreCalculated(result))
            }
        }
    }
    
    func transitionToAnalyzing() {
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .readAndSpeak:
                flow = .readAndSpeak(.analyzing)
                segmentProgress = 0.85
            case .speakOnly:
                flow = .speakOnly(.analyzing)
                segmentProgress = 0.8
            default:
                break
            }
        }
    }
}

// MARK: - Event Handlers (Timeout & Permissions)

private extension PracticeStore {
    
    func handleListeningTimedOut() {
        cancelCurrentActivity()
        
        withAnimation(AppTheme.Animation.standard) {
            isShowingTimeoutAlert = true
        }
        
        #if DEBUG
        print("[LOG] PracticeStore: Listening timed out, showing alert")
        #endif
    }
    
    func handleRetryListening() {
        isShowingTimeoutAlert = false
        listeningStartTime = nil
        
        startFlowForCurrentAffirmation()
        
        #if DEBUG
        print("[LOG] PracticeStore: Retrying listening for current affirmation")
        #endif
    }
    
    func handleSkipAffirmation() {
        isShowingTimeoutAlert = false
        listeningStartTime = nil
        
        if let affirmation = currentAffirmation {
            if !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) {
                let skippedResult = SessionAffirmationResult(
                    affirmation: affirmation,
                    isFromScoringMode: sessionMode.producesResonanceScore
                )
                sessionResults.append(skippedResult)
            }
            
            affirmation.skipCount += 1
        }
        
        if canGoNext {
            if isSessionActive {
                sessionIndex += 1
            } else {
                browseIndex += 1
            }
            segmentProgress = 0
            startFlowForCurrentAffirmation()
        } else if isSessionActive && sessionIndex >= Constants.Session.sessionSize - 1 {
            showSessionSummary()
        } else {
            resetToIdle()
        }
        
        #if DEBUG
        print("[LOG] PracticeStore: Skipped affirmation, moving to next")
        #endif
    }
    
    func handlePermissionDenied(_ type: PermissionType) {
        cancelCurrentActivity()
        deniedPermissionType = type
        
        withAnimation(AppTheme.Animation.standard) {
            isShowingPermissionAlert = true
        }
        
        #if DEBUG
        print("[LOG] PracticeStore: Permission denied - \(type)")
        #endif
    }
    
    func handleOpenSettings() {
        isShowingPermissionAlert = false
        
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    func handleContinueWithoutPermission() {
        isShowingPermissionAlert = false
        
        withAnimation(AppTheme.Animation.standard) {
            flow = .home
            sessionMode = .readOnly
        }
    }
}

// MARK: - Event Handlers (Score)

private extension PracticeStore {
    
    func handleScoreCalculated(_ result: ScoreResult) {
        lastResonanceRecord = result.toRecord()
        
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            affirmation.resonanceScores.append(result.toRecord())
            
            if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
                sessionResults[index].score = result.percentScore
            }
        }
        
        recordEngagement(.speak)
        recordResonance(result.toRecord())
        
        withAnimation(AppTheme.Animation.standard) {
            switch flow {
            case .readAndSpeak:
                flow = .readAndSpeak(.showingScore(result))
            case .speakOnly:
                flow = .speakOnly(.showingScore(result))
            default:
                break
            }
            segmentProgress = 1.0
        }
        
        lockNavigation()
        
        Task {
            try? await Task.sleep(for: PracticeTiming.scoreDisplayDuration)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                send(.scoreDisplayCompleted)
            }
        }
    }
    
    func handleScoreDisplayCompleted() {
        if isSessionActive && sessionIndex >= Constants.Session.sessionSize - 1 {
            #if DEBUG
            print("[LOG] PracticeStore: Session complete at last index \(sessionIndex)")
            #endif
            
            showSessionSummary()
            return
        }
        
        if canGoNext {
            pendingAutoAdvance = .next
        }
    }
}

// MARK: - Event Handlers (Affirmation)

private extension PracticeStore {
    
    func handleToggleFavorite() {
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
            sessionResults[index].isFavorited = affirmation.isFavorited
        }
        
        if let repository = repository {
            do {
                try repository.toggleFavorite(affirmationId: affirmation.id)
            } catch {
                #if DEBUG
                print("[WARN] PracticeStore: Failed to persist favorite toggle: \(error.localizedDescription)")
                #endif
            }
        }
        
        HapticFeedback.selection()
    }
    
    func handleShareAffirmation() {
        recordEngagement(.share)
    }
    
    func recordAffirmationView() {
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.hasBeenSeen = true
        affirmation.viewCount += 1
        affirmation.lastInteractedAt = Date()
    }
}

// MARK: - Session & Batch Tracking

private extension PracticeStore {
    
    func trackUniqueBrowseView() {
        guard let affirmation = currentAffirmation else { return }
        
        if !viewedBrowseAffirmationIds.contains(affirmation.id) {
            viewedBrowseAffirmationIds.insert(affirmation.id)
            browseBatchConsumed += 1
            
            #if DEBUG
            print("[LOG] Browse batch consumed: \(browseBatchConsumed)/\(Constants.Session.batchSize) (unique views: \(viewedBrowseAffirmationIds.count))")
            #endif
            
            checkBrowseBatchRefresh()
        }
    }
    
    func recordAffirmationForSession() {
        guard let affirmation = currentAffirmation else { return }
        guard !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) else { return }
        
        let isFromScoringMode = (sessionMode == .readThenSpeak || sessionMode == .speakOnly)
        let result = SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: isFromScoringMode)
        sessionResults.append(result)
        
        #if DEBUG
        print("[LOG] PracticeStore: Recorded affirmation for session: \(affirmation.text.prefix(30))...")
        #endif
    }
    
    func checkBrowseBatchRefresh() {
        guard browseBatchConsumed >= Constants.Session.regenerationTriggerIndex else { return }
        guard !isBrowseBatchRefreshInProgress else { return }
        guard let repo = repository else { return }
        guard !loadedCategories.isEmpty else { return }
        
        isBrowseBatchRefreshInProgress = true
        
        #if DEBUG
        print("[LOG] PracticeStore: Triggering browse batch refresh...")
        #endif
        
        let categories = loadedCategories
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            do {
                let newAffirmations = try repo.fetchQueue(
                    forCategories: categories,
                    limit: Constants.Session.batchSize
                )
                
                self.appendToBrowseQueue(newAffirmations)
                self.isBrowseBatchRefreshInProgress = false
                
                #if DEBUG
                print("[OK] PracticeStore: Browse batch refresh complete. Added \(newAffirmations.count) affirmations")
                #endif
            } catch {
                self.isBrowseBatchRefreshInProgress = false
                
                #if DEBUG
                print("[LOG] PracticeStore: Browse batch refresh failed: \(error)")
                #endif
            }
        }
    }
    
    func appendToBrowseQueue(_ newAffirmations: [Affirmation]) {
        let existingIds = Set(browseAffirmations.map { $0.id })
        let uniqueNew = newAffirmations.filter { !existingIds.contains($0.id) }
        
        browseAffirmations.append(contentsOf: uniqueNew)
        browseBatchConsumed = 0
    }
}

// MARK: - Session Summary

private extension PracticeStore {
    
    func showSessionSummary() {
        cancelCurrentActivity()
        
        Task {
            try? await Task.sleep(for: PracticeTiming.sessionCompletePause)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                isNavigationLocked = true
                
                withAnimation(.easeInOut(duration: PracticeTiming.summaryTransitionDuration)) {
                    isShowingSummary = true
                }
                
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryTransitionDuration * 1000)))
                    await MainActor.run {
                        isNavigationLocked = false
                    }
                }
                
                HapticFeedback.notification(.success)
            }
        }
    }
    
    func handleDismissSummary() {
        sessionResults = []
        sessionAffirmations = []
        sessionIndex = 0
        
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            isShowingSummary = false
        }
        
        flow = .home
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
    }
    
    func handleRetrySession() {
        sessionIndex = 0
        sessionResults = []
        segmentProgress = 0
        
        switch sessionMode {
        case .readAloud:
            flow = .readAloud(.idle)
        case .readThenSpeak:
            flow = .readAndSpeak(.idle)
        case .speakOnly:
            flow = .speakOnly(.idle)
        default:
            flow = .home
        }
        
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            isShowingSummary = false
        }
        
        Task {
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            await MainActor.run {
                startFlowForCurrentAffirmation()
            }
        }
    }
    
    func handleToggleFavoriteInSummary(affirmationId: UUID) {
        let affirmation = sessionAffirmations.first { $0.id == affirmationId }
            ?? browseAffirmations.first { $0.id == affirmationId }
        
        guard let affirmation = affirmation else { return }
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmationId }) {
            sessionResults[index].isFavorited = affirmation.isFavorited
        }
        
        if let repository = repository {
            do {
                try repository.toggleFavorite(affirmationId: affirmationId)
            } catch {
                #if DEBUG
                print("[WARN] PracticeStore: Failed to persist favorite toggle: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

// MARK: - Flow Execution

private extension PracticeStore {
    
    func startFlowForCurrentAffirmation() {
        guard currentAffirmation != nil else { return }
        
        activeFlowTask?.cancel()
        flowGeneration += 1
        
        recordAffirmationView()
        recordEngagement(.view)
        
        if sessionMode != .readOnly {
            recordAffirmationForSession()
        }
        
        let generation = flowGeneration
        
        activeFlowTask = Task {
            await executeCurrentFlow(generation: generation)
        }
    }
    
    func executeCurrentFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        try? await Task.sleep(for: PracticeTiming.flowStartDelay)
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        switch flow {
        case .home:
            break
            
        case .readAloud:
            await executeReadAloudFlow(generation: generation)
            
        case .readAndSpeak:
            await executeReadAndSpeakFlow(generation: generation)
            
        case .speakOnly:
            await executeSpeakOnlyFlow(generation: generation)
        }
    }
    
    func executeReadAloudFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmationData = await MainActor.run(body: {
            guard let affirmation = currentAffirmation else { return nil as (text: String, speechDuration: TimeInterval)? }
            return (text: affirmation.text, speechDuration: affirmation.speechDuration)
        }) else { return }
        
        let affirmationText = affirmationData.text
        let speechDuration = affirmationData.speechDuration
        
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAloud(.playing(progress: 0))
            }
        }
        
        do {
            let estimatedDuration = max(speechDuration, PracticeTiming.ttsMininumHoldDuration)
            
            let progressTask = Task {
                let startTime = Date()
                while !Task.isCancelled && generation == flowGeneration {
                    try? await Task.sleep(for: .milliseconds(50))
                    let elapsed = Date().timeIntervalSince(startTime)
                    let progress = min(elapsed / estimatedDuration, 0.95)
                    
                    await MainActor.run {
                        guard generation == flowGeneration else { return }
                        send(.ttsProgress(progress))
                    }
                    
                    if elapsed >= estimatedDuration * 0.95 {
                        break
                    }
                }
            }
            
            try await systemTTS.speak(affirmationText)
            progressTask.cancel()
            
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            
            await MainActor.run {
                guard generation == flowGeneration else { return }
                segmentProgress = 1.0
                send(.ttsCompleted)
            }
            
        } catch {
            #if DEBUG
            print("[ERROR] PracticeStore: TTS failed - \(error.localizedDescription)")
            #endif
            
            await MainActor.run {
                guard generation == flowGeneration else { return }
                send(.ttsFailed(.ttsError(error.localizedDescription)))
            }
        }
    }
    
    func executeReadAndSpeakFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmationData = await MainActor.run(body: {
            guard let affirmation = currentAffirmation else { return nil as (text: String, speechDuration: TimeInterval)? }
            return (text: affirmation.text, speechDuration: affirmation.speechDuration)
        }) else { return }
        
        let affirmationText = affirmationData.text
        let speechDuration = affirmationData.speechDuration
        
        // Check permissions first
        let speechService = dependencies.speechAnalysisService
        let hasMicPermission = await speechService.requestMicrophonePermission()
        let hasSpeechPermission = await speechService.requestSpeechRecognitionPermission()
        
        guard hasMicPermission && hasSpeechPermission else {
            await MainActor.run {
                if !hasMicPermission && !hasSpeechPermission {
                    send(.permissionDenied(.both))
                } else if !hasMicPermission {
                    send(.permissionDenied(.microphone))
                } else {
                    send(.permissionDenied(.speechRecognition))
                }
            }
            return
        }
        
        // Phase 1: TTS Playback
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAndSpeak(.ttsPlaying(progress: 0))
            }
        }
        
        do {
            let estimatedDuration = max(speechDuration, PracticeTiming.ttsMininumHoldDuration)
            
            let progressTask = Task {
                let startTime = Date()
                while !Task.isCancelled && generation == flowGeneration {
                    try? await Task.sleep(for: .milliseconds(50))
                    let elapsed = Date().timeIntervalSince(startTime)
                    let progress = min(elapsed / estimatedDuration, 0.45)
                    
                    await MainActor.run {
                        guard generation == flowGeneration else { return }
                        send(.ttsProgress(progress))
                    }
                    
                    if elapsed >= estimatedDuration * 0.95 {
                        break
                    }
                }
            }
            
            try await systemTTS.speak(affirmationText)
            progressTask.cancel()
            
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            
        } catch {
            #if DEBUG
            print("[ERROR] PracticeStore: TTS failed in read-and-speak - \(error.localizedDescription)")
            #endif
            await MainActor.run {
                send(.ttsFailed(.ttsError(error.localizedDescription)))
            }
            return
        }
        
        // Phase 2: Wait for user
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAndSpeak(.waitingForUser)
                segmentProgress = 0.5
            }
        }
        
        try? await Task.sleep(for: PracticeTiming.waitForUserDuration)
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Phase 3: Listening
        await MainActor.run {
            guard generation == flowGeneration else { return }
            listeningStartTime = Date()
            
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAndSpeak(.listening(.initial))
            }
        }
        
        await executeListeningPhase(
            generation: generation,
            affirmationText: affirmationText
        )
    }
    
    func executeSpeakOnlyFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        guard let affirmationText = await MainActor.run(body: {
            currentAffirmation?.text
        }) else { return }
        
        // Check permissions first
        let speechService = dependencies.speechAnalysisService
        let hasMicPermission = await speechService.requestMicrophonePermission()
        let hasSpeechPermission = await speechService.requestSpeechRecognitionPermission()
        
        guard hasMicPermission && hasSpeechPermission else {
            await MainActor.run {
                if !hasMicPermission && !hasSpeechPermission {
                    send(.permissionDenied(.both))
                } else if !hasMicPermission {
                    send(.permissionDenied(.microphone))
                } else {
                    send(.permissionDenied(.speechRecognition))
                }
            }
            return
        }
        
        // Initialize listening state
        await MainActor.run {
            guard generation == flowGeneration else { return }
            listeningStartTime = Date()
            
            withAnimation(AppTheme.Animation.quick) {
                flow = .speakOnly(.listening(.initial))
            }
        }
        
        await executeListeningPhase(
            generation: generation,
            affirmationText: affirmationText
        )
    }
    
    // MARK: - Simplified Listening Phase
    
    /// Executes the listening phase using SpeechCaptureService.
    /// Completion is based on silence detection or maximum duration.
    func executeListeningPhase(
        generation: Int,
        affirmationText: String
    ) async {
        let startTime = Date()
        var lastTranscription = ""
        var lastAudioLevel: Double = 0
        var hasStarted = false
        
        #if DEBUG
        print("[LOG] PracticeStore: Setting up listening for: \"\(affirmationText.prefix(40))...\"")
        #endif
        
        // Set up stream consumer BEFORE starting capture
        listeningTask = Task { [weak self] in
            guard let self = self else { return }
            
            let stream = self.speechCaptureService.captureStream
            
            try? await Task.sleep(for: .milliseconds(50))
            
            #if DEBUG
            print("[LOG] PracticeStore: Stream consumer ready, starting capture...")
            #endif
            
            // Start capture
            do {
                try await self.speechCaptureService.startCapture()
            } catch {
                #if DEBUG
                print("[ERROR] PracticeStore: Failed to start capture - \(error)")
                #endif
                
                await MainActor.run {
                    guard generation == self.flowGeneration else { return }
                    
                    if let captureError = error as? SpeechCaptureService.CaptureError {
                        switch captureError {
                        case .microphonePermissionDenied:
                            self.send(.permissionDenied(.microphone))
                        case .speechRecognitionPermissionDenied:
                            self.send(.permissionDenied(.speechRecognition))
                        default:
                            self.send(.listeningFailed(.speechRecognitionError(String(describing: captureError))))
                        }
                    } else {
                        self.send(.listeningFailed(.speechRecognitionError(error.localizedDescription)))
                    }
                }
                return
            }
            
            await MainActor.run {
                guard generation == self.flowGeneration else { return }
                self.send(.listeningStarted)
                hasStarted = true
            }
            
            #if DEBUG
            print("[LOG] PracticeStore: Capture started, consuming stream...")
            #endif
            
            // Process capture stream
            // CRITICAL: Use labeled break to exit the for-await loop, not just the switch
            captureLoop: for await update in stream {
                guard !Task.isCancelled else { break captureLoop }
                guard generation == self.flowGeneration else { break captureLoop }
                
                switch update {
                case .transcription(let text, let isFinal):
                    #if DEBUG
                    print("[LOG] PracticeStore: Transcription: \"\(text.prefix(50))...\" (final: \(isFinal))")
                    #endif
                    
                    lastTranscription = text
                    
                    // Complete on final transcription with content
                    if isFinal && !text.isEmpty {
                        #if DEBUG
                        print("[LOG] PracticeStore: Final transcription received, completing")
                        #endif
                        break captureLoop  // Exit the for-await loop
                    }
                    
                case .audioLevel(let level):
                    lastAudioLevel = Double(level)
                    
                    let elapsed = Date().timeIntervalSince(startTime)
                    let context = ListeningContext(
                        elapsed: elapsed,
                        audioLevel: lastAudioLevel,
                        recognizedText: lastTranscription
                    )
                    
                    await MainActor.run {
                        guard generation == self.flowGeneration else { return }
                        self.send(.listeningUpdate(context))
                    }
                    
                case .silenceDetected(let duration):
                    #if DEBUG
                    print("[LOG] PracticeStore: Silence detected (\(String(format: "%.1f", duration))s)")
                    #endif
                    
                    // Complete on silence if we have some transcription
                    let elapsed = Date().timeIntervalSince(startTime)
                    if !lastTranscription.isEmpty && elapsed > 2.0 {
                        #if DEBUG
                        print("[LOG] PracticeStore: Completing on silence with transcription")
                        #endif
                        break captureLoop  // Exit the for-await loop
                    }
                    
                case .error(let captureError):
                    #if DEBUG
                    print("[ERROR] PracticeStore: Capture error - \(captureError)")
                    #endif
                    
                    await MainActor.run {
                        guard generation == self.flowGeneration else { return }
                        
                        switch captureError {
                        case .microphonePermissionDenied:
                            self.send(.permissionDenied(.microphone))
                        case .speechRecognitionPermissionDenied:
                            self.send(.permissionDenied(.speechRecognition))
                        default:
                            self.send(.listeningFailed(.speechRecognitionError(String(describing: captureError))))
                        }
                    }
                    return
                    
                case .started:
                    #if DEBUG
                    print("[LOG] PracticeStore: Capture service started")
                    #endif
                    
                case .stopped:
                    #if DEBUG
                    print("[LOG] PracticeStore: Capture service stopped")
                    #endif
                    break captureLoop  // Exit on stop as well
                }
            }
        }
        
        // Wait for listening with timeout
        let maxDuration = PracticeTiming.maximumListeningDuration
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.listeningTask?.value
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(maxDuration))
            }
            
            await group.next()
            group.cancelAll()
        }
        
        // Clean up
        listeningTask?.cancel()
        listeningTask = nil
        
        // Stop capture and get final transcription
        let finalText = speechCaptureService.stopCapture()
        if !finalText.isEmpty {
            lastTranscription = finalText
        }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        guard hasStarted else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Check for timeout with no transcription
        if lastTranscription.isEmpty && duration >= maxDuration - 1 {
            #if DEBUG
            print("[LOG] PracticeStore: Listening timed out with no transcription")
            #endif
            send(.listeningTimedOut)
            return
        }
        
        #if DEBUG
        print("[LOG] PracticeStore: Listening complete - Duration: \(String(format: "%.1f", duration))s, Text: \"\(lastTranscription.prefix(50))...\"")
        #endif
        
        send(.listeningCompleted(recognizedText: lastTranscription, duration: duration))
    }
}

// MARK: - Scheduling Helpers

private extension PracticeStore {
    
    func scheduleAutoAdvance() {
        Task {
            try? await Task.sleep(for: PracticeTiming.readAloudCompletePause)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if isSessionActive && sessionIndex >= Constants.Session.sessionSize - 1 {
                    showSessionSummary()
                    return
                }
                
                if canGoNext {
                    pendingAutoAdvance = .next
                }
            }
        }
    }
    
    func lockNavigation() {
        isNavigationLocked = true
        
        Task {
            try? await Task.sleep(for: PracticeTiming.navigationLockDuration)
            
            await MainActor.run {
                isNavigationLocked = false
            }
        }
    }
}

// MARK: - Activity Management

private extension PracticeStore {
    
    func cancelCurrentActivity() {
        activeFlowTask?.cancel()
        activeFlowTask = nil
        pendingAutoAdvance = nil
        
        listeningTask?.cancel()
        listeningTask = nil
        
        listeningStartTime = nil
        
        systemTTS.stopSpeaking()
        speechCaptureService.cancelCapture()
        
        Task {
            await dependencies.speechAnalysisService.cancelAnalysis()
        }
    }
    
    func resetToIdle() {
        segmentProgress = 0
        
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .home:
                break
            case .readAloud:
                flow = .readAloud(.idle)
            case .readAndSpeak:
                flow = .readAndSpeak(.idle)
            case .speakOnly:
                flow = .speakOnly(.idle)
            }
        }
    }
}

// MARK: - Data Loading

extension PracticeStore {
    
    func loadAffirmations(
        using repository: any AffirmationRepositoryProtocol,
        forCategories categories: [String]
    ) async {
        self.repository = repository
        self.loadedCategories = categories
        
        do {
            let queue: [Affirmation]
            
            if categories.isEmpty {
                #if DEBUG
                print("[LOG] PracticeStore: No categories selected, using samples")
                #endif
                queue = Affirmation.samples
            } else {
                queue = try repository.fetchQueue(
                    forCategories: categories,
                    limit: Constants.Session.batchSize
                )
                
                #if DEBUG
                print("[LOG] PracticeStore: Loaded \(queue.count) affirmations for browse queue")
                #endif
            }
            
            if queue.isEmpty {
                send(.affirmationsLoaded(Affirmation.samples))
            } else {
                send(.affirmationsLoaded(queue))
            }
            
        } catch {
            #if DEBUG
            print("[LOG] PracticeStore: Load failed - \(error.localizedDescription)")
            #endif
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    func loadFavorites(using repository: any AffirmationRepositoryProtocol) async {
        self.repository = repository
        
        do {
            let favorites = try repository.fetchFavorites()
            
            guard !favorites.isEmpty else {
                error = .dataLoadError("No favorites yet. Heart some affirmations first!")
                return
            }
            
            send(.affirmationsLoaded(favorites))
            send(.exitSession)
            
        } catch {
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    func updateIndex(_ newIndex: Int) {
        let queue = affirmations
        guard queue.indices.contains(newIndex) else { return }
        
        let currentIdx = isSessionActive ? sessionIndex : browseIndex
        guard newIndex != currentIdx else { return }
        
        flowGeneration += 1
        segmentProgress = 0
        
        if isSessionActive {
            resetToIdle()
            sessionIndex = newIndex
        } else {
            browseIndex = newIndex
        }
    }
}

// MARK: - Engagement Tracking

extension PracticeStore {
    
    func recordEngagement(_ type: EngagementType) {
        guard let affirmation = currentAffirmation,
              let repository = repository else { return }
        
        do {
            switch type {
            case .view:
                try repository.recordView(affirmationId: affirmation.id)
            case .speak:
                try repository.recordSpeak(affirmationId: affirmation.id)
            case .skip:
                try repository.recordSkip(affirmationId: affirmation.id)
            case .share:
                try repository.recordShare(affirmationId: affirmation.id)
            }
        } catch {
            #if DEBUG
            print("[LOG] PracticeStore: Failed to record \(type) engagement: \(error.localizedDescription)")
            #endif
        }
    }
    
    func recordResonance(_ record: ResonanceRecord) {
        guard let affirmation = currentAffirmation,
              let repository = repository else { return }
        
        do {
            try repository.addResonanceRecord(affirmationId: affirmation.id, record: record)
        } catch {
            #if DEBUG
            print("[LOG] PracticeStore: Failed to record resonance: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Engagement Type

enum EngagementType: Sendable {
    case view
    case speak
    case skip
    case share
}

// MARK: - Background State

struct BackgroundState: Equatable {
    let currentCategory: GoalCategory?
    let previousCategory: GoalCategory?
    
    init(currentCategory: GoalCategory?, previousCategory: GoalCategory?) {
        self.currentCategory = currentCategory
        self.previousCategory = previousCategory
    }
    
    static let `default` = BackgroundState(
        currentCategory: .confidence,
        previousCategory: nil
    )
}

// MARK: - Preview Support

extension PracticeStore {
    
    static var preview: PracticeStore {
        let store = PracticeStore()
        store.browseAffirmations = Affirmation.samples
        return store
    }
    
    static var previewReadAloud: PracticeStore {
        let store = PracticeStore()
        store.browseAffirmations = Affirmation.samples
        store.flow = .readAloud(.playing(progress: 0.5))
        return store
    }
    
    static var previewListening: PracticeStore {
        let store = PracticeStore()
        store.browseAffirmations = Affirmation.samples
        store.flow = .readAndSpeak(.listening(ListeningContext(
            elapsed: 1.5,
            audioLevel: 0.6,
            recognizedText: "I am confident..."
        )))
        return store
    }
    
    static var previewShowingScore: PracticeStore {
        let store = PracticeStore()
        store.browseAffirmations = Affirmation.samples
        store.flow = .readAndSpeak(.showingScore(ScoreResult(
            score: 0.85,
            components: .sample,
            duration: 2.5,
            mode: .readThenSpeak,
            recognizedText: "I am confident and capable"
        )))
        return store
    }
    
    static var previewModeSelector: PracticeStore {
        let store = PracticeStore()
        store.browseAffirmations = Affirmation.samples
        store.isModeSelectorExpanded = true
        return store
    }
}

// MARK: - Convenience Methods

extension PracticeStore {
    
    func exit() {
        send(.exitSession)
    }
    
    func toggleFavorite() {
        send(.toggleFavorite)
    }
    
    func share() {
        send(.shareAffirmation)
    }
    
    func dismissError() {
        send(.dismissError)
    }
    
    func onAppear() {
        send(.viewAppeared)
    }
    
    func onDisappear() {
        send(.viewDisappeared)
    }
    
    func continueFlow() {
        send(.autoAdvanceCompleted)
    }
    
    func navigate(_ direction: NavigationDirection) {
        send(.userNavigated(direction))
    }
}
