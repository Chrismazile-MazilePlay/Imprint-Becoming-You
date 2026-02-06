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
/// This component is a **pure dock row** â€” it renders only the dock content and has
/// no knowledge of expanded menus. Menu handling is delegated to `AdaptiveDockContainer`.
///
/// ## Configurations
///
/// | Configuration   | Layout                                          |
/// |-----------------|------------------------------------------------|
/// | `.home`         | Mode + Binaural buttons (icon + label)          |
/// | `.session`      | Progress + Nav + Center + Mode + Binaural       |
/// | `.configuration`| Mode + Loop + Shuffle + Play                    |
///
/// ## Button Consistency
/// Mode and Binaural buttons always show icon + label across all configurations.
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
    private var configurationAnimationKey: String {
        switch adapter.configuration {
        case .home:
            return "home"
        case .session:
            return "session"
        case .configuration:
            return "configuration"
        }
    }
    
    /// Key that changes only when selector expansion state changes.
    ///
    /// Combines both selector states into a single key for efficient animation tracking.
    private var selectorAnimationKey: String {
        "\(adapter.isModeSelectorExpanded)-\(adapter.isBinauralSelectorExpanded)"
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
        case .home:
            homeContent
        case .session:
            sessionContent
        case .configuration:
            configurationContent
        }
    }
}

// MARK: - Home Configuration

private extension AdaptiveBottomDock {
    
    var homeContent: some View {
        HStack(spacing: tokens.spacingMD) {
            DockMenuSelectorButton(
                icon: adapter.currentMode.iconName,
                label: adapter.currentMode.displayName,
                isExpanded: adapter.isModeSelectorExpanded,
                isActive: false
            ) {
                toggleModeSelector()
            }
            
            Spacer(minLength: 0)
            
            DockMenuSelectorButton(
                icon: adapter.binauralPreset.iconName,
                label: adapter.binauralPreset.displayName,
                isExpanded: adapter.isBinauralSelectorExpanded,
                isActive: adapter.binauralPreset.isActive
            ) {
                toggleBinauralSelector()
            }
        }
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
            
            // Bottom row: Mode + Binaural
            // Slight inset to align with progress segments
            HStack(spacing: tokens.spacingMD) {
                DockMenuSelectorButton(
                    icon: adapter.currentMode.iconName,
                    label: adapter.currentMode.displayName,
                    isExpanded: adapter.isModeSelectorExpanded,
                    isActive: false
                ) {
                    toggleModeSelector()
                }
                
                Spacer(minLength: 0)
                
                DockMenuSelectorButton(
                    icon: adapter.binauralPreset.iconName,
                    label: adapter.binauralPreset.displayName,
                    isExpanded: adapter.isBinauralSelectorExpanded,
                    isActive: adapter.binauralPreset.isActive
                ) {
                    toggleBinauralSelector()
                }
            }
            .padding(.horizontal, Constants.DockSizes.alignmentInset)
        }
    }
}

// MARK: - Configuration Mode

private extension AdaptiveBottomDock {
    
    var configurationContent: some View {
        HStack(spacing: 0) {
            DockMenuSelectorButton(
                icon: adapter.currentMode.iconName,
                label: adapter.currentMode.displayName,
                isExpanded: adapter.isModeSelectorExpanded,
                isActive: false
            ) {
                toggleModeSelector()
            }
            
            Spacer(minLength: tokens.spacingSM)
            
            HStack(spacing: tokens.spacingSM) {
                DockLoopButton(count: adapter.loopCount) {
                    adapter.cycleLoopCount()
                }
                
                DockShuffleButton(isEnabled: adapter.isShuffleEnabled) {
                    adapter.toggleShuffle()
                }
                
                DockPlayButton(isEnabled: adapter.isPlayEnabled) {
                    adapter.play()
                }
            }
        }
    }
}

// MARK: - Selector Actions

private extension AdaptiveBottomDock {
    
    func toggleModeSelector() {
        guard !isAnimatingSelector else { return }
        isAnimatingSelector = true
        
        withAnimation(.spring(
            response: Constants.UITiming.springResponse,
            dampingFraction: Constants.UITiming.springDamping
        )) {
            if adapter.isBinauralSelectorExpanded {
                adapter.isBinauralSelectorExpanded = false
            }
            // Dismiss error bar immediately when mode button tapped
            if adapter.isErrorBarVisible {
                adapter.dismissErrorBar()
            }
            adapter.isModeSelectorExpanded.toggle()
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.UITiming.standardAnimationDuration))
            isAnimatingSelector = false
        }
    }
    
    func toggleBinauralSelector() {
        guard !isAnimatingSelector else { return }
        isAnimatingSelector = true
        
        withAnimation(.spring(
            response: Constants.UITiming.springResponse,
            dampingFraction: Constants.UITiming.springDamping
        )) {
            if adapter.isModeSelectorExpanded {
                adapter.isModeSelectorExpanded = false
            }
            // Dismiss error bar immediately when binaural button tapped
            if adapter.isErrorBarVisible {
                adapter.dismissErrorBar()
            }
            adapter.isBinauralSelectorExpanded.toggle()
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
