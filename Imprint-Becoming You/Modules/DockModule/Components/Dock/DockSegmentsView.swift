//
//  DockSegmentsView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/20/26.
//

import SwiftUI

// MARK: - DockSegmentsView

/// Instagram Stories-style progress segments with precise fill behavior.
///
/// ## Segment Fill Rules (Deterministic)
///
/// Fill percentage is a **pure function** of these inputs only:
/// - `segmentIndex`: Which segment
/// - `currentIndex`: Which segment is active
/// - `usesTimedProgress`: Mode behavior
/// - `timerProgress`: Only used in timed mode for current segment
///
/// ### Timed Mode (Read Aloud)
/// ```
/// segmentIndex < currentIndex  -> 1.0 (complete)
/// segmentIndex == currentIndex -> timerProgress (0.0 -> 1.0 animated)
/// segmentIndex > currentIndex  -> 0.0 (upcoming)
/// ```
///
/// ### Event Mode (Read & Speak, Speak Only)
/// ```
/// segmentIndex < currentIndex  -> 1.0 (complete)
/// segmentIndex == currentIndex -> 1.0 (active = filled)
/// segmentIndex > currentIndex  -> 0.0 (upcoming)
/// ```
///
/// ## Bug Prevention
///
/// - No stale state: `timerProgress` resets to 0 synchronously when segment changes
/// - No animation leakage: Timer only exists in timed mode
/// - No intermediate states: Fill is computed, not animated between states
/// - Deterministic: Same inputs always produce same fill values
///
/// ## Animation Optimization (Issue 2.3)
///
/// Uses `structuralAnimationKey` to animate only on meaningful structural changes:
/// - Segment count changes (adding/removing segments)
/// - Current index changes (progress through session)
/// Progress animation is isolated to individual SegmentBar components.
public struct DockSegmentsView: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    /// The segment state from the adapter.
    public let segments: DockSessionSegments
    
    /// Called when the timer-driven segment completes (timed mode only).
    public let onSegmentCompleted: () -> Void
    
    // MARK: - Constants
    
    private let barHeight: CGFloat = 3
    
    // MARK: - Animation Optimization
    
    /// Key that changes only when segment structure or position changes.
    ///
    /// This prevents unnecessary animations when other properties change
    /// (like isAnimating, generation) that don't affect layout.
    private var structuralAnimationKey: String {
        "\(segments.totalCount)-\(segments.currentIndex)"
    }
    
    // MARK: - Timer State (Timed Mode Only)
    
    /// Progress of the current segment's timer (0.0 - 1.0).
    /// Only used when `usesTimedProgress = true`.
    @State private var timerProgress: CGFloat = 0
    
    /// The timer driving the animation.
    @State private var animationTimer: Timer?
    
    /// The segment index the timer is running for.
    /// Used to detect segment changes and invalidate stale timers.
    @State private var timerSegmentIndex: Int = -1
    
    /// Generation counter to invalidate stale timer callbacks.
    /// Incremented on every segment change or animation stop.
    @State private var timerGeneration: Int = 0
    
    // MARK: - Initialization
    
    public init(
        segments: DockSessionSegments,
        onSegmentCompleted: @escaping () -> Void
    ) {
        self.segments = segments
        self.onSegmentCompleted = onSegmentCompleted
    }
    
    // MARK: - Body
    
    public var body: some View {
        HStack(spacing: dynamicSpacing) {
            ForEach(0..<segments.totalCount, id: \.self) { index in
                SegmentBar(
                    fillPercent: computeFill(for: index),
                    accentColor: tokens.accent,
                    backgroundColor: tokens.textTertiary.opacity(0.3)
                )
            }
        }
        .frame(height: barHeight)
        // Structural animation (adding/removing segments, index changes)
        .animation(tokens.standardAnimation, value: structuralAnimationKey)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress: \(segments.currentIndex + 1) of \(segments.totalCount)")
        .onChange(of: segments.currentIndex) { oldIndex, newIndex in
            handleSegmentChanged(from: oldIndex, to: newIndex)
        }
        .onChange(of: segments.isAnimating) { wasAnimating, isAnimating in
            handleAnimatingChanged(from: wasAnimating, to: isAnimating)
        }
        .onChange(of: segments.generation) { _, _ in
            handleGenerationChanged()
        }
        .onAppear {
            initializeTimerState()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    // MARK: - Dynamic Spacing
    
    private var dynamicSpacing: CGFloat {
        switch segments.totalCount {
        case 1...5: return 4
        case 6...10: return 3
        case 11...15: return 2
        default: return 1
        }
    }
    
    // MARK: - Fill Computation (Pure Function)
    
    /// Computes the fill percentage for a segment.
    ///
    /// This is a **pure function** - no side effects, deterministic output.
    ///
    /// ## Timed Mode (Read Aloud)
    /// ```
    /// index < currentIndex  -> 1.0 (complete)
    /// index == currentIndex -> timerProgress (animated 0.0 -> 1.0, validated)
    /// index > currentIndex  -> 0.0 (upcoming)
    /// ```
    ///
    /// ## Event Mode (Read & Speak, Speak Only)
    /// ```
    /// index < currentIndex  -> 1.0 (complete)
    /// index == currentIndex -> 1.0 (ALWAYS filled once current)
    /// index > currentIndex  -> 0.0 (upcoming)
    /// ```
    ///
    /// ## Race Condition Prevention
    ///
    /// In timed mode, `timerProgress` is only used if `timerSegmentIndex == currentIndex`.
    /// This prevents stale progress from a previous segment showing on a new segment
    /// during rapid navigation (when SwiftUI re-renders before onChange fires).
    ///
    /// Additionally, `showCurrentAsComplete` is checked first during forward navigation
    /// to ensure the current segment shows 100% before the index change propagates.
    private func computeFill(for index: Int) -> CGFloat {
        // Past segments: always complete
        if index < segments.currentIndex {
            return 1.0
        }
        
        // Future segments: always empty
        if index > segments.currentIndex {
            return 0.0
        }
        
        // Current segment (index == currentIndex):
        if segments.usesTimedProgress {
            // Timed mode: animated fill controlled by timer
            
            // Check for forced completion during forward navigation.
            // This ensures smooth visual transition when user skips forward.
            if segments.showCurrentAsComplete {
                return 1.0
            }
            
            // CRITICAL: Only use timerProgress if it belongs to THIS segment
            // This prevents stale progress from previous segments during rapid skip
            if segments.isAnimating && timerSegmentIndex == segments.currentIndex {
                return timerProgress
            } else {
                // Either not animating, or timerProgress is stale (belongs to different segment)
                return 0.0
            }
        } else {
            // Event mode: current segment is ALWAYS filled (1.0)
            // No dependency on isAnimating - prevents blank during score display
            return 1.0
        }
    }
    
    // MARK: - State Change Handlers
    
    /// Called when the segment index changes.
    private func handleSegmentChanged(from oldIndex: Int, to newIndex: Int) {
        // CRITICAL: Stop timer and reset ALL timer state SYNCHRONOUSLY
        // This prevents any stale state from being rendered
        stopTimer()
        timerProgress = 0
        timerSegmentIndex = newIndex  // Mark timer as belonging to NEW segment
        timerGeneration += 1
        
        // If we should be animating in timed mode, start fresh timer
        if segments.isAnimating && segments.usesTimedProgress {
            startTimer(for: newIndex)
        }
    }
    
    /// Called when the animating state changes.
    private func handleAnimatingChanged(from wasAnimating: Bool, to isAnimating: Bool) {
        if isAnimating && !wasAnimating {
            // Started animating
            if segments.usesTimedProgress {
                // Reset and start timer for current segment
                timerProgress = 0
                timerSegmentIndex = segments.currentIndex  // Ensure correct segment
                timerGeneration += 1
                startTimer(for: segments.currentIndex)
            }
            // Event mode: no timer needed, fill is computed directly
        } else if !isAnimating && wasAnimating {
            // Stopped animating
            stopTimer()
            // Note: We do NOT reset timerProgress here
            // If stopping due to completion, we want to show 100%
            // The next segment change will reset it
        }
    }
    
    /// Called when the generation counter changes (host-triggered reset).
    ///
    /// This is the host's explicit signal to restart the current segment's timer.
    /// Used when returning from background, retrying, or any interruption.
    private func handleGenerationChanged() {
        #if DEBUG
        AppLogger.debug("Generation changed, resetting timer", category: .ui)
        #endif
        
        // Stop existing timer and reset all state
        stopTimer()
        timerProgress = 0
        timerSegmentIndex = segments.currentIndex
        timerGeneration += 1
        
        // Restart timer if we should be animating in timed mode
        if segments.isAnimating && segments.usesTimedProgress {
            startTimer(for: segments.currentIndex)
        }
    }
    
    /// Initialize timer state on appear.
    private func initializeTimerState() {
        // Reset to clean state matching current segment
        timerProgress = 0
        timerSegmentIndex = segments.currentIndex  // Start with correct segment
        timerGeneration += 1
        
        // Start timer if needed
        if segments.isAnimating && segments.usesTimedProgress {
            startTimer(for: segments.currentIndex)
        }
    }
    
    // MARK: - Timer Management
    
    /// Starts the timer for a specific segment.
    private func startTimer(for segmentIndex: Int) {
        // Ensure clean state
        stopTimer()
        timerProgress = 0
        timerSegmentIndex = segmentIndex
        
        let generation = timerGeneration
        let duration = segments.currentDuration
        let updateInterval: TimeInterval = 1.0 / 60.0  // 60 FPS
        let incrementPerTick = 1.0 / (duration / updateInterval)
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [self] timer in
            // Run on main actor
            Task { @MainActor in
                // Validate timer is still relevant
                guard generation == timerGeneration else {
                    timer.invalidate()
                    return
                }
                
                guard segmentIndex == segments.currentIndex else {
                    timer.invalidate()
                    return
                }
                
                guard segments.isAnimating else {
                    timer.invalidate()
                    return
                }
                
                // Increment progress
                timerProgress += incrementPerTick
                
                // Check for completion
                if timerProgress >= 1.0 {
                    timerProgress = 1.0
                    timer.invalidate()
                    animationTimer = nil
                    
                    // Fire completion callback
                    onSegmentCompleted()
                }
            }
        }
    }
    
    /// Stops the timer immediately.
    private func stopTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - SegmentBar

/// A single segment bar with fill.
///
/// This is a pure presentation component - it just renders
/// the fill percentage it's given.
///
/// ## Animation Optimization (Issue 2.3)
/// Uses isolated progress animation on fill changes only.
/// This prevents re-renders from other state changes affecting animation.
private struct SegmentBar: View {
    let fillPercent: CGFloat
    let accentColor: Color
    let backgroundColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(backgroundColor)

                // Fill bar — always present, width controls visibility.
                // Removing the `if fillPercent > 0` conditional eliminates view
                // insertion/removal that the structural animation could flash.
                Capsule()
                    .fill(accentColor)
                    .frame(width: max(0, geometry.size.width * fillPercent))
            }
            // CRITICAL: Clip all content to the Capsule boundary.
            // The parent HStack uses a spring animation with bounce (0.2) for structural
            // transitions. During the bounce phase, GeometryReader can report a width
            // that overshoots the segment's resting size. Without clipping, the fill
            // Capsule (at 100%) extends beyond the track into the adjacent segment.
            // clipShape physically contains the fill regardless of geometry overshoot.
            .clipShape(Capsule())
        }
        // Isolate fill animation from parent structural animation.
        // .animation(nil) blocks inherited animations (the parent spring with bounce),
        // then the explicit .animation applies only to fillPercent changes at frame rate.
        .animation(nil, value: fillPercent)
        .animation(.linear(duration: 1.0 / 60.0), value: fillPercent)
    }
}

// MARK: - Previews

#Preview("Timed Mode - Animating") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockSegmentsView(
            segments: DockSessionSegments(
                configs: Array(repeating: .default, count: 10),
                currentIndex: 4,
                isAnimating: true,
                usesTimedProgress: true
            ),
            onSegmentCompleted: {}
        )
        .padding()
    }
}

#Preview("Event Mode - Active") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockSegmentsView(
            segments: DockSessionSegments(
                configs: Array(repeating: .default, count: 10),
                currentIndex: 4,
                isAnimating: true,
                usesTimedProgress: false  // Event mode: instant fill
            ),
            onSegmentCompleted: {}
        )
        .padding()
    }
}

#Preview("Event Mode - Score Display (Not Animating)") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockSegmentsView(
            segments: DockSessionSegments(
                configs: Array(repeating: .default, count: 10),
                currentIndex: 4,
                isAnimating: false,  // Paused for score
                usesTimedProgress: false
            ),
            onSegmentCompleted: {}
        )
        .padding()
    }
}

#Preview("Timed Mode - 5 Items") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockSegmentsView(
            segments: DockSessionSegments(
                configs: Array(repeating: .default, count: 5),
                currentIndex: 2,
                isAnimating: true,
                usesTimedProgress: true
            ),
            onSegmentCompleted: {}
        )
        .padding()
    }
}
