//
//  MockDockAdapter.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - MockDockAdapter

/// A mock implementation of `DockAdapterProtocol` for SwiftUI previews and testing.
///
/// This class provides a fully functional adapter that can be configured for
/// different preview scenarios. It uses the `@Observable` macro for automatic
/// SwiftUI updates.
///
/// ## Factory Methods
///
/// The class provides static factory methods for common preview scenarios:
///
/// | Factory             | Configuration   | Description                        |
/// |---------------------|-----------------|-------------------------------------|
/// | `.home`             | `.home`         | Browse mode                         |
/// | `.sessionIdle`      | `.session`      | Session, idle waveform              |
/// | `.sessionPlaying`   | `.session`      | Session, TTS playing                |
/// | `.sessionPreparing` | `.session`      | Session, preparing to listen        |
/// | `.sessionListening` | `.session`      | Session, user speaking              |
/// | `.sessionScore`     | `.session`      | Session, showing score              |
/// | `.favorites`        | `.home`         | Favorites with label + shuffle      |
/// | `.favoritesEmpty`   | `.home`         | Favorites disabled (empty)          |
/// | `.resultsSummary`   | `.home`         | Results with "Repeat Session"       |
/// | `.savedSessions`    | `.home`         | Saved sessions, no label            |
///
/// ## Usage
///
/// ```swift
/// #Preview("Home Mode") {
///     AdaptiveBottomDock(adapter: MockDockAdapter.home)
/// }
///
/// #Preview("Session Playing") {
///     AdaptiveBottomDock(adapter: MockDockAdapter.sessionPlaying)
/// }
/// ```
///
/// ## Interactive Previews
///
/// The mock adapter is fully interactive - buttons work, selectors expand,
/// and state changes propagate to the UI:
///
/// ```swift
/// #Preview("Interactive") {
///     struct PreviewWrapper: View {
///         @State private var adapter = MockDockAdapter.home
///
///         var body: some View {
///             AdaptiveDockContainer(adapter: adapter) {
///                 AdaptiveBottomDock(adapter: adapter)
///             }
///         }
///     }
///     return PreviewWrapper()
/// }
/// ```
@Observable
@MainActor
public final class MockDockAdapter: DockAdapterProtocol {
    
    // MARK: - Configuration
    
    /// The current dock configuration.
    public var configuration: DockConfiguration = .home
    
    // MARK: - Mode State
    
    /// The currently selected mode.
    public var currentMode: DockMode = .readAndSpeak
    
    /// All available modes.
    public var availableModes: [DockMode] = DockMode.allCases
    
    /// Which selector menu is currently expanded, if any.
    public var expandedSelector: DockExpandedSelector?

    // MARK: - Music State

    /// The currently selected background music category.
    public var musicCategory: DockMusicCategory = .off

    /// The current background music volume (0.0–1.0).
    public var musicVolume: Float = 0.15

    /// Whether the shuffle option appears in the config menu.
    public var showsShuffleOption: Bool = false

    // MARK: - Session State
    
    /// The center content visualization state.
    public var centerContentState: DockCenterContentState = .idle
    
    /// Session segments for Stories-style progress display.
    public var sessionSegments: DockSessionSegments?
    
    /// Whether backward navigation is available.
    public var canNavigatePrevious: Bool = false
    
    /// Whether forward navigation is available.
    public var canNavigateNext: Bool = true
    
    // MARK: - Configuration Mode State
    
    /// The current loop count.
    public var loopCount: Int = 1
    
    /// Whether shuffle is enabled.
    public var isShuffleEnabled: Bool = false
    
    /// Whether the play button is visible above the dock.
    public var showsPlayButton: Bool = false

    /// Whether the play button is enabled (tappable).
    public var isPlayEnabled: Bool = true
    
    /// Label text displayed below the dock.
    public var labelText: String = ""
    
    // MARK: - Error Bar State
    
    /// Whether the error bar is visible.
    public var isErrorBarVisible: Bool = false
    
    /// The current error bar message.
    public var errorBarMessage: String = ""
    
    /// Task managing auto-dismiss timer.
    private var errorDismissTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Creates a new mock adapter with default values.
    public init() {}
    
    // MARK: - Mode Actions
    
    /// Handles mode selection.
    public func selectMode(_ mode: DockMode) {
        currentMode = mode
        expandedSelector = nil
        #if DEBUG
        print("[MockDockAdapter] Selected mode: \(mode.displayName)")
        #endif
    }
    
    // MARK: - Music Actions

    /// Handles background music category selection.
    public func selectMusic(_ category: DockMusicCategory) {
        musicCategory = category
        expandedSelector = nil
        #if DEBUG
        print("[MockDockAdapter] Selected music: \(category.displayName)")
        #endif
    }

    /// Handles music volume changes.
    public func setMusicVolume(_ volume: Float) {
        musicVolume = volume
        #if DEBUG
        print("[MockDockAdapter] Music volume: \(String(format: "%.2f", volume))")
        #endif
    }

    // MARK: - Navigation Actions
    
    /// Handles previous navigation.
    public func navigatePrevious() {
        guard let segments = sessionSegments, canNavigatePrevious else { return }
        
        let newIndex = max(0, segments.currentIndex - 1)
        sessionSegments = DockSessionSegments(
            configs: segments.configs,
            currentIndex: newIndex,
            isAnimating: segments.isAnimating,
            usesTimedProgress: segments.usesTimedProgress
        )
        
        updateNavigationStateForSegments()
        #if DEBUG
        print("[MockDockAdapter] Navigated to previous: \(newIndex + 1) of \(segments.totalCount)")
        #endif
    }
    
    /// Handles next navigation.
    public func navigateNext() {
        guard let segments = sessionSegments, canNavigateNext else { return }
        
        let newIndex = min(segments.totalCount - 1, segments.currentIndex + 1)
        sessionSegments = DockSessionSegments(
            configs: segments.configs,
            currentIndex: newIndex,
            isAnimating: segments.isAnimating,
            usesTimedProgress: segments.usesTimedProgress
        )
        
        updateNavigationStateForSegments()
        #if DEBUG
        print("[MockDockAdapter] Navigated to next: \(newIndex + 1) of \(segments.totalCount)")
        #endif
    }
    
    /// Closes all selector menus.
    public func closeAllSelectors() {
        expandedSelector = nil
        dismissErrorBar()
    }
    
    // MARK: - Error Bar Actions
    
    /// Shows an error message in the dock error bar.
    public func showError(_ message: String) {
        errorDismissTask?.cancel()
        errorBarMessage = message
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isErrorBarVisible = true
        }
        
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self?.isErrorBarVisible = false
            }
        }
        
        #if DEBUG
        print("[MockDockAdapter] Error shown: \(message)")
        #endif
    }
    
    /// Immediately dismisses the error bar with animation.
    public func dismissErrorBar() {
        errorDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isErrorBarVisible = false
        }
    }
    
    // MARK: - Segment Animation Callback
    
    /// Handles segment animation completion.
    public func segmentAnimationCompleted() {
        guard let segments = sessionSegments else { return }
        
        // Move to next segment if available
        let newIndex = segments.currentIndex + 1
        if newIndex < segments.totalCount {
            sessionSegments = DockSessionSegments(
                configs: segments.configs,
                currentIndex: newIndex,
                isAnimating: true,
                usesTimedProgress: segments.usesTimedProgress
            )
            updateNavigationStateForSegments()
        }
        
        #if DEBUG
        print("[MockDockAdapter] Segment animation completed, moved to index \(newIndex)")
        #endif
    }
    
    // MARK: - Configuration Mode Actions
    
    /// Cycles through loop count values.
    public func cycleLoopCount() {
        switch loopCount {
        case 1: loopCount = 3
        case 3: loopCount = 5
        default: loopCount = 1
        }
        #if DEBUG
        print("[MockDockAdapter] Loop count: \(loopCount)")
        #endif
    }

    /// Selects a specific loop count.
    public func selectLoopCount(_ count: Int) {
        guard [1, 3, 5].contains(count) else { return }
        loopCount = count
        #if DEBUG
        print("[MockDockAdapter] Selected loop count: \(count)")
        #endif
    }
    
    /// Toggles shuffle state.
    public func toggleShuffle() {
        isShuffleEnabled.toggle()
        #if DEBUG
        print("[MockDockAdapter] Shuffle: \(isShuffleEnabled)")
        #endif
    }
    
    /// Handles play button tap.
    public func play() {
        #if DEBUG
        print("[MockDockAdapter] Play tapped - Mode: \(currentMode.displayName), Loops: \(loopCount), Shuffle: \(isShuffleEnabled)")
        #endif
    }
    
    // MARK: - Private Helpers
    
    private func updateNavigationStateForSegments() {
        guard let segments = sessionSegments else { return }
        canNavigatePrevious = segments.currentIndex > 0
        canNavigateNext = segments.currentIndex < segments.totalCount - 1
    }
}

// MARK: - Factory Methods

public extension MockDockAdapter {
    
    // MARK: - Home Configuration
    
    /// Creates a mock adapter for home/browse mode.
    ///
    /// - Configuration: `.home`
    /// - Shows: Mode selector + Music selector
    /// - Use case: PracticePageView when not in session
    static var home: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .home
        adapter.currentMode = .readAndSpeak
        adapter.musicCategory = .off
        return adapter
    }
    
    // MARK: - Session Configurations
    
    /// Creates a mock adapter for session idle state.
    ///
    /// - Configuration: `.session`
    /// - Center content: Idle waveform (small dots)
    /// - Use case: Session active, waiting to start
    static var sessionIdle: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .session
        adapter.currentMode = .readAndSpeak
        adapter.musicCategory = .focus
        adapter.centerContentState = .idle
        adapter.sessionSegments = DockSessionSegments(
            configs: Array(repeating: .default, count: 5),
            currentIndex: 0,
            isAnimating: false,
            usesTimedProgress: false  // Read & Speak uses toggle mode
        )
        adapter.canNavigatePrevious = false
        adapter.canNavigateNext = true
        return adapter
    }
    
    /// Creates a mock adapter for TTS playing state.
    ///
    /// - Configuration: `.session`
    /// - Center content: Playing waveform (animated bars, accent color)
    /// - Use case: TTS is reading an affirmation
    static var sessionPlaying: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .session
        adapter.currentMode = .readAloud
        adapter.musicCategory = .nature
        adapter.centerContentState = .playing(audioLevel: 0.7)
        adapter.sessionSegments = DockSessionSegments(
            configs: Array(repeating: .default, count: 8),
            currentIndex: 2,
            isAnimating: true,
            usesTimedProgress: true  // Read Aloud uses timer mode
        )
        adapter.canNavigatePrevious = true
        adapter.canNavigateNext = true
        return adapter
    }
    
    /// Creates a mock adapter for waiting state.
    ///
    /// - Configuration: `.session`
    /// - Center content: Waiting (pulsing dots) - legacy state
    /// - Use case: Speech engine initializing before listening
    static var sessionPreparing: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .session
        adapter.currentMode = .readAndSpeak
        adapter.musicCategory = .focus
        adapter.centerContentState = .preparing
        adapter.sessionSegments = DockSessionSegments(
            configs: Array(repeating: .default, count: 5),
            currentIndex: 1,
            isAnimating: false,
            usesTimedProgress: false  // Read & Speak uses toggle mode
        )
        adapter.canNavigatePrevious = true
        adapter.canNavigateNext = true
        return adapter
    }
    
    /// Creates a mock adapter for listening state.
    ///
    /// - Configuration: `.session`
    /// - Center content: Listening waveform (animated bars, green color)
    /// - Use case: User is speaking
    static var sessionListening: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .session
        adapter.currentMode = .speakOnly
        adapter.musicCategory = .off
        adapter.centerContentState = .listening(audioLevel: 0.6)
        adapter.sessionSegments = DockSessionSegments(
            configs: Array(repeating: .default, count: 10),
            currentIndex: 3,
            isAnimating: true,
            usesTimedProgress: false  // Speak Only uses toggle mode
        )
        adapter.canNavigatePrevious = true
        adapter.canNavigateNext = true
        return adapter
    }
    
    /// Creates a mock adapter for score display state.
    ///
    /// - Configuration: `.session`
    /// - Center content: Score display (animated percentage)
    /// - Use case: Showing resonance score after speech
    static var sessionScore: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .session
        adapter.currentMode = .readAndSpeak
        adapter.musicCategory = .focus
        adapter.centerContentState = .idle
        adapter.sessionSegments = DockSessionSegments(
            configs: Array(repeating: .default, count: 5),
            currentIndex: 4,
            isAnimating: false,
            usesTimedProgress: false  // Read & Speak uses toggle mode
        )
        adapter.canNavigatePrevious = true
        adapter.canNavigateNext = false
        return adapter
    }
    
    // MARK: - List View Configurations

    /// Creates a mock adapter for favorites list.
    ///
    /// - Configuration: `.home` (unified 3-button row)
    /// - Label: "Practice X affirmations"
    /// - Shows shuffle option in config menu
    /// - Use case: FavoritesFullListView
    static var favorites: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .home
        adapter.currentMode = .readAndSpeak
        adapter.showsShuffleOption = true
        adapter.showsPlayButton = true
        adapter.loopCount = 1
        adapter.isShuffleEnabled = false
        adapter.isPlayEnabled = true
        adapter.labelText = "Practice 9 affirmations"
        return adapter
    }

    /// Creates a mock adapter for empty favorites.
    ///
    /// - Configuration: `.home` (unified 3-button row)
    /// - Play button: Disabled
    /// - Use case: FavoritesFullListView with no favorites
    static var favoritesEmpty: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .home
        adapter.currentMode = .readAndSpeak
        adapter.showsShuffleOption = true
        adapter.showsPlayButton = true
        adapter.loopCount = 1
        adapter.isShuffleEnabled = false
        adapter.isPlayEnabled = false
        adapter.labelText = "No favorites yet"
        return adapter
    }

    /// Creates a mock adapter for results summary.
    ///
    /// - Configuration: `.home` (unified 3-button row)
    /// - Label: "Repeat Session"
    /// - Shows shuffle option in config menu
    /// - Use case: ResultsSummaryView
    static var resultsSummary: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .home
        adapter.currentMode = .readAndSpeak
        adapter.showsShuffleOption = true
        adapter.showsPlayButton = true
        adapter.loopCount = 1
        adapter.isShuffleEnabled = false
        adapter.isPlayEnabled = true
        adapter.labelText = "Repeat Session"
        return adapter
    }

    /// Creates a mock adapter for saved sessions.
    ///
    /// - Configuration: `.home` (unified 3-button row)
    /// - Label: None
    /// - Shows shuffle option in config menu
    /// - Use case: SavedSessionsFullListView
    static var savedSessions: MockDockAdapter {
        let adapter = MockDockAdapter()
        adapter.configuration = .home
        adapter.currentMode = .readAloud
        adapter.showsShuffleOption = true
        adapter.showsPlayButton = true
        adapter.loopCount = 3
        adapter.isShuffleEnabled = true
        adapter.isPlayEnabled = true
        adapter.labelText = ""
        return adapter
    }
}

// MARK: - Preview Helpers

public extension MockDockAdapter {
    
    /// Simulates TTS playback by animating audio level.
    ///
    /// This is useful for interactive previews that want to show
    /// the waveform animation in action.
    ///
    /// - Parameter duration: How long to simulate playback
    func simulatePlayback(duration: TimeInterval = 3.0) {
        centerContentState = .playing(audioLevel: 0.5)
        
        // In a real implementation, this would use a timer
        // to animate the audio level. For mock purposes,
        // we just set a static level.
    }
    
    /// Simulates listening by animating audio level.
    ///
    /// - Parameter duration: How long to simulate listening
    func simulateListening(duration: TimeInterval = 2.0) {
        centerContentState = .listening(audioLevel: 0.6)
    }
    
    /// Simulates showing a score with animation.
    ///
    /// - Parameter score: The score to display (0-100)
    func simulateScore(_ score: Int) {
        centerContentState = .settling

        // Delay before returning to idle (simulating transition)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            centerContentState = .idle
        }
    }
}

// MARK: - Previews

#Preview("Mock Adapter - Home") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Text("Home Configuration")
                .foregroundStyle(.white)
            
            Spacer()
            
            // Placeholder for dock (actual dock views in Phase 2)
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 68)
                .overlay {
                    Text("Mode: \(MockDockAdapter.home.currentMode.displayName)")
                        .foregroundStyle(.white)
                }
                .padding()
        }
    }
}

#Preview("Mock Adapter - Session") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Text("Session Configuration")
                .foregroundStyle(.white)
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 155)
                .overlay {
                    VStack {
                        Text("Center: \(String(describing: MockDockAdapter.sessionPlaying.centerContentState))")
                        Text("Progress: \(MockDockAdapter.sessionPlaying.sessionSegments?.displayString ?? "N/A")")
                    }
                    .foregroundStyle(.white)
                    .font(.caption)
                }
                .padding()
        }
    }
}

#Preview("Mock Adapter - Configuration") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Text("Configuration Mode")
                .foregroundStyle(.white)
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 68)
                .overlay {
                    VStack {
                        Text("Label: \(MockDockAdapter.favorites.labelText)")
                        Text("Loops: \(MockDockAdapter.favorites.loopCount)")
                    }
                    .foregroundStyle(.white)
                    .font(.caption)
                }
                .padding()
        }
    }
}
