//
//  DockProgressBars.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockProgressBars

/// Stories-style progress segments showing session progress.
///
/// Displays a row of horizontal bars representing each affirmation.
/// Completed segments are filled, current shows partial progress,
/// and upcoming segments are empty.
///
/// ## Usage
///
/// ```swift
/// DockProgressBars(progress: adapter.progress)
/// ```
public struct DockProgressBars: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    public let progress: DockProgress
    
    private let barHeight: CGFloat = 3
    private let barSpacing: CGFloat = 4
    
    // MARK: - Initialization
    
    public init(progress: DockProgress) {
        self.progress = progress
    }
    
    // MARK: - Body
    
    public var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<progress.totalCount, id: \.self) { index in
                ProgressSegment(
                    fillPercent: fillPercent(for: index),
                    isAnimating: index == progress.currentIndex && progress.isAnimating,
                    accentColor: tokens.accent,
                    tertiaryColor: tokens.textTertiary
                )
            }
        }
        .frame(height: barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress: \(progress.currentIndex + 1) of \(progress.totalCount)")
    }
    
    // MARK: - Fill Calculation
    
    private func fillPercent(for index: Int) -> CGFloat {
        if index < progress.currentIndex {
            return 1.0 // Completed
        } else if index == progress.currentIndex {
            return CGFloat(progress.segmentProgress) // Current
        } else {
            return 0 // Upcoming
        }
    }
}

// MARK: - ProgressSegment

private struct ProgressSegment: View {
    let fillPercent: CGFloat
    let isAnimating: Bool
    let accentColor: Color
    let tertiaryColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(tertiaryColor.opacity(0.3))
                
                // Fill
                Capsule()
                    .fill(accentColor)
                    .frame(width: geometry.size.width * fillPercent)
            }
        }
        .animation(isAnimating ? .linear(duration: 0.1) : .easeOut(duration: 0.2), value: fillPercent)
    }
}

// MARK: - Previews

#Preview("Progress Bars - Middle") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockProgressBars(
            progress: DockProgress(
                currentIndex: 2,
                totalCount: 5,
                segmentProgress: 0.45,
                isAnimating: true
            )
        )
        .padding()
    }
}

#Preview("Progress Bars - Start") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockProgressBars(
            progress: DockProgress(
                currentIndex: 0,
                totalCount: 8,
                segmentProgress: 0,
                isAnimating: false
            )
        )
        .padding()
    }
}
