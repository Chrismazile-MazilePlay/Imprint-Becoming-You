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

// MARK: - OnboardingViewModel

/// ViewModel managing the onboarding flow state and logic.
///
/// Handles:
/// - Navigation between onboarding steps
/// - Goal selection validation
/// - Voice calibration coordination
/// - Profile updates on completion
///
/// ## Usage
/// ```swift
/// @State private var viewModel = OnboardingViewModel()
/// OnboardingContainerView()
///     .environment(viewModel)
/// ```
@Observable
final class OnboardingViewModel {
    
    // MARK: - Properties
    
    /// Current step in the onboarding flow
    var currentStep: OnboardingStep = .welcome
    
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
    
    // MARK: - Computed Properties
    
    /// Maximum goals allowed (from Constants)
    var maxGoals: Int {
        Constants.FreeTier.maxGoals
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
    
    // MARK: - Goal Selection
    
    /// Toggles selection of a goal category
    /// - Parameter goal: Goal to toggle
    func toggleGoal(_ goal: GoalCategory) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else if selectedGoals.count < maxGoals {
            selectedGoals.insert(goal)
        }
        // If already at max, don't add more
    }
    
    /// Whether a specific goal is selected
    func isGoalSelected(_ goal: GoalCategory) -> Bool {
        selectedGoals.contains(goal)
    }
    
    /// Clears all selected goals
    func clearGoals() {
        selectedGoals.removeAll()
    }
    
    // MARK: - Calibration
    
    /// Starts voice calibration
    /// - Parameter speechService: The speech analysis service to use
    @MainActor
    func startCalibration(speechService: any SpeechAnalysisServiceProtocol) async {
        isCalibrating = true
        calibrationProgress = 0
        errorMessage = nil
        
        do {
            // Request permissions first
            let hasMic = await speechService.requestMicrophonePermission()
            guard hasMic else {
                throw AppError.microphoneAccessDenied
            }
            
            // Use default calibration phrases
            let phrases = VoiceCalibrationService.defaultCalibrationPhrases
            
            // Perform calibration
            calibrationData = try await speechService.performCalibration(with: phrases)
            
            // Success - move to next step
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
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - appState: App state to update
    @MainActor
    func completeOnboarding(
        modelContext: ModelContext,
        appState: AppState
    ) async {
        isCompleting = true
        
        do {
            // Fetch user profile
            let descriptor = FetchDescriptor<UserProfile>()
            let profiles = try modelContext.fetch(descriptor)
            
            guard let profile = profiles.first else {
                throw AppError.loadFailed(reason: "No user profile found")
            }
            
            // Update profile
            profile.selectedGoals = selectedGoals.map { $0.rawValue }
            profile.goalsLastChangedAt = Date()
            profile.calibrationData = calibrationData
            profile.hasCompletedOnboarding = true
            
            // Save
            try modelContext.save()
            
            // Update app state
            appState.updateProfile(profile)
            
            isCompleting = false
            
        } catch {
            isCompleting = false
            handleError(error)
        }
    }
    
    // MARK: - Error Handling
    
    /// Handles errors from async operations
    private func handleError(_ error: Error) {
        if let appError = error as? AppError {
            errorMessage = appError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }
    
    /// Dismisses the current error
    func dismissError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - OnboardingStep

/// Steps in the onboarding flow
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome = 0
    case goalSelection = 1
    case calibration = 2
    case complete = 3
    
    var id: Int { rawValue }
    
    /// Title for the step
    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .goalSelection:
            return "Your Goals"
        case .calibration:
            return "Voice Setup"
        case .complete:
            return "You're Ready"
        }
    }
    
    /// Whether this step can be skipped
    var isSkippable: Bool {
        switch self {
        case .calibration:
            return true
        default:
            return false
        }
    }
}

// MARK: - Animation Helper

private func animateStateChange(_ action: () -> Void) {
    withAnimation(AppTheme.Animation.standard) {
        action()
    }
}
