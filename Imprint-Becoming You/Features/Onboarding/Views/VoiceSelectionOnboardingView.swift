//
//  VoiceSelectionOnboardingView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import SwiftUI

// MARK: - Voice Selection Onboarding View

/// Voice selection step in the onboarding flow.
///
/// Features:
/// - Tap to select voice (selection is separate from preview)
/// - Tap play button to preview voice
/// - Shows all 26 English voices grouped by accent/gender
/// - Responsive cancellation on rapid tap-through
struct VoiceSelectionOnboardingView: View {
    
    // MARK: - Environment
    
    @Environment(\.dependencies) private var dependencies
    
    // MARK: - Properties
    
    @Bindable var viewModel: OnboardingViewModel
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Voice groups
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.xl) {
                    ForEach(Voice.englishVoicesByDisplayGroup, id: \.group) { groupData in
                        voiceGroupSection(group: groupData.group, voices: groupData.voices)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.lg)
            }
            
            // Continue button
            continueButton
        }
        .onAppear {
            injectDependencies()
        }
        .onDisappear {
            viewModel.stopPreview()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text("Choose Your Voice")
                .font(AppTypography.title1)
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Tap a voice to select, tap play to preview")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.lg)
    }
    
    // MARK: - Voice Group Section
    
    private func voiceGroupSection(group: VoiceDisplayGroup, voices: [Voice]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Group header
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: group.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                
                Text(group.displayName)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.leading, AppTheme.Spacing.xs)
            
            // Voice chips
            VStack(spacing: AppTheme.Spacing.sm) {
                ForEach(voices) { voice in
                    VoiceChip(
                        voice: voice,
                        isSelected: viewModel.selectedVoiceId == voice.id,
                        playbackState: viewModel.playbackStateFor(voice),
                        onPlayTapped: { viewModel.handlePlayTapped(voice) },
                        onSelectTapped: { viewModel.handleSelectTapped(voice) }
                    )
                }
            }
        }
    }
    
    // MARK: - Continue Button
    
    private var continueButton: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Selected voice display
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.accent)
                
                Text("Selected: \(viewModel.selectedVoice.name)")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            // Continue button
            Button {
                viewModel.stopPreview()
                viewModel.nextStep()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, AppTheme.Spacing.xl)
    }
    
    // MARK: - Helpers
    
    /// Injects dependencies into the view model.
    private func injectDependencies() {
        viewModel.ttsService = dependencies.ttsService
        viewModel.voicePreviewCacheService = dependencies.voicePreviewCacheService
    }
}

// MARK: - Previews

#Preview("Voice Selection - Onboarding") {
    VoiceSelectionOnboardingView(viewModel: OnboardingViewModel())
        .background(AppColors.backgroundPrimary)
        .previewEnvironment()
}

#Preview("Voice Selection - With Selection") {
    let vm = OnboardingViewModel()
    vm.selectedVoiceId = "kokoro_af_bella"
    
    return VoiceSelectionOnboardingView(viewModel: vm)
        .background(AppColors.backgroundPrimary)
        .previewEnvironment()
}
