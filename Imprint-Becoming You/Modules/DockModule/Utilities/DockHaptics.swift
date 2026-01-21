//
//  DockHaptics.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockHaptics

/// Convenience utilities for haptic feedback in dock components.
///
/// This enum provides static methods that wrap the `DockHapticsProvider` protocol,
/// making it easy to trigger haptics from anywhere in the dock module.
///
/// ## Architecture
///
/// The dock module defines the `DockHapticsProvider` protocol (in `DockDesignTokens.swift`),
/// and the host app injects a concrete implementation via environment. This maintains
/// complete decoupling from UIKit haptic APIs.
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │              HOST APP                   │
/// │  ┌───────────────────────────────────┐  │
/// │  │ ImprintHapticsProvider            │  │
/// │  │   - Wraps HapticFeedback enum     │  │
/// │  │   - Pre-warmed UIKit generators   │  │
/// │  └───────────────┬───────────────────┘  │
/// └──────────────────┼──────────────────────┘
///                    │ Environment Injection
///                    ▼
/// ┌─────────────────────────────────────────┐
/// │            DOCK MODULE                  │
/// │  ┌───────────────────────────────────┐  │
/// │  │ DockHaptics                       │  │
/// │  │   - Reads from environment        │  │
/// │  │   - Calls provider methods        │  │
/// │  └───────────────────────────────────┘  │
/// └─────────────────────────────────────────┘
/// ```
///
/// ## Usage in Views
///
/// ```swift
/// struct MyDockButton: View {
///     @Environment(\.dockHapticsProvider) private var haptics
///
///     var body: some View {
///         Button("Tap") {
///             haptics.selectionFeedback()
///             // ... action
///         }
///     }
/// }
/// ```
///
/// ## Host App Setup
///
/// Create a provider that wraps your existing haptics:
///
/// ```swift
/// struct ImprintHapticsProvider: DockHapticsProvider {
///     func selectionFeedback() {
///         HapticFeedback.selection()
///     }
///     func lightImpact() {
///         HapticFeedback.light()
///     }
///     // ... etc
/// }
///
/// // Inject into dock
/// AdaptiveDockContainer(adapter: adapter) {
///     AdaptiveBottomDock(adapter: adapter)
/// }
/// .environment(\.dockHapticsProvider, ImprintHapticsProvider())
/// ```
public enum DockHaptics {
    
    // MARK: - Selection Feedback
    
    /// Triggers selection feedback via the injected provider.
    ///
    /// Use for selection changes like toggles and picks.
    /// This is a convenience for views that have access to the environment.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func selection(using provider: any DockHapticsProvider) {
        provider.selectionFeedback()
    }
    
    // MARK: - Impact Feedback
    
    /// Triggers light impact feedback via the injected provider.
    ///
    /// Use for subtle taps and minor interactions.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func lightImpact(using provider: any DockHapticsProvider) {
        provider.lightImpact()
    }
    
    /// Triggers medium impact feedback via the injected provider.
    ///
    /// Use for standard button presses.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func mediumImpact(using provider: any DockHapticsProvider) {
        provider.mediumImpact()
    }
    
    /// Triggers heavy impact feedback via the injected provider.
    ///
    /// Use for significant actions.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func heavyImpact(using provider: any DockHapticsProvider) {
        provider.heavyImpact()
    }
    
    // MARK: - Notification Feedback
    
    /// Triggers success notification feedback via the injected provider.
    ///
    /// Use when a task completes successfully.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func success(using provider: any DockHapticsProvider) {
        provider.successNotification()
    }
    
    /// Triggers warning notification feedback via the injected provider.
    ///
    /// Use when caution is needed.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func warning(using provider: any DockHapticsProvider) {
        provider.warningNotification()
    }
    
    /// Triggers error notification feedback via the injected provider.
    ///
    /// Use when something goes wrong.
    ///
    /// - Parameter provider: The haptics provider from environment
    public static func error(using provider: any DockHapticsProvider) {
        provider.errorNotification()
    }
}

// MARK: - View Extension

public extension View {
    
    /// Adds haptic feedback when a value changes.
    ///
    /// This modifier triggers haptic feedback whenever the observed value changes.
    /// Useful for providing tactile feedback on state transitions.
    ///
    /// ```swift
    /// Toggle("Option", isOn: $isEnabled)
    ///     .hapticFeedback(on: isEnabled, type: .selection)
    /// ```
    ///
    /// - Parameters:
    ///   - value: The value to observe for changes
    ///   - type: The type of haptic feedback to trigger
    /// - Returns: A view with haptic feedback on value change
    func hapticFeedback<V: Equatable>(
        on value: V,
        type: HapticType
    ) -> some View {
        modifier(HapticFeedbackModifier(value: value, type: type))
    }
}

// MARK: - Haptic Type

/// Types of haptic feedback available.
public enum HapticType {
    /// Light tap for selection changes
    case selection
    /// Light impact
    case lightImpact
    /// Medium impact
    case mediumImpact
    /// Heavy impact
    case heavyImpact
    /// Success notification
    case success
    /// Warning notification
    case warning
    /// Error notification
    case error
}

// MARK: - Haptic Feedback Modifier

/// View modifier that triggers haptic feedback on value changes.
private struct HapticFeedbackModifier<V: Equatable>: ViewModifier {
    @Environment(\.dockHapticsProvider) private var haptics
    
    let value: V
    let type: HapticType
    
    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, _ in
                triggerHaptic()
            }
    }
    
    private func triggerHaptic() {
        switch type {
        case .selection:
            haptics.selectionFeedback()
        case .lightImpact:
            haptics.lightImpact()
        case .mediumImpact:
            haptics.mediumImpact()
        case .heavyImpact:
            haptics.heavyImpact()
        case .success:
            haptics.successNotification()
        case .warning:
            haptics.warningNotification()
        case .error:
            haptics.errorNotification()
        }
    }
}
