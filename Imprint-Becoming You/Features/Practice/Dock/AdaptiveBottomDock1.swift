//
//  AdaptiveBottomDock.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - AdaptiveBottomDock

/// The unified morphing bottom dock that adapts its content based on context.
///
/// This component is a **pure dock row** - it renders only the dock content (chips, buttons)
/// and has **no knowledge of menus**. Menu handling (Mode selector, Binaural selector) is
/// delegated to `AdaptiveDockContainer`.
///
/// ## Supported Contexts
///
/// ### Practice Mode (via `init(store:)`)
/// - **Home**: Mode button + Binaural button (compact)
/// - **Active Session**: Progress bars + Waveform/Score + Navigation + Mode/Binaural buttons
///
/// ### Configuration Mode (via `init(selectedMode:...)`)
/// - **Results/Favorites/Saved Sessions**: Mode + Loops + Shuffle + Play
///
/// ## Layout (Configuration Mode)
/// ```
/// ┌─────────────────────────┐      ┌────────┐  ┌────────┐      ┌────┐
/// │ 📖 Read Aloud    ▼  │      │ 🔁 3   │  │  🔀    │      │ ▶  │
/// └─────────────────────────┘      └────────┘  └────────┘      └────┘
///       Left-aligned              Centered chips          Right-aligned
/// ```
///
/// ## Menu Handling
/// This component does NOT render expanded menus. When mode/binaural buttons are tapped,
/// they toggle state in the store or binding. The parent `AdaptiveDockContainer` is
/// responsible for rendering the actual menu panels.
struct AdaptiveBottomDock1: View {
    
    // MARK: - Dock Mode
    
    private enum DockMode {
        case practice
        case configuration
    }
    
    private let dockMode: DockMode
    
    // MARK: - Practice Mode Properties
    
    private var store: PracticeStore?
    
    // MARK: - Configuration Mode Properties
    
    @Binding private var configSelectedMode: SessionMode
    @Binding private var configLoopCount: Int
    @Binding private var configShuffleEnabled: Bool
    @Binding private var configIsModeSelectorExpanded: Bool
    private let configIsPlayEnabled: Bool
    private let configIsDisabled: Bool
    private let configOnPlay: (() -> Void)?
    
    // MARK: - Animation State
    
    /// Tracks whether selector animation is in progress.
    /// Buttons are silently disabled during animation to prevent double-taps.
    @State private var isAnimatingSelector = false
    
    /// Duration to match AppTheme.Animation.standard
    private let animationDuration: TimeInterval = 0.35
    
    // MARK: - Constants
    
    /// Fixed height for configuration mode chips
    private let chipHeight: CGFloat = 36
    
    // MARK: - Practice Mode Initializer
    
    /// Creates a dock for practice mode (home and active session).
    ///
    /// - Parameter store: The practice store managing session state
    init(store: PracticeStore) {
        self.dockMode = .practice
        self.store = store
        
        // Configuration mode bindings (unused in practice mode)
        self._configSelectedMode = .constant(.readThenSpeak)
        self._configLoopCount = .constant(1)
        self._configShuffleEnabled = .constant(false)
        self._configIsModeSelectorExpanded = .constant(false)
        self.configIsPlayEnabled = false
        self.configIsDisabled = false
        self.configOnPlay = nil
    }
    
    // MARK: - Configuration Mode Initializer
    
    /// Creates a dock for configuration mode (Results, Favorites, Saved Sessions).
    ///
    /// - Parameters:
    ///   - selectedMode: Binding to the selected session mode
    ///   - loopCount: Binding to the loop count (1, 3, or 5)
    ///   - shuffleEnabled: Binding to shuffle toggle state
    ///   - isModeSelectorExpanded: Binding to mode selector expansion state
    ///   - isPlayEnabled: Whether the play button is enabled
    ///   - isDisabled: Whether all controls are disabled (empty state)
    ///   - onPlay: Action when play button is tapped
    init(
        selectedMode: Binding<SessionMode>,
        loopCount: Binding<Int>,
        shuffleEnabled: Binding<Bool>,
        isModeSelectorExpanded: Binding<Bool>,
        isPlayEnabled: Bool = true,
        isDisabled: Bool = false,
        onPlay: @escaping () -> Void
    ) {
        self.dockMode = .configuration
        self.store = nil
        
        self._configSelectedMode = selectedMode
        self._configLoopCount = loopCount
        self._configShuffleEnabled = shuffleEnabled
        self._configIsModeSelectorExpanded = isModeSelectorExpanded
        self.configIsPlayEnabled = isPlayEnabled
        self.configIsDisabled = isDisabled
        self.configOnPlay = onPlay
    }
    
    // MARK: - Body
    
    var body: some View {
        mainDockContent
            .animation(AppTheme.Animation.standard, value: animationTriggers)
    }
    
    /// Combined animation triggers for smooth transitions
    private var animationTriggers: AnimationTriggers {
        switch dockMode {
        case .practice:
            guard let store = store else {
                return AnimationTriggers(
                    mode: .readThenSpeak,
                    binaural: .off,
                    isActive: false
                )
            }
            return AnimationTriggers(
                mode: store.currentMode,
                binaural: store.binauralPreset,
                isActive: store.isSessionActive
            )
        case .configuration:
            return AnimationTriggers(
                mode: configSelectedMode,
                binaural: .off,
                isActive: false
            )
        }
    }
    
    // MARK: - Dock Background
    
    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.CornerRadius.extraLarge)
            .fill(AppColors.backgroundSecondary.opacity(0.95))
            .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
    }
    
    // MARK: - Main Dock Content
    
    @ViewBuilder
    private var mainDockContent: some View {
        switch dockMode {
        case .practice:
            practiceModeContent
        case .configuration:
            configurationModeContent
        }
    }
}

// MARK: - Animation Triggers

/// Hashable struct for animation value tracking
private struct AnimationTriggers: Equatable {
    let mode: SessionMode
    let binaural: BinauralPreset
    let isActive: Bool
}

// MARK: - Practice Mode Content

extension AdaptiveBottomDock1 {
    
    @ViewBuilder
    private var practiceModeContent: some View {
        if let store = store {
            VStack(spacing: AppTheme.Spacing.md) {
                if store.isSessionActive {
                    activeModeContent(store: store)
                } else {
                    homeModeContent(store: store)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(dockBackground)
        }
    }
    
    // MARK: - Home Mode Content
    
    private func homeModeContent(store: PracticeStore) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            DockModeButton1(
                mode: store.currentMode,
                isExpanded: store.isModeSelectorExpanded
            ) {
                togglePracticeModeSelector()
            }
            
            Spacer(minLength: 0)
            
            DockBinauralButton1(
                preset: store.binauralPreset,
                isExpanded: store.isBinauralSelectorExpanded
            ) {
                togglePracticeBinauralSelector()
            }
        }
    }
    
    // MARK: - Active Mode Content
    
    private func activeModeContent(store: PracticeStore) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Progress bars (Stories style)
            DockProgressBars1(
                current: store.displayCurrentIndex,
                total: store.displayTotalCount,
                progress: store.segmentProgress,
                isAnimating: store.flow.isTTSPlaying || store.flow.isListening
            )
            .padding(.horizontal, AppTheme.Spacing.sm)
            
            // Center content with chevrons
            centerContentRow(store: store)
            
            // Mode and binaural buttons
            HStack(spacing: AppTheme.Spacing.md) {
                DockModeButton1(
                    mode: store.currentMode,
                    isExpanded: store.isModeSelectorExpanded,
                    showLabel: true
                ) {
                    togglePracticeModeSelector()
                }
                
                Spacer(minLength: 0)
                
                DockBinauralButton1(
                    preset: store.binauralPreset,
                    isExpanded: store.isBinauralSelectorExpanded
                ) {
                    togglePracticeBinauralSelector()
                }
            }
        }
    }
    
    // MARK: - Center Content Row (Active Mode)
    
    private func centerContentRow(store: PracticeStore) -> some View {
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
            
            // Center content (waveform or score)
            centerContent(store: store)
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
    
    // MARK: - Center Content (Waveform/Score)
    
    @ViewBuilder
    private func centerContent(store: PracticeStore) -> some View {
        switch store.flow {
        case .home:
            EmptyView()
            
        case .readAloud(let phase):
            switch phase {
            case .idle:
                DockWaveformView1(state: .idle)
            case .playing:
                DockWaveformView1(state: .playing, audioLevel: CGFloat(store.flow.currentAudioLevel ?? 0))
            case .complete:
                DockWaveformView1(state: .idle)
            }
            
        case .readAndSpeak(let phase):
            switch phase {
            case .idle:
                DockWaveformView1(state: .idle)
            case .ttsPlaying:
                DockWaveformView1(state: .playing, audioLevel: CGFloat(store.flow.currentAudioLevel ?? 0))
            case .preparingToListen:
                DockWaveformView1(state: .waiting)
            case .listening(let context):
                DockWaveformView1(state: .listening, audioLevel: CGFloat(context.audioLevel))
            case .analyzing:
                DockWaveformView1(state: .settling)
            case .showingScore(let result):
                DockScoreDisplay1(score: result.percentScore)
            }
            
        case .speakOnly(let phase):
            switch phase {
            case .idle:
                DockWaveformView1(state: .idle)
            case .listening(let context):
                DockWaveformView1(state: .listening, audioLevel: CGFloat(context.audioLevel))
            case .analyzing:
                DockWaveformView1(state: .settling)
            case .showingScore(let result):
                DockScoreDisplay1(score: result.percentScore)
            case .preparingToListen:
                DockWaveformView1(state: .waiting)
            }
        }
    }
    
    // MARK: - Practice Mode Button Actions
    
    private func togglePracticeModeSelector() {
        guard !isAnimatingSelector, let store = store else { return }
        
        isAnimatingSelector = true
        HapticFeedback.impact(.light)
        store.send(.toggleModeSelector)
        
        let duration = animationDuration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            isAnimatingSelector = false
        }
    }
    
    private func togglePracticeBinauralSelector() {
        guard !isAnimatingSelector, let store = store else { return }
        
        isAnimatingSelector = true
        HapticFeedback.impact(.light)
        store.send(.toggleBinauralSelector)
        
        let duration = animationDuration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            isAnimatingSelector = false
        }
    }
}

// MARK: - Configuration Mode Content

extension AdaptiveBottomDock1 {
    
    private var configurationModeContent: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Configuration controls with ZStack layout
            configurationControls
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(dockBackground)
        .opacity(configIsDisabled ? 0.5 : 1.0)
        .allowsHitTesting(!configIsDisabled)
    }
    
    /// Configuration controls with fixed right-side spacing.
    ///
    /// ## Layout Strategy
    /// - Mode chip: Left-aligned, variable width
    /// - Spacer: Flexible, absorbs mode width changes
    /// - Loop chip: Fixed spacing to shuffle
    /// - Shuffle chip: Fixed spacing to play button
    /// - Play button: Right-aligned
    ///
    /// ```
    /// [Mode ▼] ← flexible → [🔁 3] ← FIXED → [🔀] ← FIXED → [▶]
    /// ```
    private var configurationControls: some View {
        HStack(spacing: 0) {
            // Mode chip (left-aligned, variable width)
            DockModeButton1(
                mode: configSelectedMode,
                isExpanded: configIsModeSelectorExpanded,
                showLabel: true
            ) {
                toggleConfigModeSelector()
            }
            .frame(height: chipHeight)
            
            // Flexible spacer - absorbs mode chip width changes
            Spacer(minLength: AppTheme.Spacing.sm)
            
            // Fixed-spacing group: Loop → Shuffle → Play
            HStack(spacing: AppTheme.Spacing.sm) {
                configLoopChip
                configShuffleChip
                configPlayButton
            }
        }
    }
    
    // MARK: - Loop Chip
    
    private var configLoopChip: some View {
        Button {
            cycleLoopCount()
            HapticFeedback.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "repeat")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(configLoopCount)")
                    .font(AppTypography.caption1.weight(.semibold))
            }
            .foregroundStyle(configLoopCount > 1 ? AppColors.accent : AppColors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(height: chipHeight)
            .background(
                Capsule()
                    .fill(configLoopCount > 1 ? AppColors.accent.opacity(0.15) : AppColors.backgroundTertiary)
            )
        }
        .accessibilityLabel("Loop count: \(configLoopCount). Tap to cycle.")
        .accessibilityHint("Cycles through 1, 3, and 5 loops")
    }
    
    private func cycleLoopCount() {
        switch configLoopCount {
        case 1: configLoopCount = 3
        case 3: configLoopCount = 5
        default: configLoopCount = 1
        }
    }
    
    // MARK: - Shuffle Chip
    
    private var configShuffleChip: some View {
        Button {
            configShuffleEnabled.toggle()
            HapticFeedback.selection()
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(configShuffleEnabled ? AppColors.accent : AppColors.textSecondary)
                .frame(width: chipHeight, height: chipHeight)
                .background(
                    Capsule()
                        .fill(configShuffleEnabled ? AppColors.accent.opacity(0.15) : AppColors.backgroundTertiary)
                )
        }
        .accessibilityLabel("Shuffle: \(configShuffleEnabled ? "on" : "off")")
        .accessibilityHint("Randomizes affirmation order each loop")
    }
    
    // MARK: - Play Button
    
    private var configPlayButton: some View {
        Button {
            configOnPlay?()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(configPlayButtonEnabled ? AppColors.textPrimary : AppColors.textTertiary)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(configPlayButtonEnabled ? AppColors.accent : AppColors.backgroundTertiary)
                )
        }
        .disabled(!configPlayButtonEnabled)
        .accessibilityLabel("Play")
    }
    
    private var configPlayButtonEnabled: Bool {
        configIsPlayEnabled && !configIsDisabled
    }
    
    // MARK: - Configuration Mode Button Actions
    
    private func toggleConfigModeSelector() {
        guard !isAnimatingSelector else { return }
        
        isAnimatingSelector = true
        HapticFeedback.impact(.light)
        
        withAnimation(AppTheme.Animation.standard) {
            configIsModeSelectorExpanded.toggle()
        }
        
        let duration = animationDuration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            isAnimatingSelector = false
        }
    }
}

// MARK: - Previews

#Preview("Dock - Home Mode") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            AdaptiveBottomDock1(store: .preview)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
    }
}

#Preview("Dock - Configuration Mode") {
    struct ConfigPreview: View {
        @State private var mode: SessionMode = .readThenSpeak
        @State private var loops = 1
        @State private var shuffle = false
        @State private var expanded = false
        
        var body: some View {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    // Use AdaptiveDockContainer with AdaptiveBottomDock
                    AdaptiveDockContainer1.favorites(
                        count: 9,
                        isModeSelectorExpanded: $expanded,
                        selectedMode: $mode
                    ) {
                        AdaptiveBottomDock1(
                            selectedMode: $mode,
                            loopCount: $loops,
                            shuffleEnabled: $shuffle,
                            isModeSelectorExpanded: $expanded,
                            onPlay: { print("Play") }
                        )
                    }
                }
            }
        }
    }
    
    return ConfigPreview()
}

#Preview("Dock - Configuration Disabled") {
    struct DisabledPreview: View {
        @State private var mode: SessionMode = .readThenSpeak
        @State private var loops = 1
        @State private var shuffle = false
        @State private var expanded = false
        
        var body: some View {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    AdaptiveDockContainer1.favorites(
                        count: 0,
                        isModeSelectorExpanded: $expanded,
                        selectedMode: $mode
                    ) {
                        AdaptiveBottomDock1(
                            selectedMode: $mode,
                            loopCount: $loops,
                            shuffleEnabled: $shuffle,
                            isModeSelectorExpanded: $expanded,
                            isDisabled: true,
                            onPlay: { }
                        )
                    }
                }
            }
        }
    }
    
    return DisabledPreview()
}
