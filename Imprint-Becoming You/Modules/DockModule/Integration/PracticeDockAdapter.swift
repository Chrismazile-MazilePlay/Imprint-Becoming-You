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

    /// When `true`, this adapter never produces session segments or fires
    /// segment completion callbacks.
    ///
    /// Used by the home dock (behind the fullScreenCover) to prevent phantom
    /// segment timers from running invisibly during active sessions. Without
    /// this, both the home and session docks would produce timers that fire
    /// `segmentTimerCompleted`, contributing to double-advance bugs.
    let suppressSegments: Bool

    // MARK: - Local State

    /// Which selector menu is currently expanded, if any.
    var expandedSelector: DockExpandedSelector?

    /// Shuffle option hidden on home/session screens (no predefined set to shuffle).
    var showsShuffleOption: Bool { false }

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
    /// - Parameters:
    ///   - store: The practice store to adapt
    ///   - suppressSegments: When `true`, suppresses session segment timers.
    ///     Use `true` for the home dock behind the fullScreenCover.
    init(store: PracticeStore, suppressSegments: Bool = false) {
        self.store = store
        self.suppressSegments = suppressSegments
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
    
    // MARK: - Music State

    var musicCategory: DockMusicCategory {
        mapMusicCategory(store.backgroundMusicCategory)
    }

    var musicVolume: Float {
        store.backgroundMusicVolume
    }
    
    // MARK: - Session State
    
    var centerContentState: DockCenterContentState {
        mapFlowToCenterContent(store.flow)
    }
    
    var sessionSegments: DockSessionSegments? {
        guard !suppressSegments else { return nil }
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
    
    var canNavigatePrevious: Bool {
        store.canGoPrevious
    }
    
    var canNavigateNext: Bool {
        store.canGoNext
    }
    
    // MARK: - Configuration Mode State

    /// Loop count selected on the home screen.
    ///
    /// Applied to the store's loop configuration when a session starts via mode selection.
    /// Defaults to `1` (single play).
    var loopCount: Int = 1

    /// Whether spaced repetition (Reinforce) is enabled on the home screen.
    ///
    /// Applied to the store's loop configuration when a session starts via mode selection.
    /// Defaults to `false` (standard 10-segment session).
    var isSpacedRepetitionEnabled: Bool = false

    /// Whether the extended loop page (2, 6, 10) is shown in the config menu.
    ///
    /// Defaults to `false` (base page with 1, 3, 5).
    var isExtendedLoopPage: Bool = false

    /// Not applicable for practice mode.
    var isShuffleEnabled: Bool { false }
    
    /// Not applicable for practice mode.
    var isPlayEnabled: Bool { false }
    
    /// Not applicable for practice mode.
    var labelText: String { "" }
    
    // MARK: - Mode Actions
    
    func selectMode(_ mode: DockMode) {
        // Check mic availability for modes that require it
        if mode.requiresMicrophone && !ListDockAdapter.isMicrophoneAccessible() {
            // Close mode selector, then show error bar
            expandedSelector = nil
            showError("The microphone is being used by another app")
            return
        }

        let sessionMode = mapDockModeToSessionMode(mode)
        store.send(.selectMode(sessionMode))
        expandedSelector = nil

        // Apply loop + spaced repetition configuration after session starts
        // (overrides the store's reset).
        // send() is synchronous, so setLoopConfiguration runs on the same MainActor turn.
        if loopCount > 1 || isSpacedRepetitionEnabled {
            var config = LoopConfiguration()
            config.loopCount = loopCount
            config.isShuffleEnabled = false
            config.isSpacedRepetitionEnabled = isSpacedRepetitionEnabled
            config.currentLoopIteration = 1
            store.setLoopConfiguration(config)
        }
    }
    
    // MARK: - Music Actions

    func selectMusic(_ category: DockMusicCategory) {
        let musicCategory = mapDockMusicToCategory(category)
        store.send(.selectBackgroundMusic(musicCategory))
        expandedSelector = nil
    }

    func setMusicVolume(_ volume: Float) {
        store.send(.setBackgroundMusicVolume(volume))
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
        expandedSelector = nil
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
        guard !suppressSegments else { return }
        // Dock's segment timer completed - trigger auto-advance
        store.send(.segmentTimerCompleted)
    }
    
    // MARK: - Configuration Mode Actions (No-op)
    
    func cycleLoopCount() {
        // Not applicable for practice mode
    }

    func selectLoopCount(_ count: Int) {
        let allValid = LoopConfiguration.loopOptions + LoopConfiguration.extendedLoopOptions
        guard allValid.contains(count) else { return }
        loopCount = count
    }

    func navigateLoopPage() {
        isExtendedLoopPage.toggle()
    }

    func toggleShuffle() {
        // Not applicable for practice mode
    }

    func toggleSpacedRepetition() {
        isSpacedRepetitionEnabled.toggle()
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
    
    /// Maps MusicCategory? to DockMusicCategory.
    func mapMusicCategory(_ category: MusicCategory?) -> DockMusicCategory {
        guard let category = category else { return .off }
        return DockMusicCategory(rawValue: category.rawValue) ?? .off
    }

    /// Maps DockMusicCategory back to MusicCategory?.
    func mapDockMusicToCategory(_ dockCategory: DockMusicCategory) -> MusicCategory? {
        guard dockCategory != .off else { return nil }
        return MusicCategory(rawValue: dockCategory.rawValue)
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
            case .listening:
                // Read audio level from the dedicated lightweight property instead
                // of the flow enum's ListeningContext. This avoids triggering
                // setFlow() + ListeningContext String copies on every audio tick.
                return .listening(audioLevel: CGFloat(store.listeningAudioLevel))
            case .celebrating:
                return .idle
            }

        case .speakOnly(let phase):
            switch phase {
            case .idle:
                return .idle
            case .preparingToListen:
                // Green breathing animation while speech engine initializes
                return .preparing
            case .listening:
                // Read audio level from the dedicated lightweight property instead
                // of the flow enum's ListeningContext. This avoids triggering
                // setFlow() + ListeningContext String copies on every audio tick.
                return .listening(audioLevel: CGFloat(store.listeningAudioLevel))
            case .celebrating:
                return .idle
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
            case .celebrating:
                return true   // Keep filled during celebration
            }

        // SpeakOnly (toggle mode): segment filled during active phases
        case .speakOnly(let phase):
            switch phase {
            case .idle:
                return false  // Not started yet
            case .preparingToListen, .listening:
                return true   // Segment shows as filled
            case .celebrating:
                return true   // Keep filled during celebration
            }
        }
    }
}
