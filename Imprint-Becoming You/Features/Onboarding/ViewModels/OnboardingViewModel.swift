//
//  OnboardingViewModel.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData
import SwiftUI
import Observation
import AVFoundation

// MARK: - OnboardingViewModel

/// ViewModel managing the onboarding flow state and logic.
///
/// Handles:
/// - Navigation between onboarding steps
/// - Faith preference selection
/// - Goal selection validation
/// - Voice selection with tap-to-select + preview
/// - Voice calibration coordination
/// - Profile updates on completion
///
/// ## Onboarding Flow
/// 1. Welcome - Introduction to the app
/// 2. Faith Preference - Choose to include Biblical content
/// 3. Goal Selection - Select up to 5 focus areas
/// 4. Voice Selection - Choose TTS voice (tap to select + preview)
/// 5. Calibration - Voice setup (optional)
/// 6. Complete - Ready to practice
@MainActor
@Observable
final class OnboardingViewModel {
    
    // MARK: - Properties
    
    /// Current step in the onboarding flow
    var currentStep: OnboardingStep = .welcome
    
    /// Whether user wants faith-based content included.
    /// `nil` means no choice has been made yet.
    var includeFaithContent: Bool? = nil
    
    /// Selected goal categories
    var selectedGoals: Set<GoalCategory> = []
    
    /// Whether calibration is in progress
    var isCalibrating: Bool = false
    
    /// Calibration progress (0.0 - 1.0)
    var calibrationProgress: Float = 0
    
    /// Current calibration phrase being spoken
    var currentCalibrationPhrase: String = ""
    
    /// Calibration result after completion
    var calibrationData: CalibrationData?
    
    /// Whether the user chose to skip calibration
    var skippedCalibration: Bool = false
    
    /// Error message to display
    var errorMessage: String?
    
    /// Whether an error alert should be shown
    var showError: Bool = false
    
    /// Whether we're saving/completing
    var isCompleting: Bool = false
    
    // MARK: - Voice Selection State
    
    /// Currently selected voice ID (full Voice.id format, e.g., "kokoro_af_heart")
    var selectedVoiceId: String = Voice.defaultVoice.id
    
    /// Voice currently being previewed (by full Voice.id)
    var previewingVoiceId: String?
    
    /// Whether voice preview is currently playing
    var isPreviewPlaying: Bool = false
    
    /// TTS service for voice preview (injected by view)
    var ttsService: (any TTSServiceProtocol)?
    
    /// Voice preview cache service (injected by view)
    var voicePreviewCacheService: (any VoicePreviewCacheServiceProtocol)?
    
    /// Audio player for cached preview playback
    private var audioPlayer: AVAudioPlayer?
    
    // MARK: - Computed Properties
    
    /// Maximum goals allowed (from Constants)
    var maxGoals: Int {
        Constants.FreeTier.maxGoals
    }
    
    /// Whether user has made a faith preference choice
    var hasMadeFaithChoice: Bool {
        includeFaithContent != nil
    }
    
    /// Whether the user can proceed from faith preference step
    var canProceedFromFaithPreference: Bool {
        hasMadeFaithChoice
    }
    
    /// Whether the user can proceed from goal selection
    var canProceedFromGoals: Bool {
        !selectedGoals.isEmpty && selectedGoals.count <= maxGoals
    }
    
    /// Progress through onboarding (0.0 - 1.0)
    var overallProgress: Float {
        Float(currentStep.rawValue) / Float(OnboardingStep.allCases.count - 1)
    }
    
    /// Whether we can go back from current step
    var canGoBack: Bool {
        currentStep != .welcome
    }
    
    /// Available goal groups based on faith preference
    var availableGoalGroups: [GoalGroup] {
        if includeFaithContent == false {
            return GoalGroup.allCases.filter { $0 != .faithBased }
        }
        return GoalGroup.allCases
    }
    
    /// Faith-based categories for preview display
    var faithCategories: [GoalCategory] {
        GoalGroup.faithBased.categories
    }
    
    /// The currently selected Voice object
    var selectedVoice: Voice {
        Voice.voice(forId: selectedVoiceId)
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Navigation
    
    /// Advances to the next step
    func nextStep() {
        guard let nextIndex = OnboardingStep.allCases.firstIndex(of: currentStep)?.advanced(by: 1),
              nextIndex < OnboardingStep.allCases.count else {
            return
        }
        
        withAnimation {
            currentStep = OnboardingStep.allCases[nextIndex]
        }
    }
    
    /// Goes back to the previous step
    func previousStep() {
        guard let prevIndex = OnboardingStep.allCases.firstIndex(of: currentStep)?.advanced(by: -1),
              prevIndex >= 0 else {
            return
        }
        
        withAnimation {
            currentStep = OnboardingStep.allCases[prevIndex]
        }
    }
    
    /// Jumps to a specific step
    func goToStep(_ step: OnboardingStep) {
        withAnimation {
            currentStep = step
        }
    }
    
    // MARK: - Faith Preference
    
    /// Sets the user's faith content preference.
    func setFaithPreference(_ include: Bool) {
        withAnimation(AppTheme.Animation.quick) {
            includeFaithContent = include
        }
        
        // If user opts out of faith content, remove any faith goals they may have selected
        if !include {
            selectedGoals = selectedGoals.filter { !$0.isFaithBased }
        }
        
        HapticFeedback.selection()
    }
    
    // MARK: - Goal Selection
    
    /// Toggles selection of a goal category
    func toggleGoal(_ goal: GoalCategory) {
        if goal.isFaithBased && includeFaithContent == false {
            return
        }
        
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else if selectedGoals.count < maxGoals {
            selectedGoals.insert(goal)
        }
    }
    
    /// Whether a specific goal is selected
    func isGoalSelected(_ goal: GoalCategory) -> Bool {
        selectedGoals.contains(goal)
    }
    
    /// Clears all selected goals
    func clearGoals() {
        selectedGoals.removeAll()
    }
    
    // MARK: - Voice Selection
    
    /// Selects a voice and plays its preview.
    ///
    /// - Parameter voiceId: The full voice ID (e.g., "kokoro_af_heart")
    func selectVoice(_ voiceId: String) {
        // Stop any current preview
        stopPreview()
        
        // Select the voice
        selectedVoiceId = voiceId
        
        // Haptic feedback
        HapticFeedback.selection()
        
        // Play preview
        playPreview(for: voiceId)
        
        #if DEBUG
        print("🎤 OnboardingViewModel: Selected voice \(voiceId)")
        #endif
    }
    
    /// Plays preview audio for a voice.
    ///
    /// Uses cached audio if available, otherwise synthesizes on-demand.
    /// CRITICAL: Captures voiceId before async work to prevent race conditions.
    private func playPreview(for voiceId: String) {
        // Get the raw TTS voice ID (e.g., "af_heart" from "kokoro_af_heart")
        guard let ttsVoiceId = Voice.ttsVoiceId(from: voiceId) else {
            #if DEBUG
            print("⚠️ OnboardingViewModel: Could not get ttsVoiceId for \(voiceId)")
            #endif
            return
        }
        
        // Set preview state BEFORE async work
        previewingVoiceId = voiceId
        isPreviewPlaying = true
        
        // Capture values for closure to prevent race conditions
        let capturedVoiceId = voiceId
        let capturedTtsVoiceId = ttsVoiceId
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Verify we're still previewing this voice (user might have tapped another)
            guard self.previewingVoiceId == capturedVoiceId else {
                #if DEBUG
                print("🎤 OnboardingViewModel: Voice changed, skipping preview for \(capturedVoiceId)")
                #endif
                return
            }
            
            do {
                // Try to get cached audio first
                if let cache = self.voicePreviewCacheService,
                   let audioData = cache.getPreviewAudio(for: capturedTtsVoiceId) {
                    // Play from cache using AVAudioPlayer
                    #if DEBUG
                    print("🎤 OnboardingViewModel: Playing cached audio for \(capturedTtsVoiceId)")
                    #endif
                    try self.playAudioData(audioData)
                    
                } else if let cache = self.voicePreviewCacheService {
                    // Synthesize on-demand, cache it, then play
                    #if DEBUG
                    print("🎤 OnboardingViewModel: Synthesizing on-demand for \(capturedTtsVoiceId)")
                    #endif
                    let audioData = try await cache.synthesizeNow(capturedTtsVoiceId)
                    
                    // Verify still previewing same voice
                    guard self.previewingVoiceId == capturedVoiceId else { return }
                    
                    try self.playAudioData(audioData)
                    
                } else if let tts = self.ttsService {
                    // Fallback to direct TTS synthesis
                    #if DEBUG
                    print("🎤 OnboardingViewModel: Fallback to TTS for \(capturedTtsVoiceId)")
                    #endif
                    try await tts.speakText(Voice.previewPhrase, voiceId: capturedTtsVoiceId)
                }
            } catch {
                #if DEBUG
                print("⚠️ OnboardingViewModel: Voice preview failed for \(capturedTtsVoiceId): \(error)")
                #endif
            }
            
            // Only clear state if we're still previewing the same voice
            if self.previewingVoiceId == capturedVoiceId {
                self.isPreviewPlaying = false
                self.previewingVoiceId = nil
            }
        }
    }
    
    /// Plays audio data using AVAudioPlayer.
    ///
    /// - Parameter data: WAV audio data to play
    /// - Throws: Error if audio playback fails
    private func playAudioData(_ data: Data) throws {
        // Stop any existing playback
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        
        // Create and configure player
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        
        guard audioPlayer?.play() == true else {
            throw AppError.ttsError("Failed to start audio playback")
        }
        
        #if DEBUG
        print("🎤 OnboardingViewModel: Playing audio (\(data.count) bytes)")
        #endif
    }
    
    /// Stops any currently playing voice preview.
    func stopPreview() {
        // Stop AVAudioPlayer
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Stop TTS service
        ttsService?.stopSpeaking()
        
        // Clear state
        isPreviewPlaying = false
        previewingVoiceId = nil
    }
    
    // MARK: - Calibration
    
    /// Starts voice calibration
    func startCalibration(speechService: any SpeechAnalysisServiceProtocol) async {
        isCalibrating = true
        calibrationProgress = 0
        errorMessage = nil
        
        do {
            let hasMic = await speechService.requestMicrophonePermission()
            guard hasMic else {
                throw AppError.microphoneAccessDenied
            }
            
            let phrases = VoiceCalibrationService.defaultCalibrationPhrases
            calibrationData = try await speechService.performCalibration(with: phrases)
            
            isCalibrating = false
            nextStep()
            
        } catch {
            isCalibrating = false
            handleError(error)
        }
    }
    
    /// Skips calibration
    func skipCalibration() {
        skippedCalibration = true
        calibrationData = nil
        nextStep()
    }
    
    // MARK: - Completion
    
    /// Completes onboarding and saves to profile
    func completeOnboarding(
        modelContext: ModelContext,
        appState: AppState
    ) async {
        isCompleting = true
        
        do {
            let descriptor = FetchDescriptor<UserProfile>()
            let profiles = try modelContext.fetch(descriptor)
            
            guard let profile = profiles.first else {
                throw AppError.loadFailed(reason: "No user profile found")
            }
            
            profile.selectedGoals = selectedGoals.map { $0.rawValue }
            profile.goalsLastChangedAt = Date()
            profile.calibrationData = calibrationData
            profile.hasCompletedOnboarding = true
            profile.includeFaithContent = includeFaithContent
            profile.selectedVoiceId = selectedVoiceId
            
            try modelContext.save()
            appState.updateProfile(profile)
            
            isCompleting = false
            
        } catch {
            isCompleting = false
            handleError(error)
        }
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

// MARK: - OnboardingStep

/// Steps in the onboarding flow
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case faithPreference = 1
    case goalSelection = 2
    case voiceSelection = 3
    case calibration = 4
    case complete = 5
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .faithPreference: return "Faith Content"
        case .goalSelection: return "Your Goals"
        case .voiceSelection: return "Your Voice"
        case .calibration: return "Voice Setup"
        case .complete: return "You're Ready"
        }
    }
    
    var isSkippable: Bool {
        switch self {
        case .calibration: return true
        default: return false
        }
    }
}
