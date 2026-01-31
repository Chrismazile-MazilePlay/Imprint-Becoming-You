//
//  DockScoreDisplay.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockScoreDisplay

/// An animated percentage score display for showing resonance results.
///
/// Displays a score with a counting animation from 0 to the target value,
/// providing satisfying visual feedback when scores are revealed.
///
/// ## Animation
///
/// The score animates from 0 to the final value over 0.6 seconds using
/// an ease-out curve for a natural, decelerating count-up effect.
///
/// ## Accessibility
///
/// - **Label:** "Resonance score: X percent"
/// - **Value:** Descriptive feedback (Excellent, Good, Fair, Keep practicing)
///
/// ## Usage
///
/// ```swift
/// DockScoreDisplay(score: 85)
/// ```
public struct DockScoreDisplay: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    /// The target score percentage (0-100).
    public let score: Int
    
    // MARK: - Animation State
    
    @State private var displayedScore: Int = 0
    @State private var hasAnimated: Bool = false
    
    // MARK: - Accessibility
    
    /// Descriptive feedback based on score range.
    private var scoreDescription: String {
        switch score {
        case 90...100:
            return "Excellent resonance"
        case 70..<90:
            return "Good resonance"
        case 50..<70:
            return "Fair resonance"
        default:
            return "Keep practicing"
        }
    }
    
    // MARK: - Initialization
    
    /// Creates a new score display.
    ///
    /// - Parameter score: The score percentage to display (0-100)
    public init(score: Int) {
        self.score = max(0, min(100, score))
    }
    
    // MARK: - Body
    
    public var body: some View {
        Text("\(displayedScore)%")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tokens.accent)
            .contentTransition(.numericText())
            .onAppear {
                guard !hasAnimated else { return }
                hasAnimated = true
                animateScore()
            }
            .onChange(of: score) { _, newValue in
                animateScore(to: newValue)
            }
            // MARK: Accessibility
            .accessibilityLabel("Resonance score: \(score) percent")
            .accessibilityValue(scoreDescription)
    }
    
    // MARK: - Animation
    
    /// Animates the displayed score from current to target.
    private func animateScore(to target: Int? = nil) {
        let targetScore = target ?? score
        let startScore = displayedScore
        let duration: Double = 0.6
        let steps = 30
        
        for step in 0...steps {
            let delay = Double(step) * (duration / Double(steps))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Ease-out curve: fast start, slow finish
                let progress = Double(step) / Double(steps)
                let easedProgress = 1 - pow(1 - progress, 3)
                let newValue = startScore + Int(Double(targetScore - startScore) * easedProgress)
                
                withAnimation(.linear(duration: 0.02)) {
                    displayedScore = newValue
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Score Display - 85%") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockScoreDisplay(score: 85)
    }
}

#Preview("Score Display - Various") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 24) {
            DockScoreDisplay(score: 42)
            DockScoreDisplay(score: 78)
            DockScoreDisplay(score: 95)
        }
    }
}
