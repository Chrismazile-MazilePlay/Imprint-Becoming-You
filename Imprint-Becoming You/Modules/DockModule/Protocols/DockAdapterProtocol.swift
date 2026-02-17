//
//  DockAdapterProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockAdapterProtocol

/// The single interface between the Dock Module and host application.
///
/// This protocol defines all state and actions that the dock needs from the host app.
/// The host app creates a concrete adapter that maps its internal state to these
/// module-owned types, maintaining complete decoupling.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │              HOST APP                   │
/// │  ┌───────────────────────────────────┐  │
/// │  │ HostAppDockAdapter                │  │
/// │  │   - Maps app state → dock types   │  │
/// │  │   - Routes actions → app logic    │  │
/// │  └───────────────┬───────────────────┘  │
/// └──────────────────┼──────────────────────┘
///                    │ Protocol Boundary
///                    ▼
/// ┌─────────────────────────────────────────┐
/// │            DOCK MODULE                  │
/// │  ┌───────────────────────────────────┐  │
/// │  │ AdaptiveDockContainer             │  │
/// │  │   └─ AdaptiveBottomDock           │  │
/// │  │       └─ Components...            │  │
/// │  └───────────────────────────────────┘  │
/// └─────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// // Host app creates adapter
/// @Observable
/// final class MyDockAdapter: DockAdapterProtocol {
///     // Map host state to dock types
///     var configuration: DockConfiguration { ... }
///     var currentMode: DockMode { ... }
///     // ... implement all requirements
/// }
///
/// // Use in view
/// AdaptiveDockContainer(adapter: myAdapter) {
///     AdaptiveBottomDock(adapter: myAdapter)
/// }
/// ```
///
/// ## Thread Safety
///
/// This protocol is isolated to `@MainActor` because all UI state access
/// and mutations must occur on the main thread for SwiftUI compatibility.
@MainActor
public protocol DockAdapterProtocol: AnyObject, Observable {
    
    // MARK: - Configuration
    
    /// The current dock configuration determining layout.
    ///
    /// This drives which slots are visible:
    /// - `.home`: Mode + Music selectors only (compact)
    /// - `.session`: Full expanded dock with progress, navigation, center content
    /// - `.configuration`: Mode + Loop + Shuffle + Play (compact)
    var configuration: DockConfiguration { get }
    
    // MARK: - Mode State
    
    /// The currently selected practice mode.
    var currentMode: DockMode { get }
    
    /// All modes available for selection.
    ///
    /// The dock will display these modes in the mode selector menu.
    /// Order is preserved in the UI.
    var availableModes: [DockMode] { get }
    
    /// Which selector menu is currently expanded, if any.
    ///
    /// Only one selector can be open at a time — enforced by the type system.
    /// Setting to `nil` closes all selector menus.
    ///
    /// - `.mode`: Mode selector panel visible above dock
    /// - `.music`: Music category selector panel visible above dock
    /// - `.config`: Config/settings panel visible above dock
    var expandedSelector: DockExpandedSelector? { get set }

    // MARK: - Music State

    /// The currently selected background music category.
    var musicCategory: DockMusicCategory { get }

    /// The current background music volume (0.0–1.0).
    ///
    /// Default is `0.15`. The dock's volume slider reads and writes this value.
    var musicVolume: Float { get }

    /// The current music playback mode (repeat single track or shuffle).
    var musicPlaybackMode: DockMusicPlaybackMode { get }

    /// Called when the user adjusts the music volume slider.
    ///
    /// The adapter should forward the value to the audio service for
    /// real-time volume adjustment.
    ///
    /// - Parameter volume: The new volume (0.0–1.0)
    func setMusicVolume(_ volume: Float)

    /// Whether the shuffle option appears in the config menu.
    ///
    /// Returns `false` on the home screen (no predefined set to shuffle).
    /// Returns `true` on Favorites, Saved Sessions, and Results views.
    var showsShuffleOption: Bool { get }

    // MARK: - Session State (Session Configuration Only)
    
    /// The current state of the center content slot.
    ///
    /// This determines what visualization is shown in the center area
    /// during active sessions (waveform, score, etc.).
    ///
    /// Only used when `configuration == .session`.
    var centerContentState: DockCenterContentState { get }
    
    /// Session segments configuration for Stories-style progress.
    ///
    /// The dock uses this to render and animate progress segments.
    /// The dock owns the animation timer and calls `segmentAnimationCompleted()`
    /// when a segment's timer naturally completes (triggering auto-advance).
    ///
    /// Returns `nil` when not in an active session.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// var sessionSegments: DockSessionSegments? {
    ///     guard isSessionActive else { return nil }
    ///
    ///     let configs = sessionAffirmations.map { affirmation in
    ///         DockSegmentConfig.forSpeechDuration(affirmation.speechDuration)
    ///     }
    ///
    ///     return DockSessionSegments(
    ///         configs: configs,
    ///         currentIndex: sessionIndex,
    ///         isAnimating: shouldAnimateSegment
    ///     )
    /// }
    /// ```
    ///
    /// Only used when `configuration == .session`.
    var sessionSegments: DockSessionSegments? { get }
    
    /// Whether backward navigation is available.
    ///
    /// When `false`, the previous button is disabled.
    /// Typically `false` on the first item.
    var canNavigatePrevious: Bool { get }
    
    /// Whether forward navigation is available.
    ///
    /// When `false`, the next button is disabled.
    /// Typically `false` on the last item.
    var canNavigateNext: Bool { get }
    
    // MARK: - Configuration Mode State (Configuration Only)
    
    /// The current loop count setting.
    ///
    /// Valid values are typically 1, 3, or 5.
    /// Only used when `configuration == .configuration`.
    var loopCount: Int { get }
    
    /// Whether shuffle is enabled.
    ///
    /// Only used when `configuration == .configuration`.
    var isShuffleEnabled: Bool { get }

    /// Whether spaced repetition is enabled.
    ///
    /// When enabled, the session doubles to 2x segments by interleaving
    /// randomized repeats. Each affirmation appears 1-3 times total.
    ///
    /// Only used when `configuration == .configuration`.
    var isSpacedRepetitionEnabled: Bool { get }

    /// Whether the play button is visible above the dock.
    ///
    /// When `true`, the play button renders above the dock background.
    /// The `isPlayEnabled` property controls whether it's tappable or greyed out.
    /// Default: `false` (hidden on home/session screens).
    var showsPlayButton: Bool { get }

    /// Whether the play button is enabled (tappable).
    ///
    /// When `false`, the play button appears greyed out and non-interactive.
    /// Only relevant when `showsPlayButton` is `true`.
    var isPlayEnabled: Bool { get }
    
    /// Optional label text displayed below the dock.
    ///
    /// Examples: "Practice 9 affirmations", "Repeat Session"
    /// Empty string means no label is shown.
    /// Only used when `configuration == .configuration`.
    var labelText: String { get }
    
    // MARK: - Mode Actions
    
    /// Called when the user selects a mode from the selector.
    ///
    /// The adapter should update its internal state and close the selector.
    ///
    /// - Parameter mode: The newly selected mode
    func selectMode(_ mode: DockMode)
    
    // MARK: - Music Actions

    /// Called when the user selects a background music category from the selector.
    ///
    /// The adapter should update its internal state. The menu remains open
    /// (non-dismissing pattern) so users can adjust volume and transport controls.
    ///
    /// - Parameter category: The newly selected music category
    func selectMusic(_ category: DockMusicCategory)

    /// Called when the user taps the skip-forward button in the music controls.
    func skipMusicForward()

    /// Called when the user taps the skip-backward button in the music controls.
    func skipMusicBackward()

    /// Called when the user taps the repeat or shuffle button to select that mode.
    ///
    /// If the requested mode is already active, the implementation should no-op.
    ///
    /// - Parameter mode: The playback mode to activate
    func selectMusicPlaybackMode(_ mode: DockMusicPlaybackMode)

    // MARK: - Navigation Actions
    
    /// Called when the user taps the previous navigation button.
    ///
    /// The adapter should navigate to the previous item if available.
    func navigatePrevious()
    
    /// Called when the user taps the next navigation button.
    ///
    /// The adapter should navigate to the next item if available.
    func navigateNext()
    
    // MARK: - Selector Actions
    
    /// Called to close all expanded selector menus.
    ///
    /// This is typically called when the user taps outside the menus
    /// or when a selection is made.
    func closeAllSelectors()
    
    // MARK: - Segment Animation Callback
    
    /// Called by the dock when a segment's animation timer completes.
    ///
    /// This callback fires when the current segment fills from 0% to 100%
    /// over its configured duration WITHOUT user interruption.
    ///
    /// The host should:
    /// 1. Auto-advance to the next affirmation
    /// 2. Update `sessionSegments.currentIndex`
    /// 3. Set `sessionSegments.isAnimating = true` to start next segment
    ///
    /// This callback does NOT fire when:
    /// - User swipes to navigate (host handles this separately)
    /// - User taps navigation buttons (host handles this separately)
    /// - Animation is paused or stopped
    ///
    /// ## Implementation Example
    ///
    /// ```swift
    /// func segmentAnimationCompleted() {
    ///     store.send(.segmentTimerCompleted)
    /// }
    /// ```
    func segmentAnimationCompleted()
    
    // MARK: - Configuration Mode Actions
    
    /// Called when the user taps the loop button.
    ///
    /// The adapter should cycle through available loop counts (e.g., 1 → 3 → 5 → 1).
    func cycleLoopCount()

    /// Called when the user selects a specific loop count from the config menu.
    ///
    /// - Parameter count: The selected loop count (1, 3, or 5)
    func selectLoopCount(_ count: Int)

    /// Called when the user taps the shuffle button.
    ///
    /// The adapter should toggle the shuffle state.
    func toggleShuffle()

    /// Called when the user taps the spaced repetition (Reinforce) button.
    ///
    /// The adapter should toggle the spaced repetition state.
    func toggleSpacedRepetition()

    // MARK: - Loop Page Navigation

    /// Whether the extended loop page is active.
    ///
    /// When `false` (default), the config menu shows base loop options `[1, 3, 5]`.
    /// When `true`, the config menu shows extended options `[2, 6, 10]`.
    var isExtendedLoopPage: Bool { get }

    /// Called when the user taps the loop page arrow.
    ///
    /// The adapter should toggle `isExtendedLoopPage` and map the current
    /// `loopCount` to the corresponding value on the target page.
    func navigateLoopPage()

    /// Called when the user taps the play button.
    ///
    /// The adapter should start the configured practice session.
    func play()
    
    // MARK: - Error Bar State
    
    /// Whether the error bar is currently visible above the dock.
    ///
    /// When `true`, the error bar panel is expanded with `errorBarMessage`.
    /// Setting to `false` collapses the error bar.
    var isErrorBarVisible: Bool { get set }
    
    /// The message displayed in the error bar.
    ///
    /// Only relevant when `isErrorBarVisible` is `true`.
    var errorBarMessage: String { get }
    
    /// Shows an error message in the dock error bar with auto-dismiss.
    ///
    /// The error bar collapses mode/music selectors before appearing,
    /// then auto-dismisses after 3 seconds. Tapping mode or music buttons
    /// immediately dismisses it.
    ///
    /// - Parameter message: The user-facing error message to display
    func showError(_ message: String)
    
    /// Immediately dismisses the error bar.
    func dismissErrorBar()
}

// MARK: - Default Implementations

public extension DockAdapterProtocol {
    
    /// Default available modes includes all cases.
    var availableModes: [DockMode] {
        DockMode.allCases
    }
    
    /// Default implementation closes all selectors and error bar.
    func closeAllSelectors() {
        expandedSelector = nil
        isErrorBarVisible = false
    }

    /// Default music volume — matches `BackgroundMusicService` initial volume.
    var musicVolume: Float { 0.15 }

    /// Default music volume setter — no-op.
    func setMusicVolume(_ volume: Float) { }

    /// Default music playback mode — repeat.
    var musicPlaybackMode: DockMusicPlaybackMode { .repeatTrack }

    /// Default skip forward — no-op.
    func skipMusicForward() { }

    /// Default skip backward — no-op.
    func skipMusicBackward() { }

    /// Default select playback mode — no-op.
    func selectMusicPlaybackMode(_ mode: DockMusicPlaybackMode) { }

    /// Default shuffle option visibility — hidden.
    var showsShuffleOption: Bool { false }

    /// Default play button visibility — hidden.
    var showsPlayButton: Bool { false }

    /// Default spaced repetition state — disabled.
    var isSpacedRepetitionEnabled: Bool { false }

    /// Default spaced repetition toggle — no-op.
    func toggleSpacedRepetition() { }

    /// Default loop count selection — no-op.
    func selectLoopCount(_ count: Int) { }

    /// Default extended loop page state — base page.
    var isExtendedLoopPage: Bool { false }

    /// Default loop page navigation — no-op.
    func navigateLoopPage() { }
    
    /// Default session segments returns nil (no session active).
    var sessionSegments: DockSessionSegments? {
        nil
    }
    
    /// Default segment animation callback does nothing.
    ///
    /// Override in adapters that use session segments.
    func segmentAnimationCompleted() {
        // No-op by default
    }
    
    /// Default error bar state — not visible.
    var isErrorBarVisible: Bool {
        get { false }
        set { }
    }
    
    /// Default error bar message — empty.
    var errorBarMessage: String { "" }
    
    /// Default show error — no-op.
    func showError(_ message: String) { }
    
    /// Default dismiss error bar — no-op.
    func dismissErrorBar() { }
}
