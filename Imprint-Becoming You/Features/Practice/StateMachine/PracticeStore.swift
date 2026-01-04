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
    var canGoPrevious: Bool {
        currentIndex > 0
    }
    
    /// Whether we can navigate to next affirmation
    var canGoNext: Bool {
        currentIndex < affirmations.count - 1
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
        print("📨 PracticeStore.send: \(event)")
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
            // TODO: Implement share sheet
            break
            
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
        
        if isSessionActive {
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
        
        // Note: Flow reset to idle happens in updateIndex (atomic with index change)
        
        if isSessionActive {
            startFlowForCurrentAffirmation()
        }
    }
    
    func handleGoToIndex(_ index: Int) {
        guard affirmations.indices.contains(index) else { return }
        guard !shouldBlockNavigation else { return }
        
        cancelCurrentActivity()
        currentIndex = index
        resetToIdle()
        
        if isSessionActive {
            startFlowForCurrentAffirmation()
        }
    }
    
    // MARK: Session Control
    
    func handleExitSession() {
        cancelCurrentActivity()
        resetToIdle()
        
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
        
        // Update affirmation stats
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            affirmation.resonanceScores.append(result.toRecord())
        }
        
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
        if canGoNext {
            // DO NOT reset to idle here - keep the score showing during the animation
            // This prevents the progress bar from flickering (100% → 0% → 100%)
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
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        HapticFeedback.selection()
    }
    
    func recordAffirmationView() {
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.hasBeenSeen = true
        affirmation.viewCount += 1
        affirmation.lastInteractedAt = Date()
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
    
    /// Loads affirmations from SwiftData
    func loadAffirmations(from modelContext: ModelContext) async {
        do {
            let now = Date()
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate { $0.expiresAt > now },
                sortBy: [SortDescriptor(\.batchIndex)]
            )
            
            var fetched = try modelContext.fetch(descriptor)
            
            // Sort: unseen first, then by batch index
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
    
    /// Loads favorited affirmations
    func loadFavorites(from modelContext: ModelContext) async {
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate { $0.isFavorited },
                sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
            )
            
            let favorites = try modelContext.fetch(descriptor)
            
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
