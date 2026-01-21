//
//  DockDesignTokens.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockDesignTokens

/// Design system abstraction for the Dock Module.
///
/// This protocol allows the host application to inject its design system values
/// (colors, spacing, typography, animations) into the dock components without
/// creating compile-time dependencies.
///
/// ## Usage
///
/// Create a conforming type in your host app:
///
/// ```swift
/// struct MyAppDockDesignTokens: DockDesignTokens {
///     var backgroundPrimary: Color { AppColors.backgroundPrimary }
///     var accent: Color { AppColors.accent }
///     // ... implement all requirements
/// }
/// ```
///
/// Inject via environment:
///
/// ```swift
/// AdaptiveDockContainer(adapter: adapter) {
///     AdaptiveBottomDock(adapter: adapter)
/// }
/// .environment(\.dockDesignTokens, MyAppDockDesignTokens())
/// ```
///
/// ## Default Values
///
/// If no custom tokens are injected, `DefaultDockDesignTokens` provides
/// sensible defaults matching the Imprint design system.
public protocol DockDesignTokens {
    
    // MARK: - Colors
    
    /// Primary background color (true black).
    /// Hex: #000000
    var backgroundPrimary: Color { get }
    
    /// Secondary background color (charcoal).
    /// Hex: #1C1C1E
    var backgroundSecondary: Color { get }
    
    /// Tertiary background color (dark gray).
    /// Hex: #2C2C2E
    var backgroundTertiary: Color { get }
    
    /// Tertiary surface color for UI elements.
    /// Hex: #48484A
    var surfaceTertiary: Color { get }
    
    /// Primary text color (off white).
    /// Hex: #F5F5F7
    var textPrimary: Color { get }
    
    /// Secondary text color (light gray).
    /// Hex: #A1A1A6
    var textSecondary: Color { get }
    
    /// Tertiary text color (medium gray).
    /// Hex: #6E6E73
    var textTertiary: Color { get }
    
    /// Primary accent color (warm amber/gold).
    /// Hex: #D4A574
    var accent: Color { get }
    
    /// Secondary accent color (soft sage).
    /// Hex: #8BA888
    var accentSecondary: Color { get }
    
    /// Success state color.
    /// Hex: #34C759
    var success: Color { get }
    
    /// Warning state color.
    /// Hex: #FF9500
    var warning: Color { get }
    
    // MARK: - Spacing
    
    /// Extra small spacing: 4pt
    var spacingXS: CGFloat { get }
    
    /// Small spacing: 8pt
    var spacingSM: CGFloat { get }
    
    /// Medium spacing: 16pt
    var spacingMD: CGFloat { get }
    
    /// Large spacing: 24pt
    var spacingLG: CGFloat { get }
    
    // MARK: - Corner Radius
    
    /// Medium corner radius: 12pt
    var cornerRadiusMedium: CGFloat { get }
    
    /// Large corner radius: 16pt
    var cornerRadiusLarge: CGFloat { get }
    
    /// Extra large corner radius: 24pt
    var cornerRadiusExtraLarge: CGFloat { get }
    
    // MARK: - Layout
    
    /// Bottom padding for the dock: 24pt
    var dockBottomPadding: CGFloat { get }
    
    /// Height for chip buttons: 36pt
    var chipHeight: CGFloat { get }
    
    /// Size for the play button: 48pt
    var playButtonSize: CGFloat { get }
    
    // MARK: - Animation
    
    /// Standard animation for dock transitions.
    var standardAnimation: Animation { get }
    
    // MARK: - Typography
    
    /// Caption 1 font: 12pt regular
    var caption1: Font { get }
    
    /// Caption 2 font: 11pt regular
    var caption2: Font { get }
    
    /// Headline font: 17pt semibold
    var headline: Font { get }
    
    /// Subheadline font: 15pt regular
    var subheadline: Font { get }
}

// MARK: - Environment Key

/// Environment key for injecting design tokens into the dock.
private struct DockDesignTokensKey: EnvironmentKey {
    static let defaultValue: any DockDesignTokens = DefaultDockDesignTokens()
}

public extension EnvironmentValues {
    
    /// The design tokens used by dock components.
    ///
    /// Set this to customize the dock's appearance:
    ///
    /// ```swift
    /// MyView()
    ///     .environment(\.dockDesignTokens, MyCustomTokens())
    /// ```
    var dockDesignTokens: any DockDesignTokens {
        get { self[DockDesignTokensKey.self] }
        set { self[DockDesignTokensKey.self] = newValue }
    }
}

// MARK: - DockHapticsProvider

/// Protocol for haptic feedback delegation.
///
/// The dock module calls these methods for tactile feedback, but the actual
/// implementation is provided by the host app. This maintains complete
/// decoupling from UIKit haptic APIs.
///
/// ## Usage
///
/// Create a conforming type in your host app:
///
/// ```swift
/// struct MyAppHapticsProvider: DockHapticsProvider {
///     func selectionFeedback() {
///         HapticFeedback.selection()
///     }
///     func lightImpact() {
///         HapticFeedback.light()
///     }
///     // ... implement all methods
/// }
/// ```
///
/// Inject via environment:
///
/// ```swift
/// MyDockView()
///     .environment(\.dockHapticsProvider, MyAppHapticsProvider())
/// ```
public protocol DockHapticsProvider {
    
    /// Light haptic for selection changes (toggles, picks).
    func selectionFeedback()
    
    /// Light impact for subtle taps.
    func lightImpact()
    
    /// Medium impact for standard button presses.
    func mediumImpact()
    
    /// Heavy impact for significant actions.
    func heavyImpact()
    
    /// Success notification feedback.
    func successNotification()
    
    /// Warning notification feedback.
    func warningNotification()
    
    /// Error notification feedback.
    func errorNotification()
}

// MARK: - Default Haptics Provider

/// A no-op haptics provider for previews and testing.
///
/// This provider does nothing when methods are called, which is appropriate
/// for SwiftUI previews and unit tests where haptic feedback is not needed.
public struct DefaultDockHapticsProvider: DockHapticsProvider {
    
    public init() {}
    
    public func selectionFeedback() {}
    public func lightImpact() {}
    public func mediumImpact() {}
    public func heavyImpact() {}
    public func successNotification() {}
    public func warningNotification() {}
    public func errorNotification() {}
}

// MARK: - Haptics Environment Key

/// Environment key for injecting haptics provider into the dock.
private struct DockHapticsProviderKey: EnvironmentKey {
    static let defaultValue: any DockHapticsProvider = DefaultDockHapticsProvider()
}

public extension EnvironmentValues {
    
    /// The haptics provider used by dock components.
    ///
    /// Set this to enable haptic feedback:
    ///
    /// ```swift
    /// MyView()
    ///     .environment(\.dockHapticsProvider, MyHapticsProvider())
    /// ```
    var dockHapticsProvider: any DockHapticsProvider {
        get { self[DockHapticsProviderKey.self] }
        set { self[DockHapticsProviderKey.self] = newValue }
    }
}
