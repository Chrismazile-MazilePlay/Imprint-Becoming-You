//
//  VoiceCalibrationView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import SwiftUI

// MARK: - VoiceCalibrationView

/// Voice calibration screen where users speak sample affirmations.
///
/// Features:
/// - Animated microphone visualization
/// - Progress through calibration phrases
/// - Real-time audio level indicator
/// - Option to skip calibration
struct VoiceCalibrationView: View {
    
    // MARK: - Environment
    
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - State
    
    @State private var audioLevel: Float = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var isAnimating: Bool = false
    @State private var currentPhraseIndex: Int = 0
    @State private var showPermissionAlert: Bool = false
    
    // MARK: - Constants
    
    private let phrases = VoiceCalibrationService.defaultCalibrationPhrases
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Let's Learn Your Voice")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Read each affirmation aloud so we can personalize your experience")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            
            Spacer()
            
            // Calibration content
            if viewModel.isCalibrating {
                CalibrationInProgressView(
                    currentPhrase: phrases[safe: currentPhraseIndex] ?? "",
                    phraseIndex: currentPhraseIndex,
                    totalPhrases: phrases.count,
                    audioLevel: audioLevel,
                    isAnimating: $isAnimating,
                    pulseScale: $pulseScale
                )
            } else {
                CalibrationReadyView(
                    onStart: startCalibration
                )
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: AppTheme.Spacing.md) {
                if !viewModel.isCalibrating {
                    Button {
                        startCalibration()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "mic.fill")
                            Text("Start Calibration")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    
                    Button {
                        viewModel.skipCalibration()
                    } label: {
                        Text("Skip for Now")
                    }
                    .buttonStyle(.ghost)
                } else {
                    // Cancel button during calibration
                    Button {
                        cancelCalibration()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.ghost)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .alert("Microphone Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                openSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Imprint needs microphone access to calibrate your voice. Please enable it in Settings.")
        }
    }
    
    // MARK: - Actions
    
    private func startCalibration() {
        Task {
            await viewModel.startCalibration(
                speechService: dependencies.speechAnalysisService
            )
        }
    }
    
    private func cancelCalibration() {
        viewModel.isCalibrating = false
        isAnimating = false
        currentPhraseIndex = 0
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - CalibrationReadyView

/// View shown before calibration starts
struct CalibrationReadyView: View {
    
    let onStart: () -> Void
    
    @State private var iconScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            // Microphone icon
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .scaleEffect(iconScale)
                
                Circle()
                    .fill(AppColors.accent.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(AppColors.accent)
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    iconScale = 1.1
                }
            }
            
            // Instructions
            VStack(spacing: AppTheme.Spacing.md) {
                InstructionRow(
                    number: 1,
                    text: "Find a quiet space"
                )
                
                InstructionRow(
                    number: 2,
                    text: "Speak naturally and clearly"
                )
                
                InstructionRow(
                    number: 3,
                    text: "Read 5 short affirmations"
                )
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
        }
    }
}

// MARK: - InstructionRow

/// Numbered instruction row
struct InstructionRow: View {
    
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Number badge
            Text("\(number)")
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.backgroundPrimary)
                .frame(width: 28, height: 28)
                .background(AppColors.accent, in: Circle())
            
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
        }
    }
}

// MARK: - CalibrationInProgressView

/// View shown during active calibration
struct CalibrationInProgressView: View {
    
    let currentPhrase: String
    let phraseIndex: Int
    let totalPhrases: Int
    let audioLevel: Float
    
    @Binding var isAnimating: Bool
    @Binding var pulseScale: CGFloat
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            // Progress indicator
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(0..<totalPhrases, id: \.self) { index in
                    Circle()
                        .fill(index <= phraseIndex ? AppColors.accent : AppColors.surfaceTertiary)
                        .frame(width: 8, height: 8)
                }
            }
            
            Text("Phrase \(phraseIndex + 1) of \(totalPhrases)")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
            
            // Animated microphone
            ZStack {
                // Pulse rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(AppColors.accent.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                        .frame(width: 120 + CGFloat(i * 30), height: 120 + CGFloat(i * 30))
                        .scaleEffect(pulseScale + CGFloat(i) * 0.1)
                }
                
                // Audio level ring
                Circle()
                    .fill(AppColors.accent.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .scaleEffect(1.0 + CGFloat(audioLevel) * 0.5)
                
                // Microphone icon
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppColors.backgroundPrimary)
                    )
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    pulseScale = 1.15
                }
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
                pulseScale = 1.0
            }
            
            // Current phrase to speak
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("Say:")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
                
                Text("\"\(currentPhrase)\"")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
        }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Previews

#Preview("Voice Calibration - Ready") {
    VoiceCalibrationView(viewModel: OnboardingViewModel())
        .background(AppColors.backgroundPrimary)
        .previewEnvironment()
}

#Preview("Voice Calibration - In Progress") {
    let vm = OnboardingViewModel()
    vm.isCalibrating = true
    
    return VoiceCalibrationView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
        .previewEnvironment()
}

#Preview("Calibration Ready View") {
    CalibrationReadyView(onStart: {})
        .background(AppColors.backgroundPrimary)
}

#Preview("Calibration In Progress") {
    CalibrationInProgressView(
        currentPhrase: "I am confident and capable.",
        phraseIndex: 2,
        totalPhrases: 5,
        audioLevel: 0.5,
        isAnimating: .constant(true),
        pulseScale: .constant(1.0)
    )
    .background(AppColors.backgroundPrimary)
}
