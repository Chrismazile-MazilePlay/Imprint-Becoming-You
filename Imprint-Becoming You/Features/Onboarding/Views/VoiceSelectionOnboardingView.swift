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
/// - Tap to select and preview voice
/// - Shows all 26 English voices grouped by accent/gender
/// - Loading indicator for voices not yet cached
/// - Instant playback from cache when available
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
            
            Text("Tap any voice to hear it")
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
            
            // Voice chips in flow layout
            FlowLayout(spacing: AppTheme.Spacing.sm) {
                ForEach(voices) { voice in
                    voiceChip(voice: voice)
                }
            }
        }
    }
    
    // MARK: - Voice Chip
    
    private func voiceChip(voice: Voice) -> some View {
        let isSelected = viewModel.selectedVoiceId == voice.id
        let isPreviewing = viewModel.previewingVoiceId == voice.id && viewModel.isPreviewPlaying
        let isCached = isVoiceCached(voice)
        
        return Button {
            viewModel.selectVoice(voice.id)
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                // Voice name
                Text(voice.displayNameWithDefault)
                    .font(AppTypography.body)
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textPrimary)
                
                // Status indicator
                Group {
                    if isPreviewing {
                        // Playing animation
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.accent)
                            .symbolEffect(.pulse, options: .repeating)
                    } else if isSelected {
                        // Selected checkmark
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                    } else if !isCached {
                        // Not cached indicator (subtle)
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(AppColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AppColors.accent.opacity(0.15) : AppColors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(voice.name) voice")
        .accessibilityHint(isSelected ? "Selected. Tap to preview" : "Tap to select and preview")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    
    /// Checks if a voice preview is cached.
    private func isVoiceCached(_ voice: Voice) -> Bool {
        guard let ttsVoiceId = voice.ttsVoiceId else { return true }
        return viewModel.voicePreviewCacheService?.isReady(ttsVoiceId) ?? true
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
