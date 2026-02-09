//
//  AdaptiveBottomDock.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - AdaptiveBottomDock

/// The unified morphing bottom dock that adapts its content based on configuration.
///
/// This component is a **pure dock row** — it renders only the dock content and has
/// no knowledge of expanded menus. Menu handling is delegated to `AdaptiveDockContainer`.
///
/// ## Unified 3-Button Row
///
/// All configurations share a unified bottom row:
/// ```
/// (Binaural)    [Mode ▼]    (⚙)
/// ```
///
/// Binaural and Gear are circular icon-only buttons (`DockCircularButton`).
/// Mode is a chip with icon + label + chevron (`DockMenuSelectorButton`).
/// Both circular buttons share the same fixed width, keeping Mode centered.
///
/// | Configuration   | Layout                                          |
/// |-----------------|------------------------------------------------|
/// | `.home`         | Binaural + Mode + Settings (unified row)        |
/// | `.session`      | Progress + Nav + Center + unified row            |
/// | `.configuration`| Routes to `.home` layout (deprecated)            |
///
/// ## Animation Optimization (Issue 2.3)
/// Uses computed animation keys to prevent unnecessary re-renders:
/// - `configurationAnimationKey`: Only changes when configuration type changes
/// - `selectorAnimationKey`: Only changes when selector expansion state changes
///
/// ## Usage
///
/// ```swift
/// AdaptiveBottomDock(adapter: myDockAdapter)
/// ```
public struct AdaptiveBottomDock: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    public let adapter: any DockAdapterProtocol
    
    // MARK: - Animation State
    
    @State private var isAnimatingSelector = false
    
    // MARK: - Computed Animation Keys
    
    /// Key that changes only when configuration type changes.
    ///
    /// Using a String key instead of the full `DockConfiguration` prevents
    /// animation triggers from internal property changes that don't affect layout.
    /// `.configuration` routes to "home" since both use the unified 3-button row.
    private var configurationAnimationKey: String {
        switch adapter.configuration {
        case .home, .configuration:
            return "home"
        case .session:
            return "session"
        }
    }

    /// Key that changes only when selector expansion state changes.
    ///
    /// Uses the expanded selector enum for efficient animation tracking.
    private var selectorAnimationKey: DockExpandedSelector? {
        adapter.expandedSelector
    }
    
    // MARK: - Initialization
    
    public init(adapter: any DockAdapterProtocol) {
        self.adapter = adapter
    }
    
    // MARK: - Body
    
    public var body: some View {
        mainContent
            .padding(.horizontal, tokens.spacingLG)
            .padding(.vertical, tokens.spacingMD)
            .background(dockBackground)
            // Animate only on meaningful configuration changes
            .animation(tokens.standardAnimation, value: configurationAnimationKey)
    }
    
    // MARK: - Background
    
    private var dockBackground: some View {
        RoundedRectangle(cornerRadius: tokens.cornerRadiusExtraLarge)
            .fill(tokens.backgroundSecondary.opacity(0.95))
            .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
    }
    
    // MARK: - Main Content Router
    
    @ViewBuilder
    private var mainContent: some View {
        switch adapter.configuration {
        case .home, .configuration:
            homeContent
        case .session:
            sessionContent
        }
    }
}

// MARK: - Unified 3-Button Row

private extension AdaptiveBottomDock {

    /// Whether the gear button should show as active.
    ///
    /// Active when loop count > 1 or shuffle is enabled, indicating
    /// non-default configuration.
    var isConfigActive: Bool {
        adapter.loopCount > 1 || adapter.isShuffleEnabled
    }

    /// The unified 3-button row: (Binaural) — [Mode ▼] — (⚙).
    ///
    /// Binaural and Gear are circular icon-only buttons. Mode is a chip with
    /// icon + label + chevron. Since both circular buttons share the same fixed
    /// width (`chipHeight` = 44pt), the Spacers distribute equally, keeping the
    /// Mode chip perfectly centered.
    ///
    /// Used in both `.home` and `.session` configurations.
    var unifiedButtonRow: some View {
        HStack(spacing: tokens.spacingMD) {
            // Binaural (left) — circular icon-only
            DockCircularButton(
                icon: adapter.binauralPreset.iconName,
                isExpanded: adapter.expandedSelector == .binaural,
                isActive: adapter.binauralPreset.isActive,
                accessibilityLabel: adapter.binauralPreset.accessibilityLabel
            ) {
                toggleSelector(.binaural)
            }

            Spacer(minLength: 0)

            // Mode (center) — chip with icon + label + chevron
            DockMenuSelectorButton(
                icon: adapter.currentMode.iconName,
                label: adapter.currentMode.displayName,
                isExpanded: adapter.expandedSelector == .mode,
                isActive: false
            ) {
                toggleSelector(.mode)
            }

            Spacer(minLength: 0)

            // Gear / Settings (right) — circular icon-only
            DockCircularButton(
                icon: "gearshape.fill",
                isExpanded: adapter.expandedSelector == .config,
                isActive: isConfigActive,
                accessibilityLabel: "Settings"
            ) {
                toggleSelector(.config)
            }
        }
    }

    /// Home content — the unified 3-button row.
    var homeContent: some View {
        unifiedButtonRow
    }
}

// MARK: - Session Configuration

private extension AdaptiveBottomDock {

    var sessionContent: some View {
        VStack(spacing: tokens.spacingMD) {
            // Progress segments - slight inset for visual alignment
            if let segments = adapter.sessionSegments {
                DockSegmentsView(
                    segments: segments,
                    onSegmentCompleted: {
                        adapter.segmentAnimationCompleted()
                    }
                )
                .padding(.horizontal, Constants.DockSizes.alignmentInset)
            }

            // Center row: Nav + Content + Nav
            HStack(spacing: 0) {
                DockNavigationButton(
                    direction: .previous,
                    isEnabled: adapter.canNavigatePrevious
                ) {
                    adapter.navigatePrevious()
                }

                Spacer(minLength: 0)

                DockCenterContentView(state: adapter.centerContentState)
                    .frame(minWidth: Constants.DockSizes.centerContentMinWidth)

                Spacer(minLength: 0)

                DockNavigationButton(
                    direction: .next,
                    isEnabled: adapter.canNavigateNext
                ) {
                    adapter.navigateNext()
                }
            }

            // Bottom row: Unified 3-button row
            // Slight inset to align with progress segments
            unifiedButtonRow
                .padding(.horizontal, Constants.DockSizes.alignmentInset)
        }
    }
}

// MARK: - Selector Actions

private extension AdaptiveBottomDock {

    /// Toggles the specified selector menu.
    ///
    /// Handles all selector types (mode, binaural, config) through a single
    /// function. Since `expandedSelector` is a single optional enum, opening
    /// one selector automatically closes any other — no manual close-before-open
    /// logic needed.
    ///
    /// During an active session (`.session` configuration), tapping the gear
    /// shows an error bar instead of opening the config menu.
    ///
    /// - Parameter selector: The selector to toggle
    func toggleSelector(_ selector: DockExpandedSelector) {
        // Block config during active session — show error instead
        if selector == .config && adapter.configuration == .session {
            adapter.showError("Settings can't be changed during a session")
            return
        }

        guard !isAnimatingSelector else { return }
        isAnimatingSelector = true

        withAnimation(.spring(
            response: Constants.UITiming.springResponse,
            dampingFraction: Constants.UITiming.springDamping
        )) {
            adapter.dismissErrorBar()
            adapter.expandedSelector = (adapter.expandedSelector == selector) ? nil : selector
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.UITiming.standardAnimationDuration))
            isAnimatingSelector = false
        }
    }
}

// MARK: - Previews

#Preview("Dock - Home") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            AdaptiveBottomDock(adapter: MockDockAdapter.home)
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
    }
}

#Preview("Dock - Session Playing") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            AdaptiveBottomDock(adapter: MockDockAdapter.sessionPlaying)
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
    }
}

#Preview("Dock - Configuration") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            AdaptiveBottomDock(adapter: MockDockAdapter.favorites)
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
    }
}
