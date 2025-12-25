//
//  PracticeViewModel.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI
import SwiftData

// MARK: - PracticeViewModel

/// ViewModel for the main practice experience.
///
/// ## Auto-Advance System
/// Coordinates animated transitions with flow continuation:
/// 1. Flow completes (TTS done, or score shown)
/// 2. `pendingAutoAdvance` is set to trigger animation
/// 3. VerticalPager animates and updates `currentIndex`
/// 4. `currentIndex.didSet` updates DockProgressBars
/// 5. VerticalPager calls `continueFlow()`
/// 6. Next affirmation flow starts
/// 7. Repeat until end of list
///
/// ## Navigation State Machine
/// User gestures cleanly interrupt any in-progress activity:
/// - Stops TTS playback immediately
/// - Cancels speech recording (discards data)
/// - Respects navigation lock during score display
@Observable
final class PracticeViewModel {
    
    // MARK: - Dependencies
    
    let dockManager = DockStateManager()
    
    // MARK: - Affirmation State
    
    var affirmations: [Affirmation] = []
    
    /// Current affirmation index - didSet keeps dock in sync
    var currentIndex: Int = 0 {
        didSet {
            dockManager.updateProgress(current: currentIndex, total: affirmations.count)
        }
    }
    
    var currentAffirmation: Affirmation? {
        guard affirmations.indices.contains(currentIndex) else { return nil }
        return affirmations[currentIndex]
    }
    
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < affirmations.count - 1 }
    
    // MARK: - Session State
    
    var isSessionActive: Bool { dockManager.isInActiveMode }
    var currentMode: SessionMode { dockManager.currentMode }
    
    var binauralPreset: BinauralPreset {
        get { dockManager.binauralPreset }
        set { dockManager.updateBinauralPreset(newValue) }
    }
    
    // MARK: - Audio State
    
    var isTTSPlaying: Bool = false
    var isListening: Bool = false
    var recognizedText: String = ""
    var audioLevel: CGFloat = 0.0
    
    // MARK: - Score State
    
    var realtimeScore: Double = 0.0 {
        didSet { dockManager.updateRealtimeScore(realtimeScore) }
    }
    
    var lastResonanceRecord: ResonanceRecord?
    
    // MARK: - Auto-Advance State
    
    /// Set to trigger animated advance in VerticalPager
    var pendingAutoAdvance: NavigationDirection? = nil
    
    /// Active flow task (can be cancelled on user navigation)
    private var activeFlowTask: Task<Void, Never>?
    
    // MARK: - Navigation State
    
    /// Locks navigation during score display animation
    var isNavigationLocked: Bool = false
    private let scoreLockDuration: Duration = .seconds(1)
    
    // MARK: - UI State
    
    var showProfileSheet: Bool = false
    var showCategoriesSheet: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    private var lastInteractionTime: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        dockManager.updateProgress(current: 0, total: 0)
    }
    
    // MARK: - Setup
    
    @MainActor
    func loadAffirmations(from modelContext: ModelContext) async {
        do {
            let now = Date()
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate { $0.expiresAt > now },
                sortBy: [SortDescriptor(\.batchIndex)]
            )
            
            var fetched = try modelContext.fetch(descriptor)
            
            fetched.sort { a, b in
                if a.hasBeenSeen != b.hasBeenSeen {
                    return !a.hasBeenSeen
                }
                return a.batchIndex < b.batchIndex
            }
            
            affirmations = Array(fetched.prefix(Constants.Session.batchSize))
            
            if affirmations.isEmpty {
                affirmations = Affirmation.samples
            }
            
            currentIndex = 0
            dockManager.updateProgress(current: 0, total: affirmations.count)
            
        } catch {
            print("Failed to load affirmations: \(error)")
            affirmations = Affirmation.samples
            dockManager.updateProgress(current: 0, total: affirmations.count)
        }
    }
    
    @MainActor
    func loadFavorites(from modelContext: ModelContext) async {
        do {
            let descriptor = FetchDescriptor<Affirmation>(
                predicate: #Predicate { $0.isFavorited },
                sortBy: [SortDescriptor(\.favoritedAt, order: .reverse)]
            )
            
            let favorites = try modelContext.fetch(descriptor)
            
            guard !favorites.isEmpty else {
                errorMessage = "No favorites yet. Heart some affirmations first!"
                showError = true
                return
            }
            
            affirmations = favorites
            currentIndex = 0
            dockManager.updateProgress(current: 0, total: affirmations.count)
            dockManager.returnToHome()
            
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - User Navigation (Gesture-Initiated)
    
    /// Called when user swipes to navigate - cancels any in-progress activity
    /// This is called AFTER VerticalPager has already updated the index
    @MainActor
    func navigate(_ direction: NavigationDirection) {
        // Cancel any in-progress activity (TTS, listening, etc.)
        cancelCurrentActivity()
        resetToIdleState()
        recordInteraction()
        
        // Start flow for new affirmation
        if isSessionActive {
            activeFlowTask = Task {
                await beginAffirmationFlow()
            }
        }
    }
    
    /// Navigates via button tap - triggers animated transition
    /// This is called BEFORE index changes, so it sets pendingAutoAdvance
    @MainActor
    func navigateViaButton(_ direction: NavigationDirection) {
        // Check bounds BEFORE navigation
        switch direction {
        case .next:
            guard canGoNext else { return }
        case .previous:
            guard canGoPrevious else { return }
        }
        
        // Cancel any in-progress activity immediately
        cancelCurrentActivity()
        resetToIdleState()
        
        // Unlock navigation (button press overrides lock)
        isNavigationLocked = false
        
        // Trigger animated transition via VerticalPager
        pendingAutoAdvance = direction
        
        recordInteraction()
    }
    
    @MainActor
    func nextAffirmation() {
        navigateViaButton(.next)
    }
    
    @MainActor
    func previousAffirmation() {
        navigateViaButton(.previous)
    }
    
    @MainActor
    func goToAffirmation(at index: Int) {
        guard affirmations.indices.contains(index) else { return }
        guard !isNavigationLocked else { return }
        
        cancelCurrentActivity()
        currentIndex = index
        resetToIdleState()
        recordInteraction()
        
        if isSessionActive {
            activeFlowTask = Task {
                await beginAffirmationFlow()
            }
        }
    }
    
    // MARK: - Auto-Advance (Flow-Initiated)
    
    /// Triggers animated advance to next affirmation
    /// Called at end of flow methods to continue automatically
    @MainActor
    private func autoAdvanceToNext() {
        guard canGoNext else { return }
        pendingAutoAdvance = .next
    }
    
    /// Called by VerticalPager after auto-advance animation completes
    /// Continues the flow for the new affirmation
    @MainActor
    func continueFlow() {
        guard isSessionActive else { return }
        
        activeFlowTask = Task {
            await beginAffirmationFlow()
        }
    }
    
    // MARK: - Activity Management
    
    @MainActor
    private func cancelCurrentActivity() {
        activeFlowTask?.cancel()
        activeFlowTask = nil
        pendingAutoAdvance = nil
        
        if isTTSPlaying {
            isTTSPlaying = false
            // TODO: Call audioService.stopTTS() when integrated
        }
        
        if isListening {
            isListening = false
            recognizedText = ""
            // TODO: Call speechAnalysisService.cancelAnalysis() when integrated
        }
    }
    
    @MainActor
    private func resetToIdleState() {
        isTTSPlaying = false
        isListening = false
        recognizedText = ""
        realtimeScore = 0
        lastResonanceRecord = nil
        audioLevel = 0
        
        switch dockManager.state {
        case .readAloud:
            dockManager.updateReadAloudPhase(.idle)
        case .readAndSpeak:
            dockManager.updateReadAndSpeakPhase(.idle)
        case .speakOnly:
            dockManager.updateSpeakOnlyPhase(.idle)
        case .home:
            break
        }
    }
    
    @MainActor
    private func lockNavigationForScore() {
        isNavigationLocked = true
        
        Task {
            try? await Task.sleep(for: scoreLockDuration)
            await MainActor.run {
                isNavigationLocked = false
            }
        }
    }
    
    // MARK: - Mode Management
    
    @MainActor
    func changeMode(_ mode: SessionMode, audioService: any AudioServiceProtocol) async {
        cancelCurrentActivity()
        dockManager.setMode(mode)
        recordInteraction()
        
        if mode != .readOnly {
            currentIndex = 0
            activeFlowTask = Task {
                await beginAffirmationFlow()
            }
        }
    }
    
    @MainActor
    func stopSession() async {
        cancelCurrentActivity()
        resetToIdleState()
        dockManager.returnToHome()
    }
    
    // MARK: - Binaural Management
    
    @MainActor
    func changeBinauralPreset(_ preset: BinauralPreset, audioService: any AudioServiceProtocol) async {
        binauralPreset = preset
        
        do {
            if preset == .off {
                await audioService.stopBinauralBeats()
            } else {
                try await audioService.startBinauralBeats(preset: preset)
            }
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Affirmation Flow
    
    @MainActor
    private func beginAffirmationFlow() async {
        guard let affirmation = currentAffirmation else { return }
        guard !Task.isCancelled else { return }
        
        // Mark as seen
        affirmation.hasBeenSeen = true
        affirmation.viewCount += 1
        affirmation.lastInteractedAt = Date()
        
        switch dockManager.state {
        case .home:
            break
        case .readAloud:
            await beginReadAloudFlow()
        case .readAndSpeak:
            await beginReadAndSpeakFlow()
        case .speakOnly:
            await beginSpeakOnlyFlow()
        }
    }
    
    // MARK: - Read Aloud Flow
    
    @MainActor
    private func beginReadAloudFlow() async {
        guard !Task.isCancelled else { return }
        
        dockManager.updateReadAloudPhase(.speaking)
        isTTSPlaying = true
        
        // TTS would play here - simulated
        try? await Task.sleep(for: .seconds(2))
        
        guard !Task.isCancelled else { return }
        
        isTTSPlaying = false
        dockManager.updateReadAloudPhase(.complete)
        
        // Brief pause before advance
        try? await Task.sleep(for: .milliseconds(500))
        
        guard !Task.isCancelled else { return }
        
        // Auto-advance with animation - flow continues via continueFlow()
        if canGoNext {
            autoAdvanceToNext()
        }
        // If at end, stay on last affirmation
    }
    
    // MARK: - Read & Speak Flow
    
    @MainActor
    private func beginReadAndSpeakFlow() async {
        // Phase 1: TTS
        guard !Task.isCancelled else { return }
        dockManager.updateReadAndSpeakPhase(.ttsPlaying)
        isTTSPlaying = true
        
        try? await Task.sleep(for: .seconds(2))
        
        guard !Task.isCancelled else { return }
        isTTSPlaying = false
        
        // Phase 2: Wait for user
        dockManager.updateReadAndSpeakPhase(.waitingForUser)
        try? await Task.sleep(for: .milliseconds(500))
        
        guard !Task.isCancelled else { return }
        
        // Phase 3: Listen
        dockManager.updateReadAndSpeakPhase(.listening)
        isListening = true
        
        try? await Task.sleep(for: .seconds(2))
        
        guard !Task.isCancelled else { return }
        isListening = false
        
        // Phase 4: Analyze
        dockManager.updateReadAndSpeakPhase(.analyzing)
        try? await Task.sleep(for: .milliseconds(500))
        
        guard !Task.isCancelled else { return }
        
        // Phase 5: Show score
        let score = Double.random(in: 0.6...1.0)
        realtimeScore = score
        
        let record = ResonanceRecord(
            timestamp: Date(),
            overallScore: Float(score),
            textAccuracy: Float.random(in: 0.7...1.0),
            vocalEnergy: Float.random(in: 0.6...1.0),
            pitchStability: Float.random(in: 0.7...1.0),
            duration: 2.0,
            sessionMode: .readThenSpeak
        )
        lastResonanceRecord = record
        
        dockManager.updateReadAndSpeakPhase(.showingScore(score: score))
        lockNavigationForScore()
        
        // Update affirmation stats
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            affirmation.resonanceScores.append(record)
        }
        
        // Show score briefly
        try? await Task.sleep(for: .seconds(1.5))
        
        guard !Task.isCancelled else { return }
        
        // Auto-advance regardless of score (changed per requirement)
        if canGoNext {
            autoAdvanceToNext()
        }
    }
    
    // MARK: - Speak Only Flow
    
    @MainActor
    private func beginSpeakOnlyFlow() async {
        // Phase 1: Listen
        guard !Task.isCancelled else { return }
        dockManager.updateSpeakOnlyPhase(.listening)
        isListening = true
        
        try? await Task.sleep(for: .seconds(2))
        
        guard !Task.isCancelled else { return }
        isListening = false
        
        // Phase 2: Analyze
        dockManager.updateSpeakOnlyPhase(.analyzing)
        try? await Task.sleep(for: .milliseconds(500))
        
        guard !Task.isCancelled else { return }
        
        // Phase 3: Show score
        let score = Double.random(in: 0.6...1.0)
        realtimeScore = score
        
        let record = ResonanceRecord(
            timestamp: Date(),
            overallScore: Float(score),
            textAccuracy: Float.random(in: 0.7...1.0),
            vocalEnergy: Float.random(in: 0.6...1.0),
            pitchStability: Float.random(in: 0.7...1.0),
            duration: 2.0,
            sessionMode: .speakOnly
        )
        lastResonanceRecord = record
        
        dockManager.updateSpeakOnlyPhase(.showingScore(score: score))
        lockNavigationForScore()
        
        // Update affirmation stats
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            affirmation.resonanceScores.append(record)
        }
        
        // Show score briefly
        try? await Task.sleep(for: .seconds(1.5))
        
        guard !Task.isCancelled else { return }
        
        // Auto-advance regardless of score (changed per requirement)
        if canGoNext {
            autoAdvanceToNext()
        }
    }
    
    // MARK: - Engagement
    
    @MainActor
    func toggleFavorite() {
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        HapticFeedback.selection()
        recordInteraction()
    }
    
    func shareAffirmation() {
        recordInteraction()
    }
    
    // MARK: - Helpers
    
    func recordInteraction() {
        lastInteractionTime = Date()
    }
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    func dismissError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - Previews

#Preview("Practice ViewModel - Auto Advance") {
    struct PreviewWrapper: View {
        @State private var viewModel = PracticeViewModel()
        
        var body: some View {
            VStack(spacing: 20) {
                if let affirmation = viewModel.currentAffirmation {
                    Text(affirmation.text)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Text("Index: \(viewModel.currentIndex + 1) / \(viewModel.affirmations.count)")
                Text("Mode: \(viewModel.currentMode.displayName)")
                Text("Nav Locked: \(viewModel.isNavigationLocked ? "Yes" : "No")")
                
                if viewModel.pendingAutoAdvance != nil {
                    Text("⏳ Auto-advancing...")
                        .foregroundStyle(.orange)
                }
                
                HStack {
                    Button("Previous") { viewModel.previousAffirmation() }
                        .disabled(!viewModel.canGoPrevious || viewModel.isNavigationLocked)
                    
                    Button("Next") { viewModel.nextAffirmation() }
                        .disabled(!viewModel.canGoNext || viewModel.isNavigationLocked)
                }
            }
            .padding()
            .onAppear {
                viewModel.affirmations = Affirmation.samples
            }
        }
    }
    return PreviewWrapper()
}
