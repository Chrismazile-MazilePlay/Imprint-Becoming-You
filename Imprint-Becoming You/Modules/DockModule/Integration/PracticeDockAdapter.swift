//
//  PracticeDockAdapter.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI
import AVFoundation

// MARK: - PracticeDockAdapter

/// Adapter that bridges `PracticeStore` to the DockModule for practice experiences.
///
/// This adapter is used by `PracticePageView` and handles both:
/// - **Home mode**: Browsing affirmations (no active session)
/// - **Session mode**: Active practice session with progress, waveform, navigation
///
/// ## Usage
///
/// ```swift
/// struct PracticePageView: View {
///     @State private var store: PracticeStore
///     @State private var dockAdapter: PracticeDockAdapter
///
///     init(store: PracticeStore) {
///         self._store = State(initialValue: store)
///         self._dockAdapter = State(initialValue: PracticeDockAdapter(store: store))
///     }
///
///     var body: some View {
///         ZStack {
///             // Content...
///
///             AdaptiveDockContainer(adapter: dockAdapter) {
///                 AdaptiveBottomDock(adapter: dockAdapter)
///             }
///         }
///     }
/// }
/// ```
///
/// ## Observation
///
/// Since `PracticeStore` is `@Observable`, this adapter automatically picks up
/// changes when the store's state changes. The adapter itself is also `@Observable`
/// to handle its own state (selector expansion).
@MainActor
@Observable
final class PracticeDockAdapter: DockAdapterProtocol {
    
    // MARK: - Dependencies
    
    /// The practice store being adapted.
    private let store: PracticeStore
    
    // MARK: - Local State
    
    /// Whether the mode selector menu is expanded.
    var isModeSelectorExpanded: Bool = false
    
    /// Whether the binaural selector menu is expanded.
    var isBinauralSelectorExpanded: Bool = false
    
    // MARK: - Error Bar State
    
    /// Whether the error bar is visible.
    var isErrorBarVisible: Bool = false
    
    /// The current error bar message.
    private(set) var errorBarMessage: String = ""
    
    /// Task managing the auto-dismiss timer for the error bar.
    private var errorDismissTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Creates an adapter wrapping the given practice store.
    ///
    /// - Parameter store: The practice store to adapt
    init(store: PracticeStore) {
        self.store = store
    }
    
    // MARK: - Configuration
    
    var configuration: DockConfiguration {
        store.isSessionActive ? .session : .home
    }
    
    // MARK: - Mode State
    
    var currentMode: DockMode {
        mapMode(store.sessionMode)
    }
    
    var availableModes: [DockMode] {
        // During an active session, hide "Read Only" — selecting it would end
        // the session, and the exit button already provides that functionality.
        if store.isSessionActive {
            return DockMode.allCases.filter { $0 != .readOnly }
        }
        return DockMode.allCases
    }
    
    // MARK: - Binaural State
    
    var binauralPreset: DockBinauralPreset {
        mapBinaural(store.binauralPreset)
    }
    
    // MARK: - Session State
    
    var centerContentState: DockCenterContentState {
        mapFlowToCenterContent(store.flow)
    }
    
    var sessionSegments: DockSessionSegments? {
        guard store.isSessionActive else { return nil }
        
        // Build configs from affirmation speech durations
        let configs = store.sessionAffirmations.map { affirmation in
            DockSegmentConfig.forSpeechDuration(affirmation.speechDuration)
        }
        
        let isAnimating = isSegmentAnimating(for: store.flow)
        
        // Only Read Aloud uses timed progress (segment timer triggers auto-advance)
        // Read & Speak and Speak Only use toggle mode (score completion triggers auto-advance)
        let usesTimedProgress = store.sessionMode == .readAloud
        
        // Signal dock to show current segment as 100% during forward navigation transition.
        // This prevents the visual glitch where segment resets to 0% before filling.
        let showCurrentAsComplete = store.isForwardNavigationPending
        
        return DockSessionSegments(
            configs: configs,
            currentIndex: store.displayCurrentIndex,
            isAnimating: isAnimating,
            usesTimedProgress: usesTimedProgress,
            generation: store.segmentGeneration,
            showCurrentAsComplete: showCurrentAsComplete
        )
    }
    
    /// Legacy progress (deprecated - use sessionSegments instead).
    var progress: DockProgress? {
        guard store.isSessionActive else { return nil }
        
        return DockProgress(
            currentIndex: store.displayCurrentIndex,
            totalCount: store.sessionAffirmations.count,
            segmentProgress: Float(store.segmentProgress),
            isAnimating: isSegmentAnimating(for: store.flow)
        )
    }
    
    var canNavigatePrevious: Bool {
        store.canGoPrevious
    }
    
    var canNavigateNext: Bool {
        store.canGoNext
    }
    
    // MARK: - Configuration Mode State (Not Used)
    
    /// Not applicable for practice mode.
    var loopCount: Int { 1 }
    
    /// Not applicable for practice mode.
    var isShuffleEnabled: Bool { false }
    
    /// Not applicable for practice mode.
    var isPlayEnabled: Bool { false }
    
    /// Not applicable for practice mode.
    var labelText: String { "" }
    
    // MARK: - Mode Actions
    
    func selectMode(_ mode: DockMode) {
        // Check mic availability for modes that require it
        if mode.requiresMicrophone && !ConfigurationDockAdapter.isMicrophoneAccessible() {
            // Close mode selector, then show error bar
            isModeSelectorExpanded = false
            showError("The microphone is being used by another app")
            return
        }
        
        let sessionMode = mapDockModeToSessionMode(mode)
        store.send(.selectMode(sessionMode))
        isModeSelectorExpanded = false
    }
    
    // MARK: - Binaural Actions
    
    func selectBinaural(_ preset: DockBinauralPreset) {
        let binauralPreset = mapDockBinauralToPreset(preset)
        store.send(.selectBinaural(binauralPreset))
        isBinauralSelectorExpanded = false
    }
    
    // MARK: - Navigation Actions
    
    /// Navigates to the previous affirmation via button tap.
    ///
    /// Uses `.navigateViaButton` to trigger VerticalPager animation.
    /// This is different from `.userNavigated` which responds to swipe gestures
    /// after the pager has already changed the index.
    func navigatePrevious() {
        store.send(.navigateViaButton(.previous))
    }
    
    /// Navigates to the next affirmation via button tap.
    ///
    /// Uses `.navigateViaButton` to trigger VerticalPager animation.
    /// This is different from `.userNavigated` which responds to swipe gestures
    /// after the pager has already changed the index.
    func navigateNext() {
        store.send(.navigateViaButton(.next))
    }
    
    // MARK: - Selector Actions
    
    func closeAllSelectors() {
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
        dismissErrorBar()
    }
    
    // MARK: - Error Bar Actions
    
    /// Shows an error message in the dock error bar.
    ///
    /// Closes any open selectors, displays the error bar, and schedules
    /// auto-dismissal after 3 seconds. Self-animating — wraps state changes
    /// in `withAnimation` to ensure consistent transition regardless of caller.
    func showError(_ message: String) {
        errorDismissTask?.cancel()
        errorBarMessage = message
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isErrorBarVisible = true
        }
        
        // Auto-dismiss after 3 seconds
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self?.isErrorBarVisible = false
            }
        }
    }
    
    /// Immediately dismisses the error bar with animation.
    func dismissErrorBar() {
        errorDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isErrorBarVisible = false
        }
    }
    
    // MARK: - Segment Animation Callback
    
    func segmentAnimationCompleted() {
        // Dock's segment timer completed - trigger auto-advance
        store.send(.segmentTimerCompleted)
    }
    
    // MARK: - Configuration Mode Actions (No-op)
    
    func cycleLoopCount() {
        // Not applicable for practice mode
    }
    
    func toggleShuffle() {
        // Not applicable for practice mode
    }
    
    func play() {
        // Not applicable for practice mode
    }
}

// MARK: - Mapping Helpers

private extension PracticeDockAdapter {
    
    /// Maps SessionMode to DockMode.
    func mapMode(_ sessionMode: SessionMode) -> DockMode {
        switch sessionMode {
        case .readOnly:
            return .readOnly
        case .readAloud:
            return .readAloud
        case .readThenSpeak:
            return .readAndSpeak
        case .speakOnly:
            return .speakOnly
        }
    }
    
    /// Maps DockMode back to SessionMode.
    func mapDockModeToSessionMode(_ dockMode: DockMode) -> SessionMode {
        switch dockMode {
        case .readOnly:
            return .readOnly
        case .readAloud:
            return .readAloud
        case .readAndSpeak:
            return .readThenSpeak
        case .speakOnly:
            return .speakOnly
        }
    }
    
    /// Maps BinauralPreset to DockBinauralPreset.
    func mapBinaural(_ preset: BinauralPreset) -> DockBinauralPreset {
        switch preset {
        case .off:
            return .off
        case .focus:
            return .focus
        case .relax:
            return .relax
        case .sleep:
            return .sleep
        }
    }
    
    /// Maps DockBinauralPreset back to BinauralPreset.
    func mapDockBinauralToPreset(_ dockPreset: DockBinauralPreset) -> BinauralPreset {
        switch dockPreset {
        case .off:
            return .off
        case .focus:
            return .focus
        case .relax:
            return .relax
        case .sleep:
            return .sleep
        }
    }
    
    /// Maps PracticeFlow to DockCenterContentState.
    func mapFlowToCenterContent(_ flow: PracticeFlow) -> DockCenterContentState {
        switch flow {
        case .home:
            return .hidden
            
        case .readAloud(let phase):
            switch phase {
            case .idle:
                return .idle
            case .playing:
                // TTS has no real audio level - use moderate constant
                return .playing(audioLevel: 0.5)
            case .complete:
                return .idle
            }
            
        case .readAndSpeak(let phase):
            switch phase {
            case .idle:
                return .idle
            case .ttsPlaying:
                return .playing(audioLevel: 0.5)
            case .preparingToListen:
                // Green breathing animation while speech engine initializes
                return .preparing
            case .listening(let context):
                return .listening(audioLevel: CGFloat(context.audioLevel))
            case .analyzing:
                return .settling
            case .showingScore(let result):
                return .showingScore(percentScore: result.percentScore)
            }
            
        case .speakOnly(let phase):
            switch phase {
            case .idle:
                return .idle
            case .preparingToListen:
                // Green breathing animation while speech engine initializes
                return .preparing
            case .listening(let context):
                return .listening(audioLevel: CGFloat(context.audioLevel))
            case .analyzing:
                return .settling
            case .showingScore(let result):
                return .showingScore(percentScore: result.percentScore)
            }
        }
    }
    
    /// Determines if segment should be active for the current flow.
    ///
    /// For timed modes (Read Aloud): this controls when the timer runs.
    /// For toggle modes (Read & Speak, Speak Only): this controls fill state.
    func isSegmentAnimating(for flow: PracticeFlow) -> Bool {
        switch flow {
        case .home:
            return false
            
        // ReadAloud (timed mode): timer runs during playing/complete phases
        case .readAloud(let phase):
            switch phase {
            case .idle:
                return false  // Not started yet
            case .playing, .complete:
                return true   // Timer runs
            }
            
        // ReadAndSpeak (toggle mode): segment filled during active phases
        case .readAndSpeak(let phase):
            switch phase {
            case .idle:
                return false  // Not started yet
            case .ttsPlaying, .preparingToListen, .listening:
                return true   // Segment shows as filled
            case .analyzing, .showingScore:
                return true   // Keep filled during analysis and score
            }
            
        // SpeakOnly (toggle mode): segment filled during active phases
        case .speakOnly(let phase):
            switch phase {
            case .idle:
                return false  // Not started yet
            case .preparingToListen, .listening:
                return true   // Segment shows as filled
            case .analyzing, .showingScore:
                return true   // Keep filled during analysis and score
            }
        }
    }
}
