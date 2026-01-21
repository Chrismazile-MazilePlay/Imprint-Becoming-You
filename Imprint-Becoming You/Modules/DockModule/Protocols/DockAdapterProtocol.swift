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
    /// - `.home`: Mode + Binaural selectors only (compact)
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
    
    /// Whether the mode selector menu is expanded.
    ///
    /// When `true`, the mode selector panel is visible above the dock.
    /// Setting this to `false` closes the menu.
    var isModeSelectorExpanded: Bool { get set }
    
    // MARK: - Binaural State
    
    /// The currently selected binaural preset.
    var binauralPreset: DockBinauralPreset { get }
    
    /// Whether the binaural selector menu is expanded.
    ///
    /// When `true`, the binaural selector panel is visible above the dock.
    /// Setting this to `false` closes the menu.
    var isBinauralSelectorExpanded: Bool { get set }
    
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
    
    /// Legacy progress information for backwards compatibility.
    ///
    /// - Note: Prefer using `sessionSegments` for session progress.
    ///   This property is maintained for non-session configurations.
    ///
    /// Returns `nil` when not in an active session or when progress
    /// should not be displayed.
    @available(*, deprecated, message: "Use sessionSegments instead for session progress")
    var progress: DockProgress? { get }
    
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
    
    /// Whether the play button is enabled.
    ///
    /// When `false`, the play button appears disabled.
    /// Only used when `configuration == .configuration`.
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
    
    // MARK: - Binaural Actions
    
    /// Called when the user selects a binaural preset from the selector.
    ///
    /// The adapter should update its internal state and close the selector.
    ///
    /// - Parameter preset: The newly selected preset
    func selectBinaural(_ preset: DockBinauralPreset)
    
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
    
    /// Called when the user taps the shuffle button.
    ///
    /// The adapter should toggle the shuffle state.
    func toggleShuffle()
    
    /// Called when the user taps the play button.
    ///
    /// The adapter should start the configured practice session.
    func play()
}

// MARK: - Default Implementations

public extension DockAdapterProtocol {
    
    /// Default available modes includes all cases.
    var availableModes: [DockMode] {
        DockMode.allCases
    }
    
    /// Default implementation closes both selectors.
    func closeAllSelectors() {
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
    }
    
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
}
