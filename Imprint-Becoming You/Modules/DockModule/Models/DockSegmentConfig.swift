//
//  DockSegmentConfig.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/20/26.
//

import Foundation

// MARK: - DockSegmentConfig

/// Configuration for a single progress segment.
///
/// Each segment represents one affirmation in a session.
/// The dock uses this to determine animation timing.
///
/// ## Duration Calculation (Host Responsibility)
///
/// The host app calculates duration based on affirmation properties:
///
/// ```swift
/// let duration: TimeInterval = affirmation.speechDuration > 8
///     ? affirmation.speechDuration + 4
///     : 8
/// ```
///
/// - Default: 8 seconds
/// - Long affirmations (speechDuration > 8): speechDuration + 4 seconds
///
/// ## Usage
///
/// ```swift
/// let configs = sessionAffirmations.map { affirmation in
///     DockSegmentConfig(
///         animationDuration: calculateDuration(for: affirmation)
///     )
/// }
/// ```
public struct DockSegmentConfig: Equatable, Sendable {
    
    /// The duration for this segment's fill animation in seconds.
    ///
    /// When the segment becomes active and animation starts, it will
    /// fill from 0% to 100% over this duration.
    public let animationDuration: TimeInterval
    
    // MARK: - Initialization
    
    /// Creates a segment configuration.
    ///
    /// - Parameter animationDuration: Duration in seconds for the fill animation
    public init(animationDuration: TimeInterval) {
        self.animationDuration = animationDuration
    }
}

// MARK: - Factory Methods

public extension DockSegmentConfig {
    
    /// Default segment duration (8 seconds).
    static let `default` = DockSegmentConfig(animationDuration: 8)
    
    /// Creates a config with the standard duration calculation.
    ///
    /// - Parameter speechDuration: The affirmation's speech duration
    /// - Returns: A config with appropriate animation duration
    static func forSpeechDuration(_ speechDuration: TimeInterval) -> DockSegmentConfig {
        let duration: TimeInterval = speechDuration > 8
            ? speechDuration + 4
            : 8
        return DockSegmentConfig(animationDuration: duration)
    }
}
