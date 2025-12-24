//
//  AdaptiveBottomDock.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - AdaptiveBottomDock

/// The morphing bottom dock that adapts its content based on the current mode.
///
/// ## Layout (Active Modes)
/// ```
/// ┌─────────────────────────────────────────────────────┐
/// │  ▓▓▓▓  ▓▓▓▓  ▓▓░░  ░░░░  ░░░░   ← Progress bars    │
/// │                                                     │
/// │  <         ● ● ● ● ● ● ● ● ●         >             │
/// │  ↑              Waveform              ↑             │
/// │  Chevron      (or Score)         Chevron           │
/// │                                                     │
/// │  [🔊 Mode ∧]                [🌙 Binaural ∧]        │
/// └─────────────────────────────────────────────────────┘
/// ```
///
/// ## States
/// - **Home**: Mode selector + Binaural selector only (compact)
/// - **Active**: Progress bars + Waveform/Score + Navigation + Mode controls
struct AdaptiveBottomDock: View {
    
    // MARK: - Properties
    
    @Bindable var viewModel: PracticeViewModel
    
    /// Callback when binaural preset changes
    let onBinauralChange: (BinauralPreset) async -> Void
    
    /// Callback when mode changes
    let onModeChange: (SessionMode) async -> Void
    
    // MARK: - Body
    
    var body: some View {
        let dockManager = viewModel.dockManager
        let currentMode = dockManager.currentMode
        let currentBinaural = dockManager.binauralPreset
        let isModeSelectorExpanded = dockManager.isModeSelectorExpanded
        let isBinauralSelectorExpanded = dockManager.isBinauralSelectorExpanded
        let isActiveMode = dockManager.isInActiveMode
        
        return VStack(spacing: 0) {
            // Expanded selectors (when open)
            expandedSelectors(
                currentMode: currentMode,
                currentBinaural: currentBinaural,
                isModeSelectorExpanded: isModeSelectorExpanded,
                isBinauralSelectorExpanded: isBinauralSelectorExpanded
            )
            
            // Main dock content
            VStack(spacing: AppTheme.Spacing.md) {
                if isActiveMode {
                    activeModeContent(
                        currentMode: currentMode,
                        currentBinaural: currentBinaural,
                        isModeSelectorExpanded: isModeSelectorExpanded,
                        isBinauralSelectorExpanded: isBinauralSelectorExpanded
                    )
                } else {
                    homeModeContent(
                        currentMode: currentMode,
                        currentBinaural: currentBinaural,
                        isModeSelectorExpanded: isModeSelectorExpanded,
                        isBinauralSelectorExpanded: isBinauralSelectorExpanded
                    )
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(dockBackground)
        }
        .animation(AppTheme.Animation.standard, value: currentMode)
        .animation(AppTheme.Animation.standard, value: currentBinaural)
        .animation(AppTheme.Animation.standard, value: isActiveMode)
    }
    
    // MARK: - Dock Background
    
    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
            .fill(AppColors.backgroundSecondary.opacity(0.95))
            .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
    }
    
    // MARK: - Expanded Selectors
    
    @ViewBuilder
    private func expandedSelectors(
        currentMode: SessionMode,
        currentBinaural: BinauralPreset,
        isModeSelectorExpanded: Bool,
        isBinauralSelectorExpanded: Bool
    ) -> some View {
        if isModeSelectorExpanded {
            ModeSelectorExpanded(
                selectedMode: currentMode,
                onSelect: { mode in
                    Task {
                        await onModeChange(mode)
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, AppTheme.Spacing.sm)
        }
        
        if isBinauralSelectorExpanded {
            BinauralSelectorExpanded(
                selectedPreset: currentBinaural,
                onSelect: { preset in
                    Task {
                        await onBinauralChange(preset)
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, AppTheme.Spacing.sm)
        }
    }
    
    // MARK: - Home Mode Content
    
    private func homeModeContent(
        currentMode: SessionMode,
        currentBinaural: BinauralPreset,
        isModeSelectorExpanded: Bool,
        isBinauralSelectorExpanded: Bool
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            DockModeButton(
                mode: currentMode,
                isExpanded: isModeSelectorExpanded
            ) {
                viewModel.dockManager.toggleModeSelector()
                HapticFeedback.impact(.light)
            }
            
            Spacer(minLength: 0)
            
            DockBinauralButton(
                preset: currentBinaural,
                isExpanded: isBinauralSelectorExpanded
            ) {
                viewModel.dockManager.toggleBinauralSelector()
                HapticFeedback.impact(.light)
            }
        }
    }
    
    // MARK: - Active Mode Content
    
    private func activeModeContent(
        currentMode: SessionMode,
        currentBinaural: BinauralPreset,
        isModeSelectorExpanded: Bool,
        isBinauralSelectorExpanded: Bool
    ) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Progress bars (Stories style)
            DockProgressBars(
                current: viewModel.currentIndex,
                total: viewModel.affirmations.count,
                progress: currentProgress,
                isAnimating: isPlayingOrListening
            )
            .padding(.horizontal, AppTheme.Spacing.sm)
            
            // Center content with chevrons
            centerContentRow
            
            // Mode and binaural buttons
            HStack(spacing: AppTheme.Spacing.md) {
                DockModeButton(
                    mode: currentMode,
                    isExpanded: isModeSelectorExpanded,
                    showLabel: true
                ) {
                    viewModel.dockManager.toggleModeSelector()
                    HapticFeedback.impact(.light)
                }
                
                Spacer(minLength: 0)
                
                DockBinauralButton(
                    preset: currentBinaural,
                    isExpanded: isBinauralSelectorExpanded
                ) {
                    viewModel.dockManager.toggleBinauralSelector()
                    HapticFeedback.impact(.light)
                }
            }
        }
    }
    
    // MARK: - Center Content Row (Chevrons + Waveform/Score)
    
    private var centerContentRow: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Left chevron
            Button {
                viewModel.previousAffirmation()
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(viewModel.canGoPrevious ? AppColors.textSecondary : AppColors.textTertiary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canGoPrevious)
            
            Spacer()
            
            // Center content (waveform or score)
            centerContent
            
            Spacer()
            
            // Right chevron
            Button {
                viewModel.nextAffirmation()
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(viewModel.canGoNext ? AppColors.textSecondary : AppColors.textTertiary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canGoNext)
        }
    }
    
    // MARK: - Center Content
    
    @ViewBuilder
    private var centerContent: some View {
        let state = viewModel.dockManager.state
        
        switch state {
        case .home:
            EmptyView()
            
        case .readAloud(let phase):
            switch phase {
            case .idle:
                DockWaveformView(state: .idle)
            case .speaking:
                DockWaveformView(state: .playing, audioLevel: viewModel.audioLevel)
            case .complete:
                DockWaveformView(state: .idle)
            }
            
        case .readAndSpeak(let phase):
            switch phase {
            case .idle:
                DockWaveformView(state: .idle)
            case .ttsPlaying:
                DockWaveformView(state: .playing, audioLevel: viewModel.audioLevel)
            case .waitingForUser:
                DockWaveformView(state: .waiting)
            case .listening:
                DockWaveformView(state: .listening, audioLevel: viewModel.audioLevel)
            case .analyzing:
                DockWaveformView(state: .settling)
            case .showingScore(let score):
                DockScoreDisplay(score: Int(score * 100))
            }
            
        case .speakOnly(let phase):
            switch phase {
            case .idle:
                DockWaveformView(state: .idle)
            case .listening:
                DockWaveformView(state: .listening, audioLevel: viewModel.audioLevel)
            case .analyzing:
                DockWaveformView(state: .settling)
            case .showingScore(let score):
                DockScoreDisplay(score: Int(score * 100))
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Progress through current affirmation (for progress bar fill)
    private var currentProgress: CGFloat {
        // TODO: Calculate based on TTS progress or timer
        // For now, return based on phase
        let state = viewModel.dockManager.state
        switch state {
        case .home:
            return 0
        case .readAloud(let phase):
            switch phase {
            case .idle: return 0
            case .speaking: return 0.5
            case .complete: return 1.0
            }
        case .readAndSpeak(let phase):
            switch phase {
            case .idle: return 0
            case .ttsPlaying: return 0.25
            case .waitingForUser: return 0.5
            case .listening: return 0.65
            case .analyzing: return 0.85
            case .showingScore: return 1.0
            }
        case .speakOnly(let phase):
            switch phase {
            case .idle: return 0
            case .listening: return 0.5
            case .analyzing: return 0.8
            case .showingScore: return 1.0
            }
        }
    }
    
    /// Whether currently in a playing or listening state
    private var isPlayingOrListening: Bool {
        let state = viewModel.dockManager.state
        switch state {
        case .readAloud(let phase):
            return phase == .speaking
        case .readAndSpeak(let phase):
            return phase == .ttsPlaying || phase == .listening
        case .speakOnly(let phase):
            return phase == .listening
        default:
            return false
        }
    }
}

// MARK: - DockModeButton

struct DockModeButton: View {
    
    let mode: SessionMode
    let isExpanded: Bool
    var showLabel: Bool = true
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14, weight: .semibold))
                
                if showLabel {
                    Text(mode.displayName)
                        .font(AppTypography.caption1.weight(.medium))
                        .lineLimit(1)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppColors.accent.opacity(0.15))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Session mode: \(mode.displayName)")
        .accessibilityHint("Double tap to change mode")
    }
}

// MARK: - DockBinauralButton

struct DockBinauralButton: View {
    
    let preset: BinauralPreset
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 14, weight: .semibold))
                
                if preset != .off {
                    Text(preset.displayName)
                        .font(AppTypography.caption1.weight(.medium))
                        .lineLimit(1)
                }
                
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(preset == .off ? AppColors.textSecondary : AppColors.accentSecondary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                preset == .off
                    ? AppColors.surfaceTertiary
                    : AppColors.accentSecondary.opacity(0.15)
            )
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Binaural beats: \(preset.displayName)")
        .accessibilityHint("Double tap to change binaural preset")
    }
}

// MARK: - ModeSelectorExpanded

struct ModeSelectorExpanded: View {
    
    let selectedMode: SessionMode
    let onSelect: (SessionMode) -> Void
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(SessionMode.allCases) { mode in
                ModeOptionRow(
                    mode: mode,
                    isSelected: mode == selectedMode
                ) {
                    onSelect(mode)
                    HapticFeedback.selection()
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        // No horizontal padding - inherits from parent to match dock width
    }
}

// MARK: - ModeOptionRow

struct ModeOptionRow: View {
    
    let mode: SessionMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    
                    Text(mode.description)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppColors.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BinauralSelectorExpanded

struct BinauralSelectorExpanded: View {
    
    let selectedPreset: BinauralPreset
    let onSelect: (BinauralPreset) -> Void
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(BinauralPreset.allCases) { preset in
                BinauralOptionRow(
                    preset: preset,
                    isSelected: preset == selectedPreset
                ) {
                    onSelect(preset)
                    HapticFeedback.selection()
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
        // No horizontal padding - inherits from parent to match dock width
    }
}

// MARK: - BinauralOptionRow

struct BinauralOptionRow: View {
    
    let preset: BinauralPreset
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppColors.accentSecondary : AppColors.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(AppTypography.headline)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    
                    if preset != .off {
                        Text(preset.description)
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 0)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.accentSecondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(isSelected ? AppColors.accentSecondary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Dock - Home Mode") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock(
                viewModel: {
                    let vm = PracticeViewModel()
                    vm.affirmations = Affirmation.samples
                    return vm
                }(),
                onBinauralChange: { _ in },
                onModeChange: { _ in }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}

#Preview("Dock - Read Aloud Playing") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock(
                viewModel: {
                    let vm = PracticeViewModel()
                    vm.affirmations = Affirmation.samples
                    vm.dockManager.setMode(.readAloud)
                    vm.dockManager.updateReadAloudPhase(.speaking)
                    vm.audioLevel = 0.6
                    return vm
                }(),
                onBinauralChange: { _ in },
                onModeChange: { _ in }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}

#Preview("Dock - Listening (Green)") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock(
                viewModel: {
                    let vm = PracticeViewModel()
                    vm.affirmations = Affirmation.samples
                    vm.dockManager.setMode(.speakOnly)
                    vm.dockManager.updateSpeakOnlyPhase(.listening)
                    vm.audioLevel = 0.7
                    return vm
                }(),
                onBinauralChange: { _ in },
                onModeChange: { _ in }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}

#Preview("Dock - Score Shown") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock(
                viewModel: {
                    let vm = PracticeViewModel()
                    vm.affirmations = Affirmation.samples
                    vm.dockManager.setMode(.speakOnly)
                    vm.dockManager.updateSpeakOnlyPhase(.showingScore(score: 0.78))
                    return vm
                }(),
                onBinauralChange: { _ in },
                onModeChange: { _ in }
            )
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}
