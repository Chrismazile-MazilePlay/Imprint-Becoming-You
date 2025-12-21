//
//  SessionViewModel.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

// MARK: - SessionViewModel

/// ViewModel managing the main affirmation practice session.
///
/// Handles:
/// - Affirmation loading and navigation
/// - Session mode and binaural beat control
/// - Speech analysis coordination
/// - Resonance score tracking
/// - Inactivity timeout detection
///
/// ## Usage
/// ```swift
/// @State private var viewModel = SessionViewModel()
/// SessionContainerView()
///     .environment(viewModel)
/// ```
@Observable
final class SessionViewModel {
    
    // MARK: - Properties
    
    /// Current affirmations in the session
    var affirmations: [Affirmation] = []
    
    /// Index of currently displayed affirmation
    var currentIndex: Int = 0
    
    /// Current session mode
    var sessionMode: SessionMode = .readOnly
    
    /// Current binaural beat preset
    var binauralPreset: BinauralPreset = .off
    
    /// Current session status
    var sessionStatus: SessionStatus = .idle
    
    /// Current phase within an affirmation
    var affirmationPhase: AffirmationPhase = .displaying
    
    /// Real-time resonance score during speech
    var realtimeScore: Float = 0
    
    /// Last completed resonance record
    var lastResonanceRecord: ResonanceRecord?
    
    /// Recognized text during speech
    var recognizedText: String = ""
    
    /// Whether silence has been detected
    var silenceDetected: Bool = false
    
    /// Whether the inactivity popup should show
    var showInactivityPopup: Bool = false
    
    /// Countdown seconds for inactivity popup
    var inactivityCountdown: Int = 10
    
    /// Whether settings sheet is presented
    var showSettings: Bool = false
    
    /// Whether mode selector is expanded
    var showModeSelector: Bool = false
    
    /// Error message to display
    var errorMessage: String?
    
    /// Whether an error alert should be shown
    var showError: Bool = false
    
    /// Audio level for visualization (0.0 - 1.0)
    var audioLevel: Float = 0
    
    /// Whether TTS is currently speaking
    var isSpeaking: Bool = false
    
    /// Whether we're listening to user speech
    var isListening: Bool = false
    
    // MARK: - Private Properties
    
    /// Timer for inactivity detection
    private var inactivityTimer: Timer?
    
    /// Timer for countdown popup
    private var countdownTimer: Timer?
    
    /// Last interaction timestamp
    private var lastInteractionTime: Date = Date()
    
    /// User's calibration data
    private var calibrationData: CalibrationData?
    
    // MARK: - Computed Properties
    
    /// Current affirmation being displayed
    var currentAffirmation: Affirmation? {
        guard currentIndex >= 0, currentIndex < affirmations.count else { return nil }
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
    
    /// Progress through current batch (0.0 - 1.0)
    var batchProgress: Float {
        guard !affirmations.isEmpty else { return 0 }
        return Float(currentIndex + 1) / Float(affirmations.count)
    }
    
    /// Whether the current mode uses microphone
    var requiresMicrophone: Bool {
        sessionMode.usesAudioInput
    }
    
    /// Whether the current mode uses TTS
    var requiresTTS: Bool {
        sessionMode.usesAudioOutput
    }
    
    /// Category of current affirmation
    var currentCategory: GoalCategory? {
        currentAffirmation?.goalCategory
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Session Lifecycle
    
    /// Starts a new session with the given affirmations
    @MainActor
    func startSession(
        affirmations: [Affirmation],
        mode: SessionMode,
        binauralPreset: BinauralPreset,
        calibrationData: CalibrationData?,
        audioService: any AudioServiceProtocol
    ) async {
        self.affirmations = affirmations
        self.sessionMode = mode
        self.binauralPreset = binauralPreset
        self.calibrationData = calibrationData
        self.currentIndex = 0
        self.sessionStatus = .active
        self.lastInteractionTime = Date()
        
        // Start binaural beats if enabled
        if binauralPreset != .off {
            do {
                try await audioService.startBinauralBeats(preset: binauralPreset)
            } catch {
                handleError(error)
            }
        }
        
        // Start inactivity monitoring only for modes that require user speech
        // Read Only and Read Aloud don't need monitoring - user swipes at own pace
        if mode.usesAudioInput {
            startInactivityMonitoring()
        }
        
        // Begin first affirmation
        await beginAffirmation()
    }
    
    /// Ends the current session
    @MainActor
    func endSession(audioService: any AudioServiceProtocol) async {
        sessionStatus = .completed
        stopInactivityMonitoring()
        
        await audioService.stop()
    }
    
    /// Pauses the session
    func pauseSession() {
        sessionStatus = .paused
        stopInactivityMonitoring()
    }
    
    /// Resumes the session
    func resumeSession() {
        sessionStatus = .active
        lastInteractionTime = Date()
        
        // Only restart monitoring for speaking modes
        if sessionMode.usesAudioInput {
            startInactivityMonitoring()
        }
    }
    
    // MARK: - Navigation
    
    /// Moves to the next affirmation
    @MainActor
    func nextAffirmation() async {
        guard canGoNext else { return }
        
        recordInteraction()
        currentIndex += 1
        await beginAffirmation()
    }
    
    /// Moves to the previous affirmation
    @MainActor
    func previousAffirmation() async {
        guard canGoPrevious else { return }
        
        recordInteraction()
        currentIndex -= 1
        await beginAffirmation()
    }
    
    /// Jumps to a specific affirmation index
    @MainActor
    func goToAffirmation(at index: Int) async {
        guard index >= 0, index < affirmations.count else { return }
        
        recordInteraction()
        currentIndex = index
        await beginAffirmation()
    }
    
    // MARK: - Affirmation Flow
    
    /// Begins the current affirmation based on session mode
    @MainActor
    private func beginAffirmation() async {
        guard let affirmation = currentAffirmation else { return }
        
        // Mark as seen
        affirmation.hasBeenSeen = true
        
        // Reset state
        affirmationPhase = .displaying
        realtimeScore = 0
        recognizedText = ""
        silenceDetected = false
        lastResonanceRecord = nil
        
        // Handle based on mode
        switch sessionMode {
        case .readOnly:
            // Just display, user swipes manually
            affirmationPhase = .displaying
            
        case .readAloud:
            // TTS speaks, then auto-advance
            affirmationPhase = .speaking
            // TTS will be triggered by the view
            
        case .readThenSpeak:
            // TTS speaks first, then listen
            affirmationPhase = .speaking
            // After TTS, transition to .listening
            
        case .speakOnly:
            // Go straight to listening
            affirmationPhase = .listening
        }
    }
    
    /// Called when TTS finishes speaking
    @MainActor
    func onTTSComplete() async {
        isSpeaking = false
        
        switch sessionMode {
        case .readAloud:
            // Auto-advance after delay
            try? await Task.sleep(for: .seconds(1))
            if canGoNext {
                await nextAffirmation()
            } else {
                sessionStatus = .completed
            }
            
        case .readThenSpeak:
            // Transition to listening
            affirmationPhase = .listening
            
        default:
            break
        }
    }
    
    /// Called when speech analysis completes
    @MainActor
    func onSpeechAnalysisComplete(record: ResonanceRecord?) {
        isListening = false
        affirmationPhase = .showingScore
        
        if let record = record {
            lastResonanceRecord = record
            
            // Save to affirmation
            currentAffirmation?.resonanceScores.append(record)
            currentAffirmation?.lastPracticedAt = Date()
        }
    }
    
    /// Updates real-time score during analysis
    func updateRealtimeScore(_ score: Float) {
        realtimeScore = score
    }
    
    /// Updates recognized text during analysis
    func updateRecognizedText(_ text: String) {
        recognizedText = text
    }
    
    /// Updates silence detection state
    func updateSilenceDetected(_ detected: Bool) {
        silenceDetected = detected
    }
    
    // MARK: - Mode & Settings
    
    /// Changes the session mode
    @MainActor
    func changeMode(_ mode: SessionMode) {
        let previousMode = sessionMode
        sessionMode = mode
        recordInteraction()
        
        // Update inactivity monitoring based on new mode
        if mode.usesAudioInput && !previousMode.usesAudioInput {
            // Switched to a speaking mode - start monitoring
            startInactivityMonitoring()
        } else if !mode.usesAudioInput && previousMode.usesAudioInput {
            // Switched away from speaking mode - stop monitoring
            stopInactivityMonitoring()
        }
    }
    
    /// Changes the binaural preset
    @MainActor
    func changeBinauralPreset(_ preset: BinauralPreset, audioService: any AudioServiceProtocol) async {
        binauralPreset = preset
        recordInteraction()
        
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
    
    // MARK: - Inactivity Handling
    
    /// Records user interaction to reset inactivity timer
    func recordInteraction() {
        lastInteractionTime = Date()
        
        // Dismiss popup if showing
        if showInactivityPopup {
            dismissInactivityPopup()
        }
    }
    
    /// Starts monitoring for inactivity
    private func startInactivityMonitoring() {
        stopInactivityMonitoring()
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkInactivity()
        }
    }
    
    /// Stops inactivity monitoring
    private func stopInactivityMonitoring() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    /// Checks for inactivity timeout
    private func checkInactivity() {
        guard sessionStatus == .active else { return }
        guard !showInactivityPopup else { return }
        
        // Only check inactivity for modes that require user speech
        guard sessionMode.usesAudioInput else { return }
        
        let elapsed = Date().timeIntervalSince(lastInteractionTime)
        
        if elapsed >= Constants.Session.inactivityTimeout {
            showInactivityPopup = true
            inactivityCountdown = Int(Constants.Session.popupCountdownDuration)
            startCountdown()
        }
    }
    
    /// Starts the countdown timer
    private func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.inactivityCountdown -= 1
            
            if self.inactivityCountdown <= 0 {
                self.countdownTimer?.invalidate()
                self.sessionStatus = .paused
                self.showInactivityPopup = false
            }
        }
    }
    
    /// Dismisses the inactivity popup
    func dismissInactivityPopup() {
        showInactivityPopup = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        lastInteractionTime = Date()
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        if let appError = error as? AppError {
            errorMessage = appError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }
    
    func dismissError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - SessionStatus

/// Current status of the practice session (UI state)
enum SessionStatus: Sendable {
    /// No active session
    case idle
    
    /// Session is active
    case active
    
    /// Session is paused
    case paused
    
    /// Session completed
    case completed
}

// MARK: - AffirmationPhase

/// Current phase within a single affirmation
enum AffirmationPhase: Sendable {
    /// Displaying the affirmation text
    case displaying
    
    /// TTS is speaking the affirmation
    case speaking
    
    /// Listening to user speech
    case listening
    
    /// Showing the resonance score
    case showingScore
}
