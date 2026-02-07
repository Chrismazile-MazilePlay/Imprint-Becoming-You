//
//  ConfigurationDockAdapter.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI
import AVFoundation

// MARK: - ConfigurationDockAdapter

/// Adapter for configuration mode dock used in list and results views.
///
/// This adapter is used by:
/// - `FavoritesFullListView` - label: "Practice X affirmations"
/// - `SavedSessionsFullListView` - label: "" (empty)
/// - `ResultsSummaryView` - label: "Repeat Session"
///
/// Unlike `PracticeDockAdapter`, this adapter owns its state directly rather than
/// reading from `PracticeStore`. The parent view configures it at initialization.
///
/// ## Mode Filtering
/// The `availableModes` property excludes `.readOnly` since configuration views
/// are for starting practice sessions, not returning to browse mode.
///
/// ## Usage
///
/// ```swift
/// struct FavoritesFullListView: View {
///     @State private var dockAdapter: ConfigurationDockAdapter
///
///     init(favorites: [Affirmation], onPlay: @escaping (SessionMode, LoopConfiguration) -> Void) {
///         let adapter = ConfigurationDockAdapter(
///             labelText: "Practice \(favorites.count) affirmations",
///             isPlayEnabled: !favorites.isEmpty
///         ) { mode, loopCount, shuffle in
///             let config = LoopConfiguration(
///                 loopCount: loopCount,
///                 isShuffleEnabled: shuffle
///             )
///             onPlay(mode, config)
///         }
///         self._dockAdapter = State(initialValue: adapter)
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
@MainActor
@Observable
final class ConfigurationDockAdapter: DockAdapterProtocol {
    
    // MARK: - Configuration
    
    /// Always returns `.configuration` for this adapter.
    let configuration: DockConfiguration = .configuration
    
    // MARK: - Mode State
    
    /// The currently selected mode.
    var currentMode: DockMode = .readAloud
    
    /// Available modes for configuration (excludes readOnly).
    var availableModes: [DockMode] {
        DockMode.allCases.filter { $0 != .readOnly }
    }
    
    /// Whether the mode selector is expanded.
    var isModeSelectorExpanded: Bool = false
    
    // MARK: - Binaural State (Not Used in Configuration Mode)
    
    /// Always `.off` - binaural selector not shown in configuration mode.
    var binauralPreset: DockBinauralPreset = .off
    
    /// Always `false` - binaural selector not shown in configuration mode.
    var isBinauralSelectorExpanded: Bool = false
    
    // MARK: - Error Bar State
    
    /// Whether the error bar is visible.
    var isErrorBarVisible: Bool = false
    
    /// The current error bar message.
    private(set) var errorBarMessage: String = ""
    
    /// Task managing the auto-dismiss timer for the error bar.
    private var errorDismissTask: Task<Void, Never>?
    
    // MARK: - Session State (Not Used in Configuration Mode)
    
    /// Always `.hidden` - no center content in configuration mode.
    var centerContentState: DockCenterContentState = .hidden
    
    /// Always `nil` - no session segments in configuration mode.
    var sessionSegments: DockSessionSegments? = nil
    
    /// Always `nil` - no progress in configuration mode.
    var progress: DockProgress? = nil
    
    /// Always `false` - no navigation in configuration mode.
    var canNavigatePrevious: Bool = false
    
    /// Always `false` - no navigation in configuration mode.
    var canNavigateNext: Bool = false
    
    // MARK: - Configuration Mode State
    
    /// Current loop count (1, 3, or 5).
    var loopCount: Int = 1
    
    /// Whether shuffle is enabled.
    var isShuffleEnabled: Bool = false
    
    /// Whether the play button is enabled.
    var isPlayEnabled: Bool
    
    /// Label text displayed below the dock.
    var labelText: String
    
    // MARK: - Callbacks
    
    /// Called when play is tapped with current configuration.
    private let onPlayHandler: (SessionMode, Int, Bool) -> Void
    
    // MARK: - Initialization
    
    /// Creates a configuration mode adapter.
    ///
    /// - Parameters:
    ///   - initialMode: Starting mode selection (default: `.readAloud`)
    ///   - initialLoopCount: Starting loop count (default: `1`)
    ///   - initialShuffle: Starting shuffle state (default: `false`)
    ///   - labelText: Text displayed below the dock (e.g., "Practice 9 affirmations")
    ///   - isPlayEnabled: Whether the play button should be enabled
    ///   - onPlay: Callback when play is tapped - receives (mode, loopCount, isShuffleEnabled)
    init(
        initialMode: DockMode = .readAloud,
        initialLoopCount: Int = 1,
        initialShuffle: Bool = false,
        labelText: String = "",
        isPlayEnabled: Bool = true,
        onPlay: @escaping (SessionMode, Int, Bool) -> Void
    ) {
        self.currentMode = initialMode
        self.loopCount = initialLoopCount
        self.isShuffleEnabled = initialShuffle
        self.labelText = labelText
        self.isPlayEnabled = isPlayEnabled
        self.onPlayHandler = onPlay
    }
    
    // MARK: - Mode Actions
    
    func selectMode(_ mode: DockMode) {
        // Check mic availability for modes that require it
        if mode.requiresMicrophone && !Self.isMicrophoneAccessible() {
            // Close mode selector, then show error bar
            isModeSelectorExpanded = false
            showError("The microphone is being used by another app")
            return
        }
        
        currentMode = mode
        isModeSelectorExpanded = false
    }
    
    // MARK: - Binaural Actions (No-op)
    
    func selectBinaural(_ preset: DockBinauralPreset) {
        // Not applicable for configuration mode
    }
    
    // MARK: - Navigation Actions (No-op)
    
    func navigatePrevious() {
        // Not applicable for configuration mode
    }
    
    func navigateNext() {
        // Not applicable for configuration mode
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
    
    // MARK: - Configuration Mode Actions
    
    func cycleLoopCount() {
        switch loopCount {
        case 1:
            loopCount = 3
        case 3:
            loopCount = 5
        default:
            loopCount = 1
        }
    }
    
    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }
    
    func play() {
        guard isPlayEnabled else { return }
        
        let sessionMode = mapDockModeToSessionMode(currentMode)
        onPlayHandler(sessionMode, loopCount, isShuffleEnabled)
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

// MARK: - Convenience Initializers

extension ConfigurationDockAdapter {
    
    /// Creates an adapter for FavoritesFullListView.
    ///
    /// - Parameters:
    ///   - count: Number of favorites
    ///   - onPlay: Callback when play is tapped
    static func favorites(
        count: Int,
        onPlay: @escaping (SessionMode, Int, Bool) -> Void
    ) -> ConfigurationDockAdapter {
        ConfigurationDockAdapter(
            labelText: count > 0 ? "Practice \(count) affirmations" : "No favorites yet",
            isPlayEnabled: count > 0,
            onPlay: onPlay
        )
    }
    
    /// Creates an adapter for SavedSessionsFullListView.
    ///
    /// - Parameters:
    ///   - hasSelection: Whether a session is selected
    ///   - onPlay: Callback when play is tapped
    static func savedSessions(
        hasSelection: Bool,
        onPlay: @escaping (SessionMode, Int, Bool) -> Void
    ) -> ConfigurationDockAdapter {
        ConfigurationDockAdapter(
            labelText: "",
            isPlayEnabled: hasSelection,
            onPlay: onPlay
        )
    }
    
    /// Creates an adapter for ResultsSummaryView.
    ///
    /// - Parameters:
    ///   - initialMode: The mode from the completed session
    ///   - initialLoopCount: The loop count from the completed session
    ///   - initialShuffle: The shuffle state from the completed session
    ///   - onPlay: Callback when play is tapped
    static func resultsSummary(
        initialMode: DockMode,
        initialLoopCount: Int,
        initialShuffle: Bool,
        onPlay: @escaping (SessionMode, Int, Bool) -> Void
    ) -> ConfigurationDockAdapter {
        ConfigurationDockAdapter(
            initialMode: initialMode,
            initialLoopCount: initialLoopCount,
            initialShuffle: initialShuffle,
            labelText: "Repeat Session",
            isPlayEnabled: true,
            onPlay: onPlay
        )
    }
}
