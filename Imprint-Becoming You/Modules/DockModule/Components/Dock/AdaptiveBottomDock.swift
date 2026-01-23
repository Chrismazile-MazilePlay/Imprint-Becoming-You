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
/// This component is a **pure dock row** - it renders only the dock content and has
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
    
    /// Whether a selector animation is currently in progress.
    /// Buttons are disabled during animation to prevent double-taps.
    @State private var isAnimatingSelector = false
    
    /// The currently running animation delay Task.
    /// Tracked for cancellation on view disappear or new animation start.
    @State private var animationTask: Task<Void, Never>?
    
    /// Duration for selector animations (matches spring response).
    private let animationDuration: TimeInterval = 0.35
    
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
            .animation(tokens.standardAnimation, value: adapter.configuration)
            .onDisappear {
                // Cancel any pending animation task to prevent state updates on deallocated view
                animationTask?.cancel()
                animationTask = nil
            }
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
    
    /// Horizontal inset for aligning progress/buttons with nav button edges
    /// Small value keeps alignment subtle while maintaining width
    private var alignmentInset: CGFloat { 4 }
    
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
                .padding(.horizontal, alignmentInset)
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
                    .frame(minWidth: 80)
                
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
            .padding(.horizontal, alignmentInset)
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
    
    /// Toggles the mode selector menu with animation.
    ///
    /// Uses a guard to prevent double-taps during animation.
    /// The animation Task is tracked and cancelled on view disappear.
    func toggleModeSelector() {
        guard !isAnimatingSelector else { return }
        isAnimatingSelector = true
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if adapter.isBinauralSelectorExpanded {
                adapter.isBinauralSelectorExpanded = false
            }
            adapter.isModeSelectorExpanded.toggle()
        }
        
        // Cancel any existing task before starting a new one
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(animationDuration))
            // Only reset if task wasn't cancelled
            if !Task.isCancelled {
                isAnimatingSelector = false
            }
        }
    }
    
    /// Toggles the binaural selector menu with animation.
    ///
    /// Uses a guard to prevent double-taps during animation.
    /// The animation Task is tracked and cancelled on view disappear.
    func toggleBinauralSelector() {
        guard !isAnimatingSelector else { return }
        isAnimatingSelector = true
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if adapter.isModeSelectorExpanded {
                adapter.isModeSelectorExpanded = false
            }
            adapter.isBinauralSelectorExpanded.toggle()
        }
        
        // Cancel any existing task before starting a new one
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(animationDuration))
            // Only reset if task wasn't cancelled
            if !Task.isCancelled {
                isAnimatingSelector = false
            }
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
