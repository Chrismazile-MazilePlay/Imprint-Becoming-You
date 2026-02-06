//
//  AdaptiveDockContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - AdaptiveDockContainer

/// Top-level container managing dock layout, expanded menus, and dismiss behavior.
///
/// This container wraps `AdaptiveBottomDock` and handles:
/// - Expanded selector menus (Mode, Binaural)
/// - Dismiss overlay for closing menus
/// - Optional gradient background
/// - Optional label display below dock
///
/// ## Structure
///
/// ```
/// ┌───────────────────────────────────┐
/// │         (Dismiss Overlay)         │
/// ├───────────────────────────────────┤
/// │    [Expanded Menu - if visible]   │
/// ├───────────────────────────────────┤
/// │    [Dock Content - via content]   │
/// ├───────────────────────────────────┤
/// │    [Label - if present]           │
/// └───────────────────────────────────┘
/// ```
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
        ZStack(alignment: .bottom) {
            // Dismiss overlay
            if isAnyMenuExpanded {
                dismissOverlay
            }
            
            // Main content stack
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                
                // Expanded menus (slide up from bottom)
                expandedMenus
                
                // Dock content
                content()
                    .padding(.horizontal, tokens.spacingMD)
                    .padding(.bottom, labelText.isEmpty ? tokens.dockBottomPadding : tokens.spacingSM)
                
                // Optional label
                if !labelText.isEmpty {
                    Text(labelText)
                        .font(tokens.caption1)
                        .foregroundStyle(tokens.textSecondary)
                        .padding(.bottom, tokens.dockBottomPadding)
                }
            }
        }
        .background(alignment: .bottom) {
            if showsGradient {
                gradientBackground
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isAnyMenuExpanded: Bool {
        adapter.isModeSelectorExpanded || adapter.isBinauralSelectorExpanded || adapter.isErrorBarVisible
    }
    
    private var labelText: String {
        adapter.labelText
    }
    
    // MARK: - Dismiss Overlay
    
    private var dismissOverlay: some View {
        Color.black.opacity(0.01)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    adapter.closeAllSelectors()
                }
            }
    }
    
    // MARK: - Expanded Menus
    
    @ViewBuilder
    private var expandedMenus: some View {
        if adapter.isModeSelectorExpanded {
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
        
        if adapter.isBinauralSelectorExpanded {
            HStack {
                Spacer(minLength: 0)
                BinauralSelectorExpanded(
                    selectedPreset: adapter.binauralPreset
                ) { preset in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        adapter.selectBinaural(preset)
                    }
                }
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.bottom, tokens.spacingSM)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        
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

#Preview("Container - Mode Selector Open") {
    struct PreviewWrapper: View {
        @State private var adapter: MockDockAdapter = {
            let a = MockDockAdapter.home
            a.isModeSelectorExpanded = true
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
