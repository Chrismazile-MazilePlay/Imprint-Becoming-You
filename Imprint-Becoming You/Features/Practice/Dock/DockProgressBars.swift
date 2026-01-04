//
//  DockProgressBars.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI

// MARK: - DockProgressBars

/// Stories-style progress indicator with segmented bars.
///
/// Each segment represents one affirmation in the session.
/// - **Completed:** Fully filled (accent color)
/// - **Current:** Partially filled or pulsing
/// - **Upcoming:** Dimmed/empty
///
/// ## Usage
/// ```swift
/// DockProgressBars(
///     current: 2,
///     total: 5,
///     progress: 0.7  // 70% through current item
/// )
/// ```
struct DockProgressBars: View {
    
    // MARK: - Configuration
    
    /// Height of progress bars
    private let barHeight: CGFloat = 3
    
    /// Spacing between bars
    private let barSpacing: CGFloat = 4
    
    /// Corner radius for bars
    private let cornerRadius: CGFloat = 1.5
    
    // MARK: - Properties
    
    /// Current item index (0-based)
    let current: Int
    
    /// Total number of items
    let total: Int
    
    /// Progress through current item (0.0 - 1.0)
    var progress: CGFloat = 0.0
    
    /// Whether to animate the current segment
    var isAnimating: Bool = false
    
    // MARK: - State
    
    @State private var pulseOpacity: Double = 1.0
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<total, id: \.self) { index in
                ProgressSegment(
                    state: segmentState(for: index),
                    progress: index == current ? progress : (index < current ? 1.0 : 0.0),
                    cornerRadius: cornerRadius
                )
                .frame(height: barHeight)
                .opacity(segmentOpacity(for: index))
            }
        }
        .onChange(of: isAnimating) { _, animating in
            if animating {
                startPulseAnimation()
            } else {
                pulseOpacity = 1.0
            }
        }
        .onAppear {
            if isAnimating {
                startPulseAnimation()
            }
        }
    }
    
    // MARK: - Segment State Enum
    
    enum SegmentState {
        case completed
        case current
        case upcoming
    }
    
    // MARK: - Helpers
    
    private func segmentState(for index: Int) -> SegmentState {
        if index < current {
            return .completed
        } else if index == current {
            return .current
        } else {
            return .upcoming
        }
    }
    
    private func segmentOpacity(for index: Int) -> Double {
        if index == current && isAnimating {
            return pulseOpacity
        }
        return 1.0
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.5
        }
    }
}

// MARK: - ProgressSegment

/// Individual segment in the progress bar
struct ProgressSegment: View {
    
    let state: DockProgressBars.SegmentState
    let progress: CGFloat
    let cornerRadius: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(trackColor)
                
                // Fill
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * fillProgress)
            }
        }
    }
    
    private var trackColor: Color {
        AppColors.textTertiary.opacity(0.3)
    }
    
    private var fillColor: Color {
        switch state {
        case .completed:
            return AppColors.accent
        case .current:
            return AppColors.accent
        case .upcoming:
            return Color.clear
        }
    }
    
    private var fillProgress: CGFloat {
        switch state {
        case .completed:
            return 1.0
        case .current:
            return max(0, min(1, progress))
        case .upcoming:
            return 0.0
        }
    }
}

// MARK: - Previews

#Preview("Progress Bars - Start") {
    VStack(spacing: 20) {
        DockProgressBars(current: 0, total: 5, progress: 0.0)
        DockProgressBars(current: 0, total: 5, progress: 0.5)
    }
    .padding()
    .background(AppColors.backgroundSecondary)
}

#Preview("Progress Bars - Middle") {
    VStack(spacing: 20) {
        DockProgressBars(current: 2, total: 5, progress: 0.0)
        DockProgressBars(current: 2, total: 5, progress: 0.7)
    }
    .padding()
    .background(AppColors.backgroundSecondary)
}

#Preview("Progress Bars - End") {
    VStack(spacing: 20) {
        DockProgressBars(current: 4, total: 5, progress: 0.5)
        DockProgressBars(current: 4, total: 5, progress: 1.0)
    }
    .padding()
    .background(AppColors.backgroundSecondary)
}

#Preview("Progress Bars - Various Counts") {
    VStack(spacing: 20) {
        DockProgressBars(current: 1, total: 3, progress: 0.5)
        DockProgressBars(current: 3, total: 7, progress: 0.3)
        DockProgressBars(current: 5, total: 10, progress: 0.8)
    }
    .padding()
    .background(AppColors.backgroundSecondary)
}

#Preview("Progress Bars - Animating") {
    DockProgressBars(current: 2, total: 5, progress: 0.5, isAnimating: true)
        .padding()
        .background(AppColors.backgroundSecondary)
}
