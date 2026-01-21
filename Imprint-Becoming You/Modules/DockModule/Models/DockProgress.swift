//
//  DockProgress.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import Foundation

// MARK: - DockProgress

/// Progress information for session segments.
///
/// This struct provides all the data needed to render the progress bars
/// (Stories-style segments) in the session dock configuration.
///
/// ## Visual Representation
///
/// ```
/// Segment 1    Segment 2    Segment 3    Segment 4    Segment 5
/// [████████]   [████████]   [█████░░░]   [░░░░░░░░]   [░░░░░░░░]
///  complete     complete     current      upcoming     upcoming
///                           (animating)
/// ```
///
/// ## Properties
///
/// - `currentIndex`: Which segment is active (0-based)
/// - `totalCount`: Total number of segments
/// - `segmentProgress`: Fill amount of current segment (0.0–1.0)
/// - `isAnimating`: Whether to animate the fill
///
/// ## Animation Behavior
///
/// `isAnimating` controls whether the progress bar shows a smooth fill:
///
/// | isAnimating | Visual |
/// |-------------|--------|
/// | `true`      | Smooth fill animation tracking TTS/speech progress |
/// | `false`     | Static state (empty or complete) |
///
/// ### When `isAnimating = true`
///
/// - Read Aloud: During TTS playback
/// - Read & Speak: During TTS playback or user listening
/// - Speak Only: During user listening
///
/// ### When `isAnimating = false`
///
/// - Read Only: Always (user controls pace via swipe)
/// - Any mode: Idle, waiting for user, showing score, settling
///
/// ## Usage
///
/// ```swift
/// // In host adapter
/// var progress: DockProgress? {
///     guard isSessionActive else { return nil }
///
///     let isAnimating: Bool = {
///         switch flow {
///         case .readAloud(.playing): return true
///         case .readAndSpeak(.ttsPlaying): return true
///         case .readAndSpeak(.listening): return true
///         case .speakOnly(.listening): return true
///         default: return false
///         }
///     }()
///
///     return DockProgress(
///         currentIndex: displayCurrentIndex,
///         totalCount: sessionAffirmations.count,
///         segmentProgress: currentSegmentProgress,
///         isAnimating: isAnimating
///     )
/// }
/// ```
public struct DockProgress: Equatable, Sendable {
    
    /// The index of the currently active segment (0-based).
    ///
    /// Segments before this index are shown as complete (fully filled).
    /// Segments after this index are shown as upcoming (empty).
    public let currentIndex: Int
    
    /// The total number of segments.
    ///
    /// Determines how many progress bars to render.
    public let totalCount: Int
    
    /// The fill progress of the current segment (0.0–1.0).
    ///
    /// - 0.0: Empty (just started)
    /// - 0.5: Half filled
    /// - 1.0: Complete
    ///
    /// This is separate from the waveform audio level — it represents
    /// progress through the current affirmation, not audio visualization.
    public let segmentProgress: Float
    
    /// Whether the segment fill should animate.
    ///
    /// When `true`, the progress bar shows a smooth fill animation.
    /// When `false`, the progress bar shows a static state.
    ///
    /// Animation is enabled during timed phases (TTS playing, listening)
    /// and disabled during user-controlled or static phases (idle, score display).
    public let isAnimating: Bool
    
    // MARK: - Initialization
    
    /// Creates a new progress state.
    ///
    /// - Parameters:
    ///   - currentIndex: Index of the active segment (0-based)
    ///   - totalCount: Total number of segments
    ///   - segmentProgress: Fill amount of current segment (0.0–1.0)
    ///   - isAnimating: Whether to animate the fill
    public init(
        currentIndex: Int,
        totalCount: Int,
        segmentProgress: Float,
        isAnimating: Bool
    ) {
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.segmentProgress = segmentProgress
        self.isAnimating = isAnimating
    }
}

// MARK: - Convenience Properties

public extension DockProgress {
    
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
    
    /// Progress as a fraction of total (0.0–1.0).
    ///
    /// Includes partial progress of the current segment.
    var overallProgress: Float {
        guard totalCount > 0 else { return 0 }
        let completedSegments = Float(currentIndex)
        let currentContribution = segmentProgress
        return (completedSegments + currentContribution) / Float(totalCount)
    }
    
    /// The number of completed segments.
    var completedCount: Int {
        currentIndex
    }
    
    /// The number of remaining segments (including current).
    var remainingCount: Int {
        totalCount - currentIndex
    }
}

// MARK: - Factory Methods

public extension DockProgress {
    
    /// Creates a progress state at the beginning.
    ///
    /// - Parameter totalCount: Total number of segments
    /// - Returns: Progress at index 0 with no fill
    static func start(totalCount: Int) -> DockProgress {
        DockProgress(
            currentIndex: 0,
            totalCount: totalCount,
            segmentProgress: 0,
            isAnimating: false
        )
    }
    
    /// Creates a progress state at completion.
    ///
    /// - Parameter totalCount: Total number of segments
    /// - Returns: Progress at last index with full fill
    static func complete(totalCount: Int) -> DockProgress {
        DockProgress(
            currentIndex: max(0, totalCount - 1),
            totalCount: totalCount,
            segmentProgress: 1.0,
            isAnimating: false
        )
    }
}
