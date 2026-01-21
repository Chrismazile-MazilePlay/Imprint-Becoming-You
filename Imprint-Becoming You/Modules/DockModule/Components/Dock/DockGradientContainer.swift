//
//  DockGradientContainer.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockGradientContainer

/// A gradient background view for configuration-mode screens with bottom dock.
///
/// This view provides a smooth gradient that fades scrollable content into
/// a solid background, extending properly into the bottom safe area to cover
/// the home indicator region.
///
/// ## Usage
///
/// Place this in a ZStack between your scrollable content and the dock:
///
/// ```swift
/// ZStack(alignment: .bottom) {
///     AppColors.backgroundPrimary
///         .ignoresSafeArea()
///
///     scrollableContent
///
///     DockGradientContainer()  // Fades content, extends to screen edge
///
///     AdaptiveDockContainer(adapter: adapter) {
///         AdaptiveBottomDock(adapter: adapter)
///     }
/// }
/// ```
///
/// ## Structure
///
/// ```
/// ┌─────────────────────────────┐
/// │                             │  ← Scrollable content area
/// │                             │
/// ├─────────────────────────────┤
/// │  ░░░░░░░░░░░░░░░░░░░░░░░░░  │  ← Gradient fade (80pt)
/// │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │  ← Solid (dock height)
/// │  ███████████████████████████  │  ← Solid (safe area - home indicator)
/// └─────────────────────────────┘
/// ```
public struct DockGradientContainer: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    /// Height of the dock area (excluding safe area)
    private let dockHeight: CGFloat
    
    /// Height of the gradient fade portion
    private let gradientHeight: CGFloat
    
    // MARK: - Initialization
    
    /// Creates a dock gradient container.
    ///
    /// - Parameters:
    ///   - dockHeight: Height of the dock area. Default is 110pt.
    ///   - gradientHeight: Height of the gradient fade. Default is 80pt.
    public init(
        dockHeight: CGFloat = 110,
        gradientHeight: CGFloat = 70
    ) {
        self.dockHeight = dockHeight
        self.gradientHeight = gradientHeight
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            // Gradient fade portion
            LinearGradient(
                colors: [
                    .clear,
                    tokens.backgroundPrimary.opacity(0.7),
                    tokens.backgroundPrimary
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: gradientHeight)
            
            // Solid portion for dock area (extends into safe area)
            tokens.backgroundPrimary
                .frame(height: dockHeight)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Dock Gradient Container") {
    ZStack(alignment: .bottom) {
        // Background
        Color.black
            .ignoresSafeArea()
        
        // Simulated scrollable content
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<20) { i in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 60)
                        .overlay {
                            Text("Item \(i + 1)")
                                .foregroundStyle(.white)
                        }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
        
        // Gradient container
        DockGradientContainer()
        
        // Simulated dock
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.gray.opacity(0.4))
            .frame(height: 68)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
    }
}

#Preview("Gradient Container - With Tokens") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        
        ScrollView {
            VStack(spacing: 8) {
                ForEach(0..<15) { i in
                    Text("Affirmation \(i + 1)")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 110)
        }
        
        DockGradientContainer()
        
        // Mock dock
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 68)
            
            Text("Practice 9 affirmations")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    .environment(\.dockDesignTokens, DefaultDockDesignTokens())
}
