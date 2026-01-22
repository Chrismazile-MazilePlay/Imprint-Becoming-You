//
//  DockWaveformType.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/21/26.
//

import SwiftUI

// MARK: - DockWaveformType

/// Available waveform visualization styles.
///
/// Users can select their preferred waveform style from Settings.
/// The selection persists across sessions via `UserProfile`.
///
/// ## Available Styles
///
/// | Style | Description |
/// |-------|-------------|
/// | `.layeredWaves` | Overlapping sine curves with depth (default) |
/// | `.classicBars` | Traditional equalizer-style bars |
///
/// ## Usage
///
/// ```swift
/// // In settings
/// Picker("Waveform", selection: $selectedType) {
///     ForEach(DockWaveformType.allCases) { type in
///         Text(type.displayName).tag(type)
///     }
/// }
/// ```
public enum DockWaveformType: String, CaseIterable, Identifiable, Codable, Sendable {
    
    /// Layered waves - overlapping sine curves with depth and organic movement.
    /// This is the default style.
    case layeredWaves
    
    /// Classic bars - traditional equalizer-style animated bars.
    case classicBars
    
    // MARK: - Identifiable
    
    public var id: String { rawValue }
    
    // MARK: - Display Properties
    
    /// Human-readable name for UI display.
    public var displayName: String {
        switch self {
        case .layeredWaves:
            return "Layered Waves"
        case .classicBars:
            return "Classic Bars"
        }
    }
    
    /// Description of the waveform style.
    public var description: String {
        switch self {
        case .layeredWaves:
            return "Flowing sine waves with depth and smooth motion"
        case .classicBars:
            return "Traditional equalizer bars with rhythmic animation"
        }
    }
    
    /// SF Symbol icon name for the waveform type.
    public var iconName: String {
        switch self {
        case .layeredWaves:
            return "waveform.path"
        case .classicBars:
            return "waveform"
        }
    }
    
    // MARK: - Default
    
    /// The default waveform type.
    public static let `default`: DockWaveformType = .layeredWaves
}

// MARK: - Environment Key

/// Environment key for waveform type injection.
public struct DockWaveformTypeKey: EnvironmentKey {
    public static let defaultValue: DockWaveformType = .layeredWaves
}

extension EnvironmentValues {
    /// The waveform type to use for visualizations.
    public var dockWaveformType: DockWaveformType {
        get { self[DockWaveformTypeKey.self] }
        set { self[DockWaveformTypeKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Sets the waveform type for dock visualizations.
    ///
    /// - Parameter type: The waveform type to use
    /// - Returns: A view with the waveform type applied
    public func dockWaveformType(_ type: DockWaveformType) -> some View {
        environment(\.dockWaveformType, type)
    }
}
