//
//  DockSessionSegments.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/20/26.
//

import Foundation

// MARK: - DockSessionSegments

/// Complete state for session progress segments (Instagram Stories style).
///
/// This struct provides all the data needed to render progress segments
/// during an active session. The dock owns the animation timer and notifies
/// the host when a segment's animation completes.
///
/// ## Segment Behavior Modes
///
/// The `usesTimedProgress` flag determines how segments fill:
///
/// | Mode | `usesTimedProgress` | Behavior |
/// |------|---------------------|----------|
/// | Read Aloud | `true` | Animates 0% -> 100% over duration, timer triggers auto-advance |
/// | Read & Speak | `false` | Toggles instantly, score completion triggers auto-advance |
/// | Speak Only | `false` | Toggles instantly, score completion triggers auto-advance |
///
/// ## Visual Representation (Timer Mode)
///
/// ```
/// Segment 0    Segment 1    Segment 2    Segment 3    Segment 4
/// [========]   [========]   [=====...]   [........]   [........]
///  complete     complete     animating    upcoming     upcoming
/// ```
///
/// ## Visual Representation (Toggle Mode)
///
/// ```
/// Segment 0    Segment 1    Segment 2    Segment 3    Segment 4
/// [========]   [========]   [========]   [........]   [........]
///  complete     complete     current      upcoming     upcoming
/// ```
///
/// ## Usage
///
/// ```swift
/// // In adapter
/// var sessionSegments: DockSessionSegments? {
///     guard store.isSessionActive else { return nil }
///
///     let configs = store.sessionAffirmations.map { ... }
///     let usesTimedProgress = store.sessionMode == .readAloud
///
///     return DockSessionSegments(
///         configs: configs,
///         currentIndex: store.sessionIndex,
///         isAnimating: isActive,
///         usesTimedProgress: usesTimedProgress
///     )
/// }
/// ```
public struct DockSessionSegments: Equatable, Sendable {
    
    /// Configuration for each segment (determines animation duration).
    ///
    /// The count of this array determines how many segments to render.
    /// Segments are evenly distributed across available width.
    public let configs: [DockSegmentConfig]
    
    /// The index of the currently active segment (0-based).
    ///
    /// - Segments before this index are shown as complete (100% filled)
    /// - This segment's behavior depends on `usesTimedProgress`
    /// - Segments after this index are shown as upcoming (0% filled)
    public let currentIndex: Int
    
    /// Whether the current segment is active.
    ///
    /// For timer mode (`usesTimedProgress=true`): starts the fill animation timer.
    /// For toggle mode (`usesTimedProgress=false`): shows segment as filled.
    ///
    /// Set to `false` during:
    /// - Idle states (waiting to start)
    /// - Score display
    /// - Paused states
    public let isAnimating: Bool
    
    /// Whether segments use timed progression or instant toggling.
    ///
    /// - `true`: Timer-driven (Read Aloud mode)
    ///   - Current segment animates 0% -> 100% over its configured duration
    ///   - Timer completion triggers `segmentAnimationCompleted()`
    ///
    /// - `false`: Event-driven (Read & Speak, Speak Only modes)
    ///   - Current segment shows as filled when active
    ///   - Auto-advance triggered by score completion, not timer
    public let usesTimedProgress: Bool
    
    /// Generation counter for reset signaling.
    ///
    /// When this value changes, the segment timer should reset to 0 and restart.
    /// The host increments this when:
    /// - Returning from background (segment restart)
    /// - Retrying a segment
    /// - Any interruption requiring a fresh start
    ///
    /// This provides explicit host control over timer resets without the dock
    /// needing to understand business logic.
    public let generation: Int
    
    // MARK: - Initialization
    
    /// Creates a new session segments state.
    ///
    /// - Parameters:
    ///   - configs: Configuration for each segment (count determines segment count)
    ///   - currentIndex: Index of the active segment (0-based)
    ///   - isAnimating: Whether the current segment is active
    ///   - usesTimedProgress: Whether to use timer-driven or event-driven progression
    ///   - generation: Reset generation counter (increment to force timer restart)
    public init(
        configs: [DockSegmentConfig],
        currentIndex: Int,
        isAnimating: Bool,
        usesTimedProgress: Bool = true,
        generation: Int = 0
    ) {
        self.configs = configs
        self.currentIndex = currentIndex
        self.isAnimating = isAnimating
        self.usesTimedProgress = usesTimedProgress
        self.generation = generation
    }
}

// MARK: - Convenience Properties

public extension DockSessionSegments {
    
    /// The total number of segments.
    var totalCount: Int {
        configs.count
    }
    
    /// Whether this is the first segment.
    var isFirstSegment: Bool {
        currentIndex == 0
    }
    
    /// Whether this is the last segment.
    var isLastSegment: Bool {
        currentIndex == totalCount - 1
    }
    
    /// Human-readable progress string (e.g., "3 of 10").
    var displayString: String {
        "\(currentIndex + 1) of \(totalCount)"
    }
    
    /// The configuration for the current segment.
    var currentConfig: DockSegmentConfig? {
        guard configs.indices.contains(currentIndex) else { return nil }
        return configs[currentIndex]
    }
    
    /// The animation duration for the current segment.
    var currentDuration: TimeInterval {
        currentConfig?.animationDuration ?? 8
    }
}

// MARK: - Factory Methods

public extension DockSessionSegments {
    
    /// Creates a session segments state at the beginning.
    ///
    /// - Parameters:
    ///   - configs: Configuration for each segment
    ///   - usesTimedProgress: Whether to use timer-driven progression
    ///   - generation: Reset generation counter
    /// - Returns: Segments at index 0, not animating
    static func start(
        configs: [DockSegmentConfig],
        usesTimedProgress: Bool = true,
        generation: Int = 0
    ) -> DockSessionSegments {
        DockSessionSegments(
            configs: configs,
            currentIndex: 0,
            isAnimating: false,
            usesTimedProgress: usesTimedProgress,
            generation: generation
        )
    }
    
    /// Creates a uniform session with same duration for all segments.
    ///
    /// - Parameters:
    ///   - count: Number of segments
    ///   - duration: Duration for each segment (default: 8 seconds)
    ///   - usesTimedProgress: Whether to use timer-driven progression
    ///   - generation: Reset generation counter
    /// - Returns: Segments with uniform configuration
    static func uniform(
        count: Int,
        duration: TimeInterval = 8,
        usesTimedProgress: Bool = true,
        generation: Int = 0
    ) -> DockSessionSegments {
        let configs = Array(repeating: DockSegmentConfig(animationDuration: duration), count: count)
        return DockSessionSegments(
            configs: configs,
            currentIndex: 0,
            isAnimating: false,
            usesTimedProgress: usesTimedProgress,
            generation: generation
        )
    }
}
