//
//  ListDockAdapter.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/8/26.
//

import SwiftUI
import AVFoundation

// MARK: - ListDockAdapter

/// Adapter for the unified dock used in list and results views.
///
/// Replaces `ConfigurationDockAdapter` with a single-instance, mutation-based approach.
/// Unlike its predecessor, this adapter is created **once** and its properties are
/// mutated directly — no instance replacement needed.
///
/// ## Used By
///
/// - `FavoritesFullListView` — label: "Practice X affirmations"
/// - `SavedSessionsFullListView` — no label
/// - `ResultsSummaryView` — label: "Repeat Session"
///
/// ## Key Differences from ConfigurationDockAdapter
///
/// 1. Always returns `.home` configuration (unified 3-button layout)
/// 2. Full binaural support (was `.off`/disabled in ConfigurationDockAdapter)
/// 3. Has `expandedSelector` and `showsShuffleOption`
/// 4. Created once, properties mutated directly (no replacement pattern)
/// 5. `onPlayHandler` is mutable for late binding
///
/// ## Mode Filtering
///
/// The `availableModes` property excludes `.readOnly` since list views
/// are for starting practice sessions, not returning to browse mode.
///
/// ## Usage
///
/// ```swift
/// struct FavoritesFullListView: View {
///     @State private var dockAdapter = ListDockAdapter(showsShuffleOption: true)
///
///     var body: some View {
///         ZStack {
///             // Content...
///
///             VStack {
///                 Spacer()
///                 DockFloatingPlayButton(
///                     isEnabled: dockAdapter.isPlayEnabled,
///                     labelText: dockAdapter.labelText
///                 ) { dockAdapter.play() }
///                 AdaptiveDockContainer(adapter: dockAdapter, showsGradient: true) {
///                     AdaptiveBottomDock(adapter: dockAdapter)
///                 }
///                 .imprintDockEnvironment()
///             }
///         }
///     }
/// }
/// ```
@MainActor
@Observable
final class ListDockAdapter: DockAdapterProtocol {

    // MARK: - Configuration

    /// Always returns `.home` — the unified 3-button layout.
    let configuration: DockConfiguration = .home

    // MARK: - Mode State

    /// The currently selected mode.
    var currentMode: DockMode = .readAloud

    /// Available modes for list views (excludes readOnly).
    var availableModes: [DockMode] {
        DockMode.allCases.filter { $0 != .readOnly }
    }

    /// Which selector menu is currently expanded, if any.
    var expandedSelector: DockExpandedSelector?

    // MARK: - Binaural State

    /// The currently selected binaural preset.
    var binauralPreset: DockBinauralPreset = .off

    /// Whether the shuffle option appears in the config menu.
    ///
    /// Set to `true` for Favorites, Saved Sessions, and Results views.
    /// Set to `false` for the home screen (no predefined set to shuffle).
    let showsShuffleOption: Bool

    // MARK: - Config Values

    /// Current loop count (1, 3, or 5).
    var loopCount: Int = 1

    /// Whether shuffle is enabled.
    var isShuffleEnabled: Bool = false

    /// Whether spaced repetition (Reinforce) is enabled.
    var isSpacedRepetitionEnabled: Bool = false

    /// Whether the extended loop page (2, 6, 10) is shown in the config menu.
    ///
    /// Defaults to `false` (base page with 1, 3, 5).
    var isExtendedLoopPage: Bool = false

    /// The number of unique base affirmations available for the session.
    ///
    /// Used to validate Reinforce mode requirements at `play()` time.
    /// Reinforce requires at least `Constants.Session.sessionSize` (10) base affirmations.
    /// This count should reflect the **unique** affirmation pool — before any
    /// spaced repetition expansion — so that validation is accurate regardless of
    /// whether a previous session was expanded.
    ///
    /// Set by the consumer view at initialization or when selection changes:
    /// - `FavoritesFullListView`: `favorites.count`
    /// - `SavedSessionsFullListView`: `session.affirmationIds.count`
    /// - `ResultsSummaryView`: `summary.results.count`
    var baseAffirmationCount: Int = 0

    // MARK: - Play State

    /// Play button is always visible on list/results views.
    let showsPlayButton: Bool = true

    /// Whether the floating play button is tappable.
    var isPlayEnabled: Bool

    /// Label text for the floating play button.
    ///
    /// Examples: "Practice 9 affirmations", "Repeat Session", ""
    var labelText: String

    // MARK: - Error Bar State

    /// Whether the error bar is visible.
    var isErrorBarVisible: Bool = false

    /// The current error bar message.
    private(set) var errorBarMessage: String = ""

    /// Task managing the auto-dismiss timer for the error bar.
    private var errorDismissTask: Task<Void, Never>?

    // MARK: - Session State (Not Used in List Views)

    /// Always `.hidden` — no center content in list views.
    var centerContentState: DockCenterContentState = .hidden

    /// Always `nil` — no session segments in list views.
    var sessionSegments: DockSessionSegments? = nil

    /// Always `false` — no navigation in list views.
    var canNavigatePrevious: Bool = false

    /// Always `false` — no navigation in list views.
    var canNavigateNext: Bool = false

    // MARK: - Callbacks

    /// Called when play is tapped with current configuration.
    ///
    /// Mutable to support late binding — parent views set this after initialization.
    var onPlayHandler: ((SessionMode, Int, Bool, Bool) -> Void)?

    /// Called when play is tapped while disabled.
    ///
    /// Set by consumer views that want to show contextual feedback
    /// (e.g., SavedSessionsFullListView shows "Select a session to begin").
    /// When `nil`, tapping the disabled play button does nothing.
    var onDisabledPlayHandler: (() -> Void)?

    // MARK: - Initialization

    /// Creates a list dock adapter.
    ///
    /// - Parameters:
    ///   - initialMode: Starting mode selection (default: `.readAloud`)
    ///   - initialLoopCount: Starting loop count (default: `1`)
    ///   - initialShuffle: Starting shuffle state (default: `false`)
    ///   - initialSpacedRepetition: Starting spaced repetition state (default: `false`)
    ///   - baseAffirmationCount: Number of unique base affirmations available (default: `0`)
    ///   - showsShuffleOption: Whether shuffle appears in config menu (default: `true`)
    ///   - labelText: Text for floating play button (default: `""`)
    ///   - isPlayEnabled: Whether play button starts enabled (default: `false`)
    init(
        initialMode: DockMode = .readAloud,
        initialLoopCount: Int = 1,
        initialShuffle: Bool = false,
        initialSpacedRepetition: Bool = false,
        baseAffirmationCount: Int = 0,
        showsShuffleOption: Bool = true,
        labelText: String = "",
        isPlayEnabled: Bool = false
    ) {
        self.currentMode = initialMode
        self.loopCount = initialLoopCount
        self.isShuffleEnabled = initialShuffle
        self.isSpacedRepetitionEnabled = initialSpacedRepetition
        self.baseAffirmationCount = baseAffirmationCount
        self.showsShuffleOption = showsShuffleOption
        self.labelText = labelText
        self.isPlayEnabled = isPlayEnabled
    }

    // MARK: - Mode Actions

    func selectMode(_ mode: DockMode) {
        // Check mic availability for modes that require it
        if mode.requiresMicrophone && !Self.isMicrophoneAccessible() {
            expandedSelector = nil
            showError("The microphone is being used by another app")
            return
        }

        currentMode = mode
        expandedSelector = nil
    }

    // MARK: - Binaural Actions

    func selectBinaural(_ preset: DockBinauralPreset) {
        binauralPreset = preset
        expandedSelector = nil
    }

    // MARK: - Navigation Actions (No-op)

    func navigatePrevious() {
        // Not applicable for list views
    }

    func navigateNext() {
        // Not applicable for list views
    }

    // MARK: - Selector Actions

    func closeAllSelectors() {
        expandedSelector = nil
        dismissErrorBar()
    }

    // MARK: - Segment Animation Callback (No-op)

    func segmentAnimationCompleted() {
        // Not applicable for list views
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

    // MARK: - Configuration Mode Actions

    func cycleLoopCount() {
        if isExtendedLoopPage {
            switch loopCount {
            case 2:
                loopCount = 6
            case 6:
                loopCount = 10
            default:
                loopCount = 2
            }
        } else {
            switch loopCount {
            case 1:
                loopCount = 3
            case 3:
                loopCount = 5
            default:
                loopCount = 1
            }
        }
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
        isShuffleEnabled.toggle()
    }

    func toggleSpacedRepetition() {
        isSpacedRepetitionEnabled.toggle()
    }

    func play() {
        guard isPlayEnabled else {
            onDisabledPlayHandler?()
            return
        }

        // Validate Reinforce mode requirements before starting session.
        // This is the single chokepoint for all session starts through ListDockAdapter
        // (Favorites, Saved Sessions, Results Summary repeat).
        if isSpacedRepetitionEnabled && baseAffirmationCount < Constants.Session.sessionSize {
            expandedSelector = nil
            showError("At least \(Constants.Session.sessionSize) affirmations required for Reinforce mode")
            return
        }

        let sessionMode = mapDockModeToSessionMode(currentMode)
        onPlayHandler?(sessionMode, loopCount, isShuffleEnabled, isSpacedRepetitionEnabled)
    }

    // MARK: - Helpers

    private func mapDockModeToSessionMode(_ dockMode: DockMode) -> SessionMode {
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

    /// Checks whether the microphone is currently accessible.
    ///
    /// Attempts to configure `AVAudioSession` for `.playAndRecord` — if another app
    /// (Zoom, FaceTime, phone call) holds the audio session with priority, the
    /// configuration will fail. Restores the previous session category after checking.
    ///
    /// - Returns: `true` if the mic is accessible, `false` if blocked by another app.
    static func isMicrophoneAccessible() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let previousCategory = session.category
        let previousMode = session.mode
        let previousOptions = session.categoryOptions

        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            // Restore previous session state
            try? session.setCategory(previousCategory, mode: previousMode, options: previousOptions)
            return true
        } catch {
            // Restore previous session state on failure
            try? session.setCategory(previousCategory, mode: previousMode, options: previousOptions)
            return false
        }
    }
}
