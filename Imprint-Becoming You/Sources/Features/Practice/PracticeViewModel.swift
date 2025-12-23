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
/// Coordinates:
/// - Affirmation display and navigation
/// - Mode switching and dock state
/// - Audio playback (TTS, binaural)
/// - Speech analysis and scoring
/// - Engagement tracking (favorites, views)
///
/// ## Architecture
/// This ViewModel owns a `DockStateManager` and delegates dock-specific
/// state management to it, while handling the broader practice logic.
@Observable
final class PracticeViewModel {
    
    // MARK: - Dependencies
    
    /// Dock state manager (owned)
    let dockManager = DockStateManager()
    
    // MARK: - Affirmation State
    
    /// Current batch of affirmations
    var affirmations: [Affirmation] = []
    
    /// Current affirmation index
    var currentIndex: Int = 0 {
        didSet {
            dockManager.updateProgress(current: currentIndex, total: affirmations.count)
        }
    }
    
    /// Currently displayed affirmation
    var currentAffirmation: Affirmation? {
        guard affirmations.indices.contains(currentIndex) else { return nil }
        return affirmations[currentIndex]
    }
    
    /// Whether we can go to previous affirmation
    var canGoPrevious: Bool {
        currentIndex > 0
    }
    
    /// Whether we can go to next affirmation
    var canGoNext: Bool {
        currentIndex < affirmations.count - 1
    }
    
    // MARK: - Session State
    
    /// Whether the session is active (not just browsing)
    var isSessionActive: Bool {
        dockManager.isInActiveMode
    }
    
    /// Current session mode
    var currentMode: SessionMode {
        dockManager.currentMode
    }
    
    /// Current binaural preset
    var binauralPreset: BinauralPreset {
        get { dockManager.binauralPreset }
        set { dockManager.updateBinauralPreset(newValue) }
    }
    
    // MARK: - Audio State
    
    /// Whether TTS is currently playing
    var isTTSPlaying: Bool = false
    
    /// Whether we're listening to user speech
    var isListening: Bool = false
    
    /// Recognized text from speech
    var recognizedText: String = ""
    
    /// Current audio level for waveform visualization (0.0 - 1.0)
    /// Updated from TTS output or microphone input depending on mode
    var audioLevel: CGFloat = 0.0
    
    // MARK: - Score State
    
    /// Current real-time score (0.0 - 1.0)
    var realtimeScore: Double = 0.0 {
        didSet {
            dockManager.updateRealtimeScore(realtimeScore)
        }
    }
    
    /// Last completed resonance record
    var lastResonanceRecord: ResonanceRecord?
    
    /// Auto-advance threshold (default 80%)
    var autoAdvanceThreshold: Double = 0.80
    
    // MARK: - UI State
    
    /// Whether to show the profile sheet
    var showProfileSheet: Bool = false
    
    /// Whether to show the categories sheet
    var showCategoriesSheet: Bool = false
    
    /// Error message to display
    var errorMessage: String?
    
    /// Whether to show error alert
    var showError: Bool = false
    
    /// Last interaction time (for timeout in speaking modes)
    private var lastInteractionTime: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        // Initial progress sync
        dockManager.updateProgress(current: 0, total: 0)
    }
    
    // MARK: - Setup
    
    /// Loads affirmations and prepares the practice view.
    @MainActor
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
            
            // Take batch size
            affirmations = Array(fetched.prefix(Constants.Session.batchSize))
            
            if affirmations.isEmpty {
                // Fallback to samples
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
    
    /// Loads favorites as the current affirmation set.
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
            
            // Return to home state for favorites browsing
            dockManager.returnToHome()
            
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Navigation
    
    /// Moves to the next affirmation.
    @MainActor
    func nextAffirmation() {
        guard canGoNext else { return }
        
        withAnimation(AppTheme.Animation.standard) {
            currentIndex += 1
        }
        
        recordInteraction()
        
        // If in active mode, begin the affirmation flow
        if isSessionActive {
            Task {
                await beginAffirmationFlow()
            }
        }
    }
    
    /// Moves to the previous affirmation.
    @MainActor
    func previousAffirmation() {
        guard canGoPrevious else { return }
        
        withAnimation(AppTheme.Animation.standard) {
            currentIndex -= 1
        }
        
        recordInteraction()
        
        // If in active mode, begin the affirmation flow
        if isSessionActive {
            Task {
                await beginAffirmationFlow()
            }
        }
    }
    
    /// Goes to a specific affirmation index.
    @MainActor
    func goToAffirmation(at index: Int) {
        guard affirmations.indices.contains(index) else { return }
        
        withAnimation(AppTheme.Animation.standard) {
            currentIndex = index
        }
        
        recordInteraction()
    }
    
    // MARK: - Mode Management
    
    /// Changes to a new session mode.
    @MainActor
    func changeMode(_ mode: SessionMode, audioService: any AudioServiceProtocol) async {
        dockManager.setMode(mode)
        
        recordInteraction()
        
        // If switching to an active mode, reset to beginning and begin the flow
        if mode != .readOnly {
            // Always start from the first affirmation when entering a new mode
            currentIndex = 0
            await beginAffirmationFlow()
        }
    }
    
    /// Returns to home (Read Only) mode.
    @MainActor
    func returnToHome(audioService: any AudioServiceProtocol) async {
        // Stop any active audio
        await audioService.stop()
        
        isTTSPlaying = false
        isListening = false
        realtimeScore = 0
        
        dockManager.returnToHome()
    }
    
    // MARK: - Binaural Management
    
    /// Changes the binaural preset.
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
    
    /// Begins the affirmation flow based on current mode.
    @MainActor
    private func beginAffirmationFlow() async {
        guard let affirmation = currentAffirmation else { return }
        
        // Mark as seen
        affirmation.hasBeenSeen = true
        affirmation.viewCount += 1
        affirmation.lastInteractedAt = Date()
        
        switch dockManager.state {
        case .home:
            // Nothing to do in home/browse mode
            break
            
        case .readAloud:
            await beginReadAloudFlow()
            
        case .readAndSpeak:
            await beginReadAndSpeakFlow()
            
        case .speakOnly:
            await beginSpeakOnlyFlow()
        }
    }
    
    /// Read Aloud flow: TTS plays, then auto-advance.
    @MainActor
    private func beginReadAloudFlow() async {
        dockManager.updateReadAloudPhase(.speaking)
        isTTSPlaying = true
        
        // TTS would play here (integration point)
        // await audioService.speakAffirmation(currentAffirmation)
        
        // Simulate TTS completion for now
        try? await Task.sleep(for: .seconds(2))
        
        isTTSPlaying = false
        dockManager.updateReadAloudPhase(.complete)
        
        // Auto-advance after brief pause
        try? await Task.sleep(for: .milliseconds(500))
        
        if canGoNext {
            nextAffirmation()
        }
    }
    
    /// Read & Speak flow: TTS plays, then user speaks.
    @MainActor
    private func beginReadAndSpeakFlow() async {
        // Phase 1: TTS
        dockManager.updateReadAndSpeakPhase(.ttsPlaying)
        isTTSPlaying = true
        
        // TTS would play here
        try? await Task.sleep(for: .seconds(2))
        
        isTTSPlaying = false
        
        // Phase 2: Wait for user
        dockManager.updateReadAndSpeakPhase(.waitingForUser)
        try? await Task.sleep(for: .milliseconds(500))
        
        // Phase 3: Listen
        dockManager.updateReadAndSpeakPhase(.listening)
        isListening = true
        
        // Speech analysis would happen here
        try? await Task.sleep(for: .seconds(2))
        
        isListening = false
        
        // Phase 4: Analyze
        dockManager.updateReadAndSpeakPhase(.analyzing)
        try? await Task.sleep(for: .milliseconds(500))
        
        // Phase 5: Show score
        let score = Double.random(in: 0.6...1.0) // Simulated
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
        
        // Update affirmation stats
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            recordResonanceScore(record, for: affirmation)
        }
        
        // Auto-advance if score meets threshold
        try? await Task.sleep(for: .seconds(1.5))
        
        if score >= autoAdvanceThreshold && canGoNext {
            nextAffirmation()
        }
        // Otherwise user must manually swipe
    }
    
    /// Speak Only flow: User speaks immediately.
    @MainActor
    private func beginSpeakOnlyFlow() async {
        // Phase 1: Listen
        dockManager.updateSpeakOnlyPhase(.listening)
        isListening = true
        
        // Speech analysis would happen here
        try? await Task.sleep(for: .seconds(2))
        
        isListening = false
        
        // Phase 2: Analyze
        dockManager.updateSpeakOnlyPhase(.analyzing)
        try? await Task.sleep(for: .milliseconds(500))
        
        // Phase 3: Show score
        let score = Double.random(in: 0.6...1.0) // Simulated
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
        
        // Update affirmation stats
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            recordResonanceScore(record, for: affirmation)
        }
        
        // Auto-advance if score meets threshold
        try? await Task.sleep(for: .seconds(1.5))
        
        if score >= autoAdvanceThreshold && canGoNext {
            nextAffirmation()
        }
    }
    
    // MARK: - Engagement
    
    /// Toggles favorite status for the current affirmation.
    @MainActor
    func toggleFavorite() {
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        HapticFeedback.selection()
        recordInteraction()
    }
    
    /// Shares the current affirmation (placeholder for future).
    func shareAffirmation() {
        // TODO: Implement sharing in future phase
        // For now, this is a no-op
        recordInteraction()
    }
    
    // MARK: - Helpers
    
    /// Records a user interaction (resets timeout).
    func recordInteraction() {
        lastInteractionTime = Date()
    }
    
    /// Records a resonance score for an affirmation.
    private func recordResonanceScore(_ record: ResonanceRecord, for affirmation: Affirmation) {
        affirmation.resonanceScores.append(record)
    }
    
    /// Handles an error by setting the error state.
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
    
    /// Dismisses the current error.
    func dismissError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - Previews

#Preview("Practice ViewModel") {
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
                
                Text("Mode: \(viewModel.currentMode.displayName)")
                Text("Index: \(viewModel.currentIndex + 1) / \(viewModel.affirmations.count)")
                
                HStack {
                    Button("Previous") {
                        viewModel.previousAffirmation()
                    }
                    .disabled(!viewModel.canGoPrevious)
                    
                    Button("Next") {
                        viewModel.nextAffirmation()
                    }
                    .disabled(!viewModel.canGoNext)
                }
            }
            .padding()
            .onAppear {
                viewModel.affirmations = Affirmation.samples
                viewModel.dockManager.updateProgress(
                    current: 0,
                    total: viewModel.affirmations.count
                )
            }
        }
    }
    return PreviewWrapper()
}
