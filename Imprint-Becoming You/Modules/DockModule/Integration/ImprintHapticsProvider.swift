//
//  ImprintHapticsProvider.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import Foundation

// MARK: - ImprintHapticsProvider

/// Haptics provider that wraps the existing `HapticFeedback` enum.
///
/// This bridges the app's existing haptic system to the DockModule's
/// `DockHapticsProvider` protocol, maintaining complete decoupling.
///
/// ## Usage
///
/// Inject into the dock's environment:
///
/// ```swift
/// AdaptiveDockContainer(adapter: adapter) {
///     AdaptiveBottomDock(adapter: adapter)
/// }
/// .environment(\.dockHapticsProvider, ImprintHapticsProvider())
/// ```
///
/// Or set once at a higher level in your view hierarchy.
public struct ImprintHapticsProvider: DockHapticsProvider {
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Selection
    
    public func selectionFeedback() {
        HapticFeedback.selection()
    }
    
    // MARK: - Impact
    
    public func lightImpact() {
        HapticFeedback.impact(.light)
    }
    
    public func mediumImpact() {
        HapticFeedback.impact(.medium)
    }
    
    public func heavyImpact() {
        HapticFeedback.impact(.heavy)
    }
    
    // MARK: - Notification
    
    public func successNotification() {
        HapticFeedback.notification(.success)
    }
    
    public func warningNotification() {
        HapticFeedback.notification(.warning)
    }
    
    public func errorNotification() {
        HapticFeedback.notification(.error)
    }
}

// MARK: - Environment Setup Extension

import SwiftUI

public extension View {
    
    /// Configures the dock with Imprint's haptics and design tokens.
    ///
    /// Apply this modifier to the view containing the dock:
    ///
    /// ```swift
    /// AdaptiveDockContainer(adapter: adapter) {
    ///     AdaptiveBottomDock(adapter: adapter)
    /// }
    /// .imprintDockEnvironment()
    /// ```
    func imprintDockEnvironment() -> some View {
        self
            .environment(\.dockHapticsProvider, ImprintHapticsProvider())
        // Design tokens use defaults which already match Imprint colors
        // Add .environment(\.dockDesignTokens, ImprintDesignTokens()) if needed
    }
}
