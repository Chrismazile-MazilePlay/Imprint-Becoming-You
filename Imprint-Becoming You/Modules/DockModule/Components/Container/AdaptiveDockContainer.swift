//
//  AdaptiveDockContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - AdaptiveDockContainer

/// Self-sufficient dock container with optional gradient background.
///
/// Uses ZStack to layer gradient behind dock content:
/// ```
/// ZStack (alignment: .bottom)
/// ├── Back:  LinearGradient (when showsGradient)
/// └── Front: VStack (menus, dock, label)
/// ```
///
/// Parent views position at screen bottom:
/// ```swift
/// .overlay(alignment: .bottom) {
///     AdaptiveDockContainer(adapter: adapter, showsGradient: true) {
///         AdaptiveBottomDock(adapter: adapter)
///     }
/// }
/// ```
public struct AdaptiveDockContainer<Content: View>: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    public let adapter: any DockAdapterProtocol
    public let showsGradient: Bool
    @ViewBuilder public let content: () -> Content
    
    // MARK: - Constants
    
    /// Height of gradient background (dock area + fade portion)
    private let gradientHeight: CGFloat = 200
    
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
            // Back layer: gradient
            if showsGradient {
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        tokens.backgroundPrimary.opacity(0.7),
                        tokens.backgroundPrimary
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: gradientHeight)
                .allowsHitTesting(false)
            }
            
            // Front layer: dock content
            VStack(spacing: 0) {
                expandedMenus
                
                content()
                    .padding(.horizontal, tokens.spacingMD)
                    .padding(.bottom, labelText.isEmpty ? tokens.spacingSM : tokens.spacingXS)
                
                if !labelText.isEmpty {
                    Text(labelText)
                        .font(tokens.caption1)
                        .foregroundStyle(tokens.textSecondary)
                        .padding(.bottom, tokens.spacingSM)
                }
            }
            .padding(.bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    // MARK: - Computed Properties
    
    private var isAnyMenuExpanded: Bool {
        adapter.isModeSelectorExpanded || adapter.isBinauralSelectorExpanded
    }
    
    private var labelText: String {
        adapter.labelText
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
                    withAnimation(tokens.standardAnimation) {
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
                    withAnimation(tokens.standardAnimation) {
                        adapter.selectBinaural(preset)
                    }
                }
            }
            .padding(.horizontal, tokens.spacingMD)
            .padding(.bottom, tokens.spacingSM)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Previews

#Preview("Config - With Gradient") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        ScrollView {
            VStack(spacing: 8) {
                ForEach(0..<20) { i in
                    Text("Item \(i + 1)")
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 120)
        }
    }
    .overlay {
        VStack {
            Spacer()
            AdaptiveDockContainer(adapter: MockDockAdapter.favorites, showsGradient: true) {
                AdaptiveBottomDock(adapter: MockDockAdapter.favorites)
            }
            .imprintDockEnvironment()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview("Home - No Gradient") {
    ZStack {
        Color.purple.opacity(0.3).ignoresSafeArea()
    }
    .overlay {
        VStack {
            Spacer()
            AdaptiveDockContainer(adapter: MockDockAdapter.home) {
                AdaptiveBottomDock(adapter: MockDockAdapter.home)
            }
            .imprintDockEnvironment()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview("Session - No Gradient") {
    ZStack {
        Color.blue.opacity(0.2).ignoresSafeArea()
    }
    .overlay {
        VStack {
            Spacer()
            AdaptiveDockContainer(adapter: MockDockAdapter.sessionPlaying) {
                AdaptiveBottomDock(adapter: MockDockAdapter.sessionPlaying)
            }
            .imprintDockEnvironment()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
