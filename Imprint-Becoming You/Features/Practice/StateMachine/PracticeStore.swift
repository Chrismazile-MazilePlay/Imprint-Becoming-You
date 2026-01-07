//
//  PracticeStore.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/3/26.
//

import SwiftUI
import SwiftData

// MARK: - PracticeStore

/// The single source of truth for the practice experience.
///
/// ## Architecture
/// - All state is centralized here
/// - All mutations go through `send(_ event:)`
/// - Views bind to this store and call `send()` for interactions
/// - Async effects (TTS, listening, etc.) are managed internally
///
/// ## Session vs Batch
/// - **Batch Size (30)**: Affirmations fetched from DB per batch
/// - **Session Size (10)**: Affirmations per non-default mode session
/// - **Refresh Trigger (25)**: When batchConsumed >= 25, proactively fetch next batch
///
/// ## Repository Integration
/// Uses `AffirmationRepositoryProtocol` for data access:
/// - Smart queue loading with category filtering
/// - Engagement tracking (views, speaks, resonance scores)
/// - Favorites management
///
/// ## Replaces (Deleted)
/// - `PracticeViewModel` - all state and logic
/// - `DockStateManager` - dock state is derived from `flow`
///
/// ## Usage
/// ```swift
/// @Bindable var store: PracticeStore
///
/// // Read state
/// Text(store.currentAffirmation?.text ?? "")
/// if store.flow.isListening { ListeningIndicator() }
///
/// // Send events
/// Button("Next") { store.send(.navigateViaButton(.next)) }
/// ```
@MainActor
@Observable
final class PracticeStore {
    
    // MARK: - Core State
    
    /// The current flow state (mode + phase)
    private(set) var flow: PracticeFlow = .home
    
    /// All affirmations in the current batch
    private(set) var affirmations: [Affirmation] = []
    
    /// Current affirmation index
    private(set) var currentIndex: Int = 0
    
    /// Progress through current segment (0.0 - 1.0)
    /// This is explicitly managed and resets when index changes.
    /// Decoupled from flow state to prevent timing issues.
    private(set) var segmentProgress: CGFloat = 0
    
    /// Pending auto-advance direction (triggers VerticalPager animation)
    var pendingAutoAdvance: NavigationDirection? = nil
    
    /// Whether navigation is temporarily locked (during score display)
    private(set) var isNavigationLocked: Bool = false
    
    // MARK: - Session Tracking
    
    /// Affirmations completed in current non-default session.
    /// Resets when: entering non-default mode, exiting session, session completes.
    private(set) var sessionProgress: Int = 0
    
    /// Total affirmations consumed from current batch.
    /// Increments on every navigation (any mode).
    /// Resets when new batch is loaded.
    private(set) var batchConsumed: Int = 0
    
    /// Whether a batch refresh is in progress
    private var isBatchRefreshInProgress: Bool = false
    
    /// Categories used for loading (needed for batch refresh)
    private var loadedCategories: [String] = []
    
    // MARK: - Session Summary State
    
    /// Whether the results summary is being shown
    private(set) var isShowingSummary: Bool = false
    
    /// Results collected during the session for summary display
    private(set) var sessionResults: [SessionAffirmationResult] = []
    
    /// The start index of the session (for retry functionality)
    private var sessionStartIndex: Int = 0
    
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
    
    // MARK: - Dependencies
    
    /// Service dependencies (injected)
    private let dependencies: DependencyContainer
    
    /// Repository for affirmation data access (set during load)
    private var repository: (any AffirmationRepositoryProtocol)?
    
    // MARK: - Initialization
    
    /// Creates a new practice store with dependencies
    /// - Parameter dependencies: Service container (defaults to shared)
    init(dependencies: DependencyContainer = .shared) {
        self.dependencies = dependencies
    }
    
    // MARK: - Computed Properties (Affirmations)
    
    /// The currently displayed affirmation
    var currentAffirmation: Affirmation? {
        guard affirmations.indices.contains(currentIndex) else { return nil }
        return affirmations[currentIndex]
    }
    
    /// Whether we can navigate to previous affirmation
    /// In session mode, respects session start boundary (index 0)
    var canGoPrevious: Bool {
        currentIndex > 0
    }
    
    /// Whether we can navigate to next affirmation
    /// In session mode, respects session boundary (sessionSize - 1)
    var canGoNext: Bool {
        // In active session mode, limit to session size
        if isSessionActive {
            // Session runs from index 0 to sessionSize - 1
            // Can only go next if not at last session affirmation
            return currentIndex < Constants.Session.sessionSize - 1
        }
        // In home mode, limit to full batch
        return currentIndex < affirmations.count - 1
    }
    
    /// Total count of affirmations
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
    
    /// Session progress text (e.g., "3 / 10")
    var sessionProgressText: String {
        "\(sessionProgress) / \(Constants.Session.sessionSize)"
    }
    
    // MARK: - Computed Properties (Dock Display)
    
    /// Total count for dock progress bar display.
    ///
    /// Returns session size (10) for active modes to show a fixed 10-bar progress indicator.
    /// Returns full batch count for home/browse mode.
    ///
    /// This ensures the dock always shows exactly 10 progress bars during non-default sessions,
    /// regardless of how many affirmations are loaded in the background batch.
    var displayTotalCount: Int {
        if isSessionActive {
            return Constants.Session.sessionSize
        }
        return totalCount
    }
    
    /// Current index for dock progress bar display.
    ///
    /// Returns session progress (0-9) for active modes to track position within the 10-item session.
    /// Returns current index for home/browse mode.
    ///
    /// Combined with `displayTotalCount`, this ensures progress bars accurately reflect
    /// session progress rather than position within the larger batch.
    var displayCurrentIndex: Int {
        if isSessionActive {
            return sessionProgress
        }
        return currentIndex
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
        guard currentIndex > 0 else { return nil }
        return affirmations[currentIndex - 1]
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
        // Log for debugging (can be disabled in production)
        #if DEBUG
        print("[LOG] PracticeStore.send: \(event)")
        #endif
        
        // Record interaction time for user events
        if event.isUserInteraction {
            lastInteractionTime = Date()
        }
        
        // Process the event
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
            // State already updated when flow started
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
            // State already updated when listening started
            break
            
        case .listeningUpdate(let context):
            updateListeningContext(context)
            
        case .listeningCompleted(let text, let duration):
            handleListeningCompleted(text: text, duration: duration)
            
        case .listeningFailed(let error):
            self.error = error
            resetToIdle()
            
        case .listeningCancelled:
            resetToIdle()
            
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
            // Could start binaural beats, etc.
            break
            
        case .viewDisappeared:
            cancelCurrentActivity()
            
        // MARK: Data Events
        case .affirmationsLoaded(let newAffirmations):
            affirmations = newAffirmations
            currentIndex = 0
            batchConsumed = 0 // Reset batch consumption on new load
            
        case .affirmationsLoadFailed(let error):
            self.error = error
            affirmations = Affirmation.samples
            currentIndex = 0
        }
    }
}

// MARK: - Event Handlers

private extension PracticeStore {
    
    // MARK: Mode Selection
    
    func handleSelectMode(_ mode: SessionMode) {
        cancelCurrentActivity()
        
        // Increment generation to invalidate any in-flight updates from old flow
        flowGeneration += 1
        
        // Reset progress immediately (before any animation)
        segmentProgress = 0
        
        // Reset session tracking when entering non-default mode
        if mode != .readOnly {
            sessionProgress = 0
            sessionResults = []
            sessionStartIndex = currentIndex
            sessionMode = mode
            sessionStartTime = Date()
        }
        
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
            
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
        
        // Start flow if entering active mode
        if mode != .readOnly {
            currentIndex = 0
            startFlowForCurrentAffirmation()
        }
    }
    
    func handleSelectBinaural(_ preset: BinauralPreset) {
        withAnimation(AppTheme.Animation.standard) {
            binauralPreset = preset
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        // Start/stop binaural beats
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
    
    // MARK: Navigation
    
    func handleUserNavigated(_ direction: NavigationDirection) {
        // User swiped - index already changed by VerticalPager
        // Flow was reset to idle in updateIndex (atomic with index change)
        cancelCurrentActivity()
        
        // Track batch consumption (any mode)
        incrementBatchConsumed()
        
        // Record view for the new affirmation
        recordEngagement(.view)
        
        // Track session progress (non-default modes only)
        if isSessionActive {
            incrementSessionProgress()
            
            // Check if session should end
            if checkSessionCompletion() {
                return // Session ended, don't continue flow
            }
            
            startFlowForCurrentAffirmation()
        }
    }
    
    func handleNavigateViaButton(_ direction: NavigationDirection) {
        // Check bounds only - user button presses should always work
        switch direction {
        case .next:
            guard canGoNext else { return }
        case .previous:
            guard canGoPrevious else { return }
        }
        
        // User explicitly pressed button - cancel any ongoing activity and navigate
        cancelCurrentActivity()
        resetToIdle()
        
        // Clear navigation lock for explicit button press
        isNavigationLocked = false
        
        // Trigger animated transition via VerticalPager
        pendingAutoAdvance = direction
    }
    
    func handleAutoAdvanceCompleted() {
        pendingAutoAdvance = nil
        
        // Track batch consumption (any mode)
        incrementBatchConsumed()
        
        // Record view for the new affirmation
        recordEngagement(.view)
        
        // Track session progress (non-default modes only)
        if isSessionActive {
            incrementSessionProgress()
            
            // Check if session should end
            if checkSessionCompletion() {
                return // Session ended, don't continue flow
            }
            
            startFlowForCurrentAffirmation()
        }
    }
    
    func handleGoToIndex(_ index: Int) {
        guard affirmations.indices.contains(index) else { return }
        guard !shouldBlockNavigation else { return }
        
        cancelCurrentActivity()
        currentIndex = index
        resetToIdle()
        
        // Track batch consumption
        incrementBatchConsumed()
        
        // Record view for the new affirmation
        recordEngagement(.view)
        
        if isSessionActive {
            incrementSessionProgress()
            
            if checkSessionCompletion() {
                return
            }
            
            startFlowForCurrentAffirmation()
        }
    }
    
    // MARK: Session Control
    
    func handleExitSession() {
        cancelCurrentActivity()
        resetToIdle()
        
        // Reset session progress
        sessionProgress = 0
        
        withAnimation(AppTheme.Animation.standard) {
            flow = .home
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
    
    // MARK: TTS Events
    
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
            // Transition to complete, then auto-advance
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAloud(.complete)
                segmentProgress = 1.0
            }
            scheduleAutoAdvance()
            
        default:
            // readAndSpeak flow handles its own transitions in executeReadAndSpeakFlow
            break
        }
    }
    
    // MARK: Listening Events
    
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
        // Transition to analyzing
        transitionToAnalyzing()
        
        // Calculate score (simulated for now)
        Task {
            try? await Task.sleep(for: PracticeTiming.analysisDuration)
            
            guard !Task.isCancelled else { return }
            
            // Generate score (will be replaced with real calculation)
            let score = Double.random(in: 0.6...1.0)
            let components = ScoreComponents(
                textAccuracy: Double.random(in: 0.7...1.0),
                vocalEnergy: Double.random(in: 0.6...1.0),
                pitchStability: Double.random(in: 0.7...1.0)
            )
            
            let result = ScoreResult(
                score: score,
                components: components,
                duration: duration,
                mode: currentMode,
                recognizedText: text
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
    
    // MARK: Score Events
    
    func handleScoreCalculated(_ result: ScoreResult) {
        // Save the record
        lastResonanceRecord = result.toRecord()
        
        // Update affirmation stats via direct model access (backward compat)
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            affirmation.resonanceScores.append(result.toRecord())
            
            // Update existing session result with score (was added with nil score when visited)
            if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
                sessionResults[index].score = result.percentScore
            }
        }
        
        // Also record via repository for persistence
        recordEngagement(.speak)
        recordResonance(result.toRecord())
        
        // Transition to showing score
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
        
        // Lock navigation during score display
        lockNavigation()
        
        // Schedule auto-advance after score display
        Task {
            try? await Task.sleep(for: PracticeTiming.scoreDisplayDuration)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                send(.scoreDisplayCompleted)
            }
        }
    }
    
    func handleScoreDisplayCompleted() {
        // Check if this is the last affirmation in the session BEFORE triggering auto-advance.
        // sessionProgress tracks navigations completed. After navigating to the 10th affirmation,
        // sessionProgress = 9 (sessionSize - 1). When we complete that affirmation flow,
        // we should show the results summary.
        if isSessionActive && sessionProgress >= Constants.Session.sessionSize - 1 {
            // Session complete - show results summary
            #if DEBUG
            print("[LOG] PracticeStore: Session complete at affirmation \(sessionProgress + 1)")
            #endif
            
            showSessionSummary()
            return
        }
        
        if canGoNext {
            // DO NOT reset to idle here - keep the score showing during the animation
            // This prevents the progress bar from flickering (100% to 0% to 100%)
            // The reset to idle happens in handleAutoAdvanceCompleted AFTER index changes
            pendingAutoAdvance = .next
        } else {
            // At end of list - keep showing the completed score
            // User can navigate back manually or exit the session
        }
    }
    
    // MARK: Affirmation Events
    
    func handleToggleFavorite() {
        guard let affirmation = currentAffirmation else { return }
        
        // Update model directly for immediate UI feedback.
        // The FavoriteButton component observes the Affirmation model directly,
        // so SwiftUI automatically re-renders when isFavorited changes.
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        // Also persist via repository
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
        // TODO: Implement share sheet
    }
    
    func recordAffirmationView() {
        guard let affirmation = currentAffirmation else { return }
        
        // Update model directly for immediate state
        affirmation.hasBeenSeen = true
        affirmation.viewCount += 1
        affirmation.lastInteractedAt = Date()
    }
}

// MARK: - Session & Batch Tracking

private extension PracticeStore {
    
    /// Increments batch consumed counter and triggers refresh if needed
    func incrementBatchConsumed() {
        batchConsumed += 1
        
        #if DEBUG
        print("[LOG] Batch consumed: \(batchConsumed)/\(Constants.Session.batchSize)")
        #endif
        
        // Check if we need to proactively refresh
        checkBatchRefresh()
    }
    
    /// Increments session progress counter (non-default modes only)
    func incrementSessionProgress() {
        guard isSessionActive else { return }
        sessionProgress += 1
        
        #if DEBUG
        print("[LOG] Session progress: \(sessionProgress)/\(Constants.Session.sessionSize)")
        #endif
    }
    
    /// Records the current affirmation for the session summary (scoring modes only).
    ///
    /// Called when starting flow for an affirmation. Adds with nil score initially.
    /// Score is updated later in handleScoreCalculated if user completes the flow.
    /// If user skips, the affirmation remains with nil score (shown as "Skipped").
    func recordAffirmationForSession() {
        guard let affirmation = currentAffirmation else { return }
        
        // Check if already recorded (handles back-then-forward navigation)
        guard !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) else { return }
        
        // Determine if this mode produces scores
        let isFromScoringMode = (sessionMode == .readThenSpeak || sessionMode == .speakOnly)
        
        // Add with nil score (pending)
        let result = SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: isFromScoringMode)
        sessionResults.append(result)
        
        #if DEBUG
        print("[LOG] PracticeStore: Recorded affirmation for session: \(affirmation.text.prefix(30))...")
        #endif
    }
    
    /// Checks if batch needs refresh and triggers background fetch
    func checkBatchRefresh() {
        guard batchConsumed >= Constants.Session.regenerationTriggerIndex else { return }
        guard !isBatchRefreshInProgress else { return }
        guard let repo = repository else { return }
        guard !loadedCategories.isEmpty else { return }
        
        isBatchRefreshInProgress = true
        
        #if DEBUG
        print("[LOG] PracticeStore: Triggering background batch refresh...")
        #endif
        
        // Capture categories for the task
        let categories = loadedCategories
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            do {
                // Fetch next batch (synchronous call on MainActor)
                let newAffirmations = try repo.fetchQueue(
                    forCategories: categories,
                    limit: Constants.Session.batchSize
                )
                
                // Append to queue seamlessly
                self.appendNewBatch(newAffirmations)
                self.isBatchRefreshInProgress = false
                
                #if DEBUG
                print("[OK] PracticeStore: Batch refresh complete. Added \(newAffirmations.count) affirmations")
                #endif
            } catch {
                self.isBatchRefreshInProgress = false
                
                #if DEBUG
                print("[LOG] PracticeStore: Batch refresh failed: \(error)")
                #endif
            }
        }
    }
    
    /// Appends new affirmations to the queue
    func appendNewBatch(_ newAffirmations: [Affirmation]) {
        // Filter out any duplicates
        let existingIds = Set(affirmations.map { $0.id })
        let uniqueNew = newAffirmations.filter { !existingIds.contains($0.id) }
        
        affirmations.append(contentsOf: uniqueNew)
        batchConsumed = 0 // Reset counter after refresh
    }
    
    /// Checks if session should complete (10 affirmations in non-default mode)
    /// - Returns: `true` if session ended, `false` to continue
    func checkSessionCompletion() -> Bool {
        guard isSessionActive else { return false }
        guard sessionProgress >= Constants.Session.sessionSize else { return false }
        
        #if DEBUG
        print("[LOG] PracticeStore: Session complete! (\(sessionProgress) affirmations)")
        #endif
        
        // Complete session WITHOUT animation to prevent visual artifacts.
        // When animated, the dock height change causes the page to slide up.
        // We want a clean transition back to home mode.
        completeSessionSilently()
        
        return true
    }
    
    /// Completes the session and returns to home mode without animation.
    ///
    /// This method is separate from `handleExitSession()` because:
    /// - `handleExitSession()` is triggered by user pressing Exit button (should animate)
    /// - `completeSessionSilently()` is triggered when session naturally completes (should NOT animate)
    ///
    /// Without animation, the dock height change happens instantly, preventing
    /// the visual artifact where the page slides up before transitioning.
    private func completeSessionSilently() {
        // Cancel any pending work first
        cancelCurrentActivity()
        
        // Reset progress immediately (NOT animated - prevents visual artifacts)
        segmentProgress = 0
        
        // Reset session tracking
        sessionProgress = 0
        
        // Transition to home IMMEDIATELY without animation.
        // CRITICAL: Do NOT wrap this in withAnimation()!
        // When flow changes, isSessionActive becomes false, which changes dockOffset.
        // If animated, the padding change causes the page content to slide up.
        // By changing instantly, the view updates without visible motion.
        flow = .home
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
        
        // Success haptic feedback
        HapticFeedback.notification(.success)
    }
    
    // MARK: - Session Summary
    
    /// Shows the results summary after a scoring session completes.
    ///
    /// Called when the 10th affirmation's score display completes in
    /// Read & Speak or Speak Only modes.
    private func showSessionSummary() {
        // Cancel any pending work
        cancelCurrentActivity()
        
        // Brief pause before transition (user sees final score)
        Task {
            try? await Task.sleep(for: PracticeTiming.sessionCompletePause)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Disable interactions during crossfade
                isNavigationLocked = true
                
                // Show summary with crossfade animation
                withAnimation(.easeInOut(duration: PracticeTiming.summaryTransitionDuration)) {
                    isShowingSummary = true
                }
                
                // Re-enable interactions after crossfade
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryTransitionDuration * 1000)))
                    await MainActor.run {
                        isNavigationLocked = false
                    }
                }
                
                // Success haptic
                HapticFeedback.notification(.success)
            }
        }
    }
    
    /// Handles dismissing the summary and returning to home.
    func handleDismissSummary() {
        // Reset session state
        sessionProgress = 0
        sessionResults = []
        
        // Hide summary with slide-down animation
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            isShowingSummary = false
        }
        
        // Return to home (instant, hidden by animation)
        flow = .home
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
    }
    
    /// Handles retry - restarts session with same affirmations.
    func handleRetrySession() {
        // Reset to session start
        currentIndex = sessionStartIndex
        sessionProgress = 0
        sessionResults = []
        segmentProgress = 0
        
        // Reset flow to idle state of the session mode
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
        
        // Hide summary with slide-down animation
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            isShowingSummary = false
        }
        
        // Start flow after animation completes
        Task {
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            await MainActor.run {
                startFlowForCurrentAffirmation()
            }
        }
    }
    
    /// Handles toggling favorite for an affirmation in the summary.
    func handleToggleFavoriteInSummary(affirmationId: UUID) {
        // Find the affirmation in our list
        guard let affirmation = affirmations.first(where: { $0.id == affirmationId }) else { return }
        
        // Toggle favorite
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        // Update the session result to match
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmationId }) {
            sessionResults[index].isFavorited = affirmation.isFavorited
        }
        
        // Persist via repository
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
    
    /// Starts the appropriate flow for the current affirmation
    func startFlowForCurrentAffirmation() {
        guard currentAffirmation != nil else { return }
        
        // Cancel any existing flow
        activeFlowTask?.cancel()
        
        // Increment generation to invalidate any in-flight updates
        flowGeneration += 1
        
        // Record the view
        recordAffirmationView()
        recordEngagement(.view)
        
        // For all session modes, record this affirmation for the session summary
        // (if not already recorded - handles case where user goes back then forward)
        if sessionMode != .readOnly {
            recordAffirmationForSession()
        }
        
        // Capture generation for this flow
        let generation = flowGeneration
        
        // Start the new flow
        activeFlowTask = Task {
            await executeCurrentFlow(generation: generation)
        }
    }
    
    /// Executes the flow based on current mode
    func executeCurrentFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Small delay before starting
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
    
    /// Read Aloud: TTS plays, then auto-advance
    func executeReadAloudFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Start TTS
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAloud(.playing(progress: 0))
            }
        }
        
        // Simulate TTS playback (replace with real TTS)
        for i in 0...20 {
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            try? await Task.sleep(for: .milliseconds(100))
            let progress = Double(i) / 20.0
            await MainActor.run {
                guard generation == flowGeneration else { return }
                send(.ttsProgress(progress))
            }
        }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        await MainActor.run {
            guard generation == flowGeneration else { return }
            send(.ttsCompleted)
        }
    }
    
    /// Read & Speak: TTS plays, wait, listen, score, auto-advance
    func executeReadAndSpeakFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Phase 1: TTS
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAndSpeak(.ttsPlaying(progress: 0))
            }
        }
        
        // Simulate TTS playback
        for i in 0...20 {
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            try? await Task.sleep(for: .milliseconds(100))
            let progress = Double(i) / 20.0
            await MainActor.run {
                guard generation == flowGeneration else { return }
                send(.ttsProgress(progress))
            }
        }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
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
        
        // Phase 3: Listen
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .readAndSpeak(.listening(.initial))
            }
        }
        
        // Simulate listening duration (will be replaced with real speech recognition)
        var elapsed: TimeInterval = 0
        while elapsed < 2.0 {
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            try? await Task.sleep(for: .milliseconds(100))
            elapsed += 0.1
            
            let context = ListeningContext(
                elapsed: elapsed,
                audioLevel: Double.random(in: 0.3...0.8),
                recognizedText: "" // Empty - real text will come from speech recognition
            )
            
            await MainActor.run {
                guard generation == flowGeneration else { return }
                send(.listeningUpdate(context))
            }
        }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Listening complete - triggers analysis and scoring
        await MainActor.run {
            guard generation == flowGeneration else { return }
            send(.listeningCompleted(recognizedText: "", duration: elapsed))
        }
    }
    
    /// Speak Only: Listen, score, auto-advance
    func executeSpeakOnlyFlow(generation: Int) async {
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Phase 1: Listen
        await MainActor.run {
            guard generation == flowGeneration else { return }
            withAnimation(AppTheme.Animation.quick) {
                flow = .speakOnly(.listening(.initial))
            }
        }
        
        // Simulate listening duration (will be replaced with real speech recognition)
        var elapsed: TimeInterval = 0
        while elapsed < 2.0 {
            guard !Task.isCancelled else { return }
            guard generation == flowGeneration else { return }
            try? await Task.sleep(for: .milliseconds(100))
            elapsed += 0.1
            
            let context = ListeningContext(
                elapsed: elapsed,
                audioLevel: Double.random(in: 0.3...0.8),
                recognizedText: "" // Empty - real text will come from speech recognition
            )
            
            await MainActor.run {
                guard generation == flowGeneration else { return }
                send(.listeningUpdate(context))
            }
        }
        
        guard !Task.isCancelled else { return }
        guard generation == flowGeneration else { return }
        
        // Listening complete - triggers analysis and scoring
        await MainActor.run {
            guard generation == flowGeneration else { return }
            send(.listeningCompleted(recognizedText: "", duration: elapsed))
        }
    }
}

// MARK: - Scheduling Helpers

private extension PracticeStore {
    
    func scheduleAutoAdvance() {
        Task {
            try? await Task.sleep(for: PracticeTiming.readAloudCompletePause)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Check session completion before auto-advancing (for readAloud mode)
                if isSessionActive && sessionProgress >= Constants.Session.sessionSize - 1 {
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
    
    /// Cancels any in-progress activity
    func cancelCurrentActivity() {
        activeFlowTask?.cancel()
        activeFlowTask = nil
        pendingAutoAdvance = nil
    }
    
    /// Resets to idle state within current mode
    func resetToIdle() {
        // Reset progress immediately (no animation)
        segmentProgress = 0
        
        // Animate flow transition
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
    
    /// Loads affirmations using the repository pattern.
    ///
    /// Uses the smart queue algorithm to prioritize:
    /// 1. Unseen affirmations first
    /// 2. Least viewed affirmations
    /// 3. Oldest practiced affirmations
    ///
    /// - Parameters:
    ///   - repository: The affirmation repository to use
    ///   - categories: User's selected goal categories (empty = load all)
    func loadAffirmations(
        using repository: any AffirmationRepositoryProtocol,
        forCategories categories: [String]
    ) async {
        // Store repository for later engagement tracking and batch refresh
        self.repository = repository
        self.loadedCategories = categories
        
        do {
            let queue: [Affirmation]
            
            if categories.isEmpty {
                // No categories selected - use sample data
                #if DEBUG
                print("[LOG] PracticeStore: No categories selected, using samples")
                #endif
                queue = Affirmation.samples
            } else {
                // Fetch from repository with smart queue sorting
                queue = try repository.fetchQueue(
                    forCategories: categories,
                    limit: Constants.Session.batchSize
                )
                
                #if DEBUG
                print("[LOG] PracticeStore: Loaded \(queue.count) affirmations for \(categories.count) categories")
                #endif
            }
            
            if queue.isEmpty {
                // Fallback to samples if database is empty
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
    
    /// Loads favorited affirmations using the repository.
    ///
    /// - Parameter repository: The affirmation repository to use
    func loadFavorites(using repository: any AffirmationRepositoryProtocol) async {
        self.repository = repository
        
        do {
            let favorites = try repository.fetchFavorites()
            
            guard !favorites.isEmpty else {
                error = .dataLoadError("No favorites yet. Heart some affirmations first!")
                return
            }
            
            send(.affirmationsLoaded(favorites))
            send(.exitSession) // Return to browse mode
            
        } catch {
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    /// Updates current index (called by VerticalPager binding)
    ///
    /// Resets segmentProgress to 0 immediately when index changes.
    func updateIndex(_ newIndex: Int) {
        guard affirmations.indices.contains(newIndex) else { return }
        guard newIndex != currentIndex else { return }
        
        // Increment generation to invalidate any in-flight updates
        flowGeneration += 1
        
        // Always reset progress immediately for new segment
        segmentProgress = 0
        
        // Also reset flow if in active session
        if isSessionActive {
            resetToIdle()
        }
        
        currentIndex = newIndex
    }
    
    // MARK: - Legacy Support (Deprecated)
    
    /// Legacy method - use `loadAffirmations(using:forCategories:)` instead.
    @available(*, deprecated, message: "Use loadAffirmations(using:forCategories:) instead")
    func loadAffirmations(from modelContext: ModelContext) async {
        // Legacy fallback - loads all affirmations without filtering
        let now = Date()
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.expiresAt > now },
            sortBy: [SortDescriptor(\.batchIndex)]
        )
        
        do {
            var fetched = try modelContext.fetch(descriptor)
            
            fetched.sort { a, b in
                if a.hasBeenSeen != b.hasBeenSeen {
                    return !a.hasBeenSeen
                }
                return a.batchIndex < b.batchIndex
            }
            
            let batch = Array(fetched.prefix(Constants.Session.batchSize))
            
            if batch.isEmpty {
                send(.affirmationsLoaded(Affirmation.samples))
            } else {
                send(.affirmationsLoaded(batch))
            }
            
        } catch {
            send(.affirmationsLoadFailed(.dataLoadError(error.localizedDescription)))
        }
    }
    
    /// Legacy method - use `loadFavorites(using:)` instead.
    @available(*, deprecated, message: "Use loadFavorites(using:) instead")
    func loadFavorites(from modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Affirmation>(
            predicate: #Predicate { $0.isFavorited },
            sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
        )
        
        do {
            let favorites = try modelContext.fetch(descriptor)
            
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
}

// MARK: - Engagement Tracking

extension PracticeStore {
    
    /// Records engagement for the current affirmation.
    ///
    /// Call this when user views, speaks, or interacts with an affirmation.
    ///
    /// - Parameter type: The type of engagement to record
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
    
    /// Records a resonance score for the current affirmation.
    ///
    /// - Parameter record: The resonance record to save
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

/// Types of user engagement with affirmations
enum EngagementType: Sendable {
    /// User viewed the affirmation
    case view
    /// User spoke the affirmation
    case speak
    /// User skipped past quickly
    case skip
    /// User shared the affirmation
    case share
}

// MARK: - Background State

/// State for the morphing gradient background
struct BackgroundState: Equatable {
    let currentCategory: GoalCategory?
    let previousCategory: GoalCategory?
    
    /// Creates background state
    init(currentCategory: GoalCategory?, previousCategory: GoalCategory?) {
        self.currentCategory = currentCategory
        self.previousCategory = previousCategory
    }
    
    /// Fallback when no category
    static let `default` = BackgroundState(
        currentCategory: .confidence,
        previousCategory: nil
    )
}

// MARK: - Preview Support

extension PracticeStore {
    
    /// Preview store in home mode
    static var preview: PracticeStore {
        let store = PracticeStore()
        store.affirmations = Affirmation.samples
        return store
    }
    
    /// Preview store in active read aloud mode
    static var previewReadAloud: PracticeStore {
        let store = PracticeStore()
        store.affirmations = Affirmation.samples
        store.flow = .readAloud(.playing(progress: 0.5))
        return store
    }
    
    /// Preview store in active read and speak mode (listening)
    static var previewListening: PracticeStore {
        let store = PracticeStore()
        store.affirmations = Affirmation.samples
        store.flow = .readAndSpeak(.listening(ListeningContext(
            elapsed: 1.5,
            audioLevel: 0.6,
            recognizedText: "I am confident..."
        )))
        return store
    }
    
    /// Preview store showing score
    static var previewShowingScore: PracticeStore {
        let store = PracticeStore()
        store.affirmations = Affirmation.samples
        store.flow = .readAndSpeak(.showingScore(ScoreResult(
            score: 0.85,
            components: .sample,
            duration: 2.5,
            mode: .readThenSpeak,
            recognizedText: "I am confident and capable"
        )))
        return store
    }
    
    /// Preview store with expanded mode selector
    static var previewModeSelector: PracticeStore {
        let store = PracticeStore()
        store.affirmations = Affirmation.samples
        store.isModeSelectorExpanded = true
        return store
    }
}

// MARK: - Convenience Methods

extension PracticeStore {
    
    /// Convenience for exiting session
    func exit() {
        send(.exitSession)
    }
    
    /// Convenience for toggling favorite
    func toggleFavorite() {
        send(.toggleFavorite)
    }
    
    /// Convenience for sharing
    func share() {
        send(.shareAffirmation)
    }
    
    /// Convenience for dismissing error
    func dismissError() {
        send(.dismissError)
    }
    
    /// Called when view appears
    func onAppear() {
        send(.viewAppeared)
    }
    
    /// Called when view disappears
    func onDisappear() {
        send(.viewDisappeared)
    }
    
    /// Continues flow after auto-advance animation
    func continueFlow() {
        send(.autoAdvanceCompleted)
    }
    
    /// Navigate in direction
    func navigate(_ direction: NavigationDirection) {
        send(.userNavigated(direction))
    }
}
