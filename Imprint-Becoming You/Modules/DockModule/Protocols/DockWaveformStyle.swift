//
//  DockWaveformStyle.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/21/26.
//

import SwiftUI

// MARK: - DockWaveformStyle Protocol

/// Protocol for swappable waveform visualizations.
///
/// All waveform implementations must respond uniformly to `DockCenterContentState`
/// changes for consistent UX across different visual styles.
///
/// ## Conformance Requirements
///
/// Implementations must:
/// - React to all `DockCenterContentState` values
/// - Use design tokens for colors (accent, success)
/// - Support smooth animated transitions between states
/// - Handle audio levels for reactive visualizations
///
/// ## Usage
///
/// ```swift
/// struct MyCustomWaveformStyle: DockWaveformStyle {
///     func makeBody(state: DockCenterContentState, tokens: DockDesignTokens) -> some View {
///         // Your custom waveform implementation
///     }
/// }
/// ```
public protocol DockWaveformStyle: Sendable {
    associatedtype Body: View
    
    /// Creates the waveform view for the given state.
    ///
    /// - Parameters:
    ///   - state: The current visualization state
    ///   - tokens: Design tokens for styling
    /// - Returns: A view representing the waveform
    @MainActor @ViewBuilder
    func makeBody(state: DockCenterContentState, tokens: DockDesignTokens) -> Body
}

// MARK: - AnyDockWaveformStyle

/// Type-erased wrapper for `DockWaveformStyle` conforming types.
///
/// Enables storing and passing different waveform styles uniformly.
public struct AnyDockWaveformStyle: Sendable {
    
    private let _makeBody: @MainActor @Sendable (DockCenterContentState, DockDesignTokens) -> AnyView
    
    /// Creates a type-erased waveform style.
    ///
    /// - Parameter style: The concrete waveform style to wrap
    @MainActor
    public init<S: DockWaveformStyle>(_ style: S) {
        self._makeBody = { state, tokens in
            AnyView(style.makeBody(state: state, tokens: tokens))
        }
    }
    
    /// Creates the waveform view for the given state.
    @MainActor
    public func makeBody(state: DockCenterContentState, tokens: DockDesignTokens) -> some View {
        _makeBody(state, tokens)
    }
}

// MARK: - Environment Key

/// Environment key for injecting waveform styles.
///
/// Uses `DockWaveformType` enum for the default, resolving at render time.
public struct DockWaveformStyleKey: EnvironmentKey {
    // Use nonisolated(unsafe) for static initialization
    // The actual style creation happens on MainActor at render time
    nonisolated(unsafe) public static var defaultValue: AnyDockWaveformStyle? = nil
}

extension EnvironmentValues {
    /// The waveform style to use for visualizations.
    ///
    /// If nil, the default style based on `dockWaveformType` is used.
    public var dockWaveformStyle: AnyDockWaveformStyle? {
        get { self[DockWaveformStyleKey.self] }
        set { self[DockWaveformStyleKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Sets the waveform style for dock visualizations.
    ///
    /// - Parameter style: The waveform style to use
    /// - Returns: A view with the waveform style applied
    @MainActor
    public func dockWaveformStyle<S: DockWaveformStyle>(_ style: S) -> some View {
        environment(\.dockWaveformStyle, AnyDockWaveformStyle(style))
    }
}
