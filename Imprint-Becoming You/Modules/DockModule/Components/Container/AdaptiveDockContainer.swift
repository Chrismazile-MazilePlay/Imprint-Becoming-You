//
//  AdaptiveDockContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - AdaptiveDockContainer

/// Top-level container managing dock layout, play button, label, and expanded menus.
///
/// This container wraps `AdaptiveBottomDock` and handles:
/// - Play button (conditional, above dock row)
/// - Expanded selector menus (Mode, Binaural, Config/Settings)
/// - Label text (conditional, below dock row)
/// - Optional gradient background
/// - Error bar display
///
/// The play button and expanded menus share the same vertical space via a
/// `ZStack`. Menus render in front of (Z-above) the play button, so they
/// float on top without pushing the dock content down.
///
/// Menu dismiss is handled by the host views (not this container).
/// Host views add tap gestures to their native content areas to close
/// expanded menus, avoiding overlay insertion/removal artifacts.
///
/// ## Structure
///
/// ```
/// VStack:
///   ZStack {
///     Play button  (Z-back, right-aligned)
///     Menus        (Z-front, full width)
///   }
///   Dock row       (via content closure)
///   Label text     (optional)
/// ```
///
/// ## Menu Alignment
///
/// - Mode selector: **left-aligned** (expands toward center from left button)
/// - Binaural selector: **left-aligned** (expands from left button position)
/// - Config selector: **right-aligned** (matches gear button position)
///
/// ## Usage
///
/// ```swift
/// AdaptiveDockContainer(adapter: myAdapter) {
///     AdaptiveBottomDock(adapter: myAdapter)
/// }
/// ```
public struct AdaptiveDockContainer<Content: View>: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    public let adapter: any DockAdapterProtocol
    public let showsGradient: Bool
    @ViewBuilder public let content: () -> Content
    
    // MARK: - Initialization
    
    public init(
        adapter: any DockAdapterProtocol,
        showsGradient: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.adapter = adapter
        self.showsGradient = showsGradient
        self.content = content
    }
    
    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Play button + expanded menus share the same vertical space.
            // Menus render in front of (Z-above) the play button so they
            // float on top without pushing dock content down.
            //
            // The ZStack must be unconditionally present so that child menu
            // transitions (.move(edge: .bottom)) fire correctly. If gated by
            // an `if`, SwiftUI inserts the entire ZStack as a new view on
            // first menu open, swallowing the child transition into a fade.
            ZStack(alignment: .bottomTrailing) {
                // Play button (Z-back) — right-aligned above dock row
                if adapter.showsPlayButton {
                    DockPlayButton(isEnabled: adapter.isPlayEnabled) {
                        adapter.play()
                    }
                    .padding(.trailing, tokens.spacingLG)
                    .padding(.bottom, tokens.spacingMD)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Expanded menus (Z-front) — float above play button
                expandedMenus
            }

            // Dock row (just the button row / session content)
            content()
                .padding(.horizontal, tokens.spacingMD)

            // Label text — below dock row
            if !adapter.labelText.isEmpty {
                Text(adapter.labelText)
                    .font(tokens.caption1)
                    .foregroundStyle(tokens.textSecondary)
                    .padding(.top, tokens.spacingSM)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, tokens.dockBottomPadding)
        .background(alignment: .bottom) {
            if showsGradient {
                gradientBackground
            }
        }
    }

    // MARK: - Expanded Menus
    
    @ViewBuilder
    private var expandedMenus: some View {
        // Binaural selector — left-aligned (matches left binaural button)
        if adapter.expandedSelector == .binaural {
            HStack {
                BinauralSelectorExpanded(
                    selectedPreset: adapter.binauralPreset
                ) { preset in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        adapter.selectBinaural(preset)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.bottom, tokens.spacingSM)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Mode selector — left-aligned
        if adapter.expandedSelector == .mode {
            HStack {
                ModeSelectorExpanded(
                    modes: adapter.availableModes,
                    selectedMode: adapter.currentMode
                ) { mode in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        adapter.selectMode(mode)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.bottom, tokens.spacingSM)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Config selector — right-aligned (matches right gear button)
        if adapter.expandedSelector == .config {
            HStack {
                Spacer(minLength: 0)
                ConfigSelectorExpanded(
                    loopCount: adapter.loopCount,
                    isShuffleEnabled: adapter.isShuffleEnabled,
                    showsShuffleOption: adapter.showsShuffleOption,
                    onSelectLoopCount: { count in
                        adapter.selectLoopCount(count)
                    },
                    onToggleShuffle: {
                        adapter.toggleShuffle()
                    }
                )
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.bottom, tokens.spacingSM)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        // Error bar
        if adapter.isErrorBarVisible {
            DockErrorBar(message: adapter.errorBarMessage)
                .padding(.horizontal, tokens.spacingMD)
                .padding(.bottom, tokens.spacingSM)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Gradient Background
    
    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                tokens.backgroundPrimary.opacity(0),
                tokens.backgroundPrimary.opacity(0.8),
                tokens.backgroundPrimary
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 180)
        .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Container - Home") {
    struct PreviewWrapper: View {
        @State private var adapter = MockDockAdapter.home
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                AdaptiveDockContainer(adapter: adapter) {
                    AdaptiveBottomDock(adapter: adapter)
                }
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Container - Session") {
    struct PreviewWrapper: View {
        @State private var adapter = MockDockAdapter.sessionPlaying
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                AdaptiveDockContainer(adapter: adapter) {
                    AdaptiveBottomDock(adapter: adapter)
                }
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Container - Config with Gradient") {
    struct PreviewWrapper: View {
        @State private var adapter = MockDockAdapter.favorites
        
        var body: some View {
            ZStack {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(0..<20) { i in
                            Text("Affirmation \(i + 1)")
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                }
                
                AdaptiveDockContainer(adapter: adapter, showsGradient: true) {
                    AdaptiveBottomDock(adapter: adapter)
                }
            }
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}

#Preview("Container - Play + Menu Z-Layer") {
    struct PreviewWrapper: View {
        @State private var adapter: MockDockAdapter = {
            let a = MockDockAdapter.favorites
            a.expandedSelector = .mode
            return a
        }()

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                // Simulate consumer overlay layout
                VStack {
                    Spacer()
                    AdaptiveDockContainer(adapter: adapter, showsGradient: true) {
                        AdaptiveBottomDock(adapter: adapter)
                    }
                    .imprintDockEnvironment()
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
    return PreviewWrapper()
}

#Preview("Container - Mode Selector Open") {
    struct PreviewWrapper: View {
        @State private var adapter: MockDockAdapter = {
            let a = MockDockAdapter.home
            a.expandedSelector = .mode
            return a
        }()
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                AdaptiveDockContainer(adapter: adapter) {
                    AdaptiveBottomDock(adapter: adapter)
                }
            }
        }
    }
    return PreviewWrapper()
}
