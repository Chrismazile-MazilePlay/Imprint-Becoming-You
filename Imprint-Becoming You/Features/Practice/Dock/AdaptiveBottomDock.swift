//
//  AdaptiveBottomDock.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
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
    
    @Bindable var store: PracticeStore
    
    // MARK: - Body
    
    var body: some View {
        let currentMode = store.currentMode
        let currentBinaural = store.binauralPreset
        let isModeSelectorExpanded = store.isModeSelectorExpanded
        let isBinauralSelectorExpanded = store.isBinauralSelectorExpanded
        let isActiveMode = store.isSessionActive
        
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
                    store.send(.selectMode(mode))
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, AppTheme.Spacing.sm)
        }
        
        if isBinauralSelectorExpanded {
            BinauralSelectorExpanded(
                selectedPreset: currentBinaural,
                onSelect: { preset in
                    store.send(.selectBinaural(preset))
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
                store.send(.toggleModeSelector)
                HapticFeedback.impact(.light)
            }
            
            Spacer(minLength: 0)
            
            DockBinauralButton(
                preset: currentBinaural,
                isExpanded: isBinauralSelectorExpanded
            ) {
                store.send(.toggleBinauralSelector)
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
                current: store.currentIndex,
                total: store.totalCount,
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
                    store.send(.toggleModeSelector)
                    HapticFeedback.impact(.light)
                }
                
                Spacer(minLength: 0)
                
                DockBinauralButton(
                    preset: currentBinaural,
                    isExpanded: isBinauralSelectorExpanded
                ) {
                    store.send(.toggleBinauralSelector)
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
                store.send(.navigateViaButton(.previous))
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(store.canGoPrevious ? AppColors.textSecondary : AppColors.textTertiary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!store.canGoPrevious)
            .accessibilityLabel("Previous affirmation")
            .accessibilityHint(store.canGoPrevious ? "Double tap to go back" : "Already at first affirmation")
            
            Spacer()
            
            // Center content (waveform or score) - fixed height for consistent dock size
            centerContent
                .frame(height: 52)
            
            Spacer()
            
            // Right chevron
            Button {
                store.send(.navigateViaButton(.next))
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(store.canGoNext ? AppColors.textSecondary : AppColors.textTertiary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!store.canGoNext)
            .accessibilityLabel("Next affirmation")
            .accessibilityHint(store.canGoNext ? "Double tap to advance" : "Already at last affirmation")
        }
    }
    
    // MARK: - Center Content
    
    @ViewBuilder
    private var centerContent: some View {
        switch store.flow {
        case .home:
            EmptyView()
            
        case .readAloud(let phase):
            switch phase {
            case .idle:
                DockWaveformView(state: .idle)
            case .playing:
                DockWaveformView(state: .playing, audioLevel: audioLevel)
            case .complete:
                DockWaveformView(state: .idle)
            }
            
        case .readAndSpeak(let phase):
            switch phase {
            case .idle:
                DockWaveformView(state: .idle)
            case .ttsPlaying:
                DockWaveformView(state: .playing, audioLevel: audioLevel)
            case .waitingForUser:
                DockWaveformView(state: .waiting)
            case .listening(let context):
                DockWaveformView(state: .listening, audioLevel: CGFloat(context.audioLevel))
            case .analyzing:
                DockWaveformView(state: .settling)
            case .showingScore(let result):
                DockScoreDisplay(score: result.percentScore)
            }
            
        case .speakOnly(let phase):
            switch phase {
            case .idle:
                DockWaveformView(state: .idle)
            case .listening(let context):
                DockWaveformView(state: .listening, audioLevel: CGFloat(context.audioLevel))
            case .analyzing:
                DockWaveformView(state: .settling)
            case .showingScore(let result):
                DockScoreDisplay(score: result.percentScore)
            }
        }
    }
    
    // MARK: - Computed Helpers
    
    /// Audio level from flow context, or 0 if not available
    private var audioLevel: CGFloat {
        CGFloat(store.flow.currentAudioLevel ?? 0)
    }
    
    /// Progress through current affirmation (for progress bar fill)
    /// Uses explicit segmentProgress from store, not derived from flow state.
    private var currentProgress: CGFloat {
        store.segmentProgress
    }
    
    /// Whether currently in a playing or listening state
    private var isPlayingOrListening: Bool {
        store.flow.isTTSPlaying || store.flow.isListening
    }
}

// MARK: - Previews

#Preview("Dock - Home Mode") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock(store: .preview)
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
            
            AdaptiveBottomDock(store: .previewReadAloud)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}

#Preview("Dock - Listening") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock(store: .previewListening)
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
            
            AdaptiveBottomDock(store: .previewShowingScore)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}
