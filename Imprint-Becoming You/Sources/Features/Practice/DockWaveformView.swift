//
//  DockWaveformView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/22/25.
//

import SwiftUI
import Combine

// MARK: - WaveformState

/// Represents the current state of the waveform animation.
enum WaveformState: Equatable {
    /// Small dots, no animation
    case idle
    
    /// Animating waveform for TTS playback (accent color)
    case playing
    
    /// Animating waveform for microphone input (green color)
    case listening
    
    /// Transitioning from waveform back to idle dots
    case settling
    
    /// Subtle pulse animation indicating "ready/waiting"
    case waiting
}

// MARK: - DockWaveformView

/// A 9-bar waveform animation that morphs between idle dots and animated bars.
///
/// ## States
/// - **Idle:** 9 small circular dots in a row
/// - **Playing:** Bars animate to audio levels (TTS), accent color
/// - **Listening:** Bars animate to mic levels, green color
/// - **Settling:** Bars smoothly shrink back to dots
/// - **Waiting:** Dots pulse gently indicating "your turn"
///
/// ## Fallback Animation
/// When in playing/listening state but no audio level updates are received,
/// the waveform animates with simulated random values for visual feedback.
struct DockWaveformView: View {
    
    // MARK: - Configuration
    
    /// Number of bars in the waveform
    private let barCount = 9
    
    /// Size of idle dots (width AND height for perfect circles)
    private let dotSize: CGFloat = 6
    
    /// Maximum bar height when animating
    private let maxHeight: CGFloat = 28
    
    /// Bar width (same as dot size for smooth morph)
    private let barWidth: CGFloat = 6
    
    /// Spacing between bars
    private let barSpacing: CGFloat = 6
    
    // MARK: - Properties
    
    /// Current waveform state
    let state: WaveformState
    
    /// Audio level (0.0 - 1.0) for reactive animation
    var audioLevel: CGFloat = 0.0
    
    // MARK: - State
    
    @State private var barHeights: [CGFloat] = Array(repeating: 6, count: 9)
    @State private var waitingPulse: Bool = false
    @State private var animationTimer: Timer?
    @State private var isAnimating: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    height: barHeights[index],
                    maxHeight: maxHeight,
                    width: barWidth,
                    color: barColor
                )
            }
        }
        .opacity(waitingOpacity)
        .onAppear {
            initializeBarHeights()
            handleStateChange(to: state)
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(to: newState)
        }
        .onChange(of: audioLevel) { _, newLevel in
            if (state == .playing || state == .listening) && newLevel > 0 {
                updateBarsForAudioLevel(newLevel)
            }
        }
        .onDisappear {
            stopFallbackAnimation()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Color based on current state
    private var barColor: Color {
        switch state {
        case .listening:
            return Color.green
        default:
            return AppColors.accent
        }
    }
    
    /// Opacity for waiting pulse
    private var waitingOpacity: Double {
        state == .waiting ? (waitingPulse ? 1.0 : 0.5) : 1.0
    }
    
    // MARK: - Initialization
    
    private func initializeBarHeights() {
        barHeights = Array(repeating: dotSize, count: barCount)
    }
    
    // MARK: - State Handling
    
    private func handleStateChange(to newState: WaveformState) {
        // Stop any existing animation
        stopFallbackAnimation()
        waitingPulse = false
        
        switch newState {
        case .idle:
            settleToIdle()
            
        case .playing, .listening:
            // Start fallback animation (will animate even without audio data)
            startFallbackAnimation()
            
        case .settling:
            settleToIdle()
            
        case .waiting:
            settleToIdle()
            startWaitingPulse()
        }
    }
    
    // MARK: - Fallback Animation
    
    /// Starts a timer-based animation for when no audio level updates are received
    private func startFallbackAnimation() {
        isAnimating = true
        
        // Use a timer to animate bars with random values
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard isAnimating else { return }
            
            // Generate random levels for organic feel
            let baseLevel = CGFloat.random(in: 0.3...0.8)
            updateBarsForAudioLevel(baseLevel)
        }
    }
    
    /// Stops the fallback animation timer
    private func stopFallbackAnimation() {
        isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    // MARK: - Animation Methods
    
    /// Updates bar heights based on audio level with natural variation
    private func updateBarsForAudioLevel(_ level: CGFloat) {
        let baseLevel = max(0.1, min(1.0, level))
        
        withAnimation(.easeOut(duration: 0.08)) {
            barHeights = (0..<barCount).map { index in
                // Create natural wave pattern - center bars tend to be taller
                let centerDistance = abs(CGFloat(index) - CGFloat(barCount - 1) / 2)
                let centerBias = 1.0 - (centerDistance / CGFloat(barCount / 2)) * 0.3
                
                // Add randomness for organic feel
                let randomVariation = CGFloat.random(in: 0.6...1.4)
                
                // Calculate final height
                let normalizedHeight = baseLevel * centerBias * randomVariation
                let height = dotSize + (maxHeight - dotSize) * normalizedHeight
                
                return max(dotSize, min(maxHeight, height))
            }
        }
    }
    
    /// Smoothly transitions bars back to idle dots
    private func settleToIdle() {
        withAnimation(.easeOut(duration: 0.4)) {
            barHeights = Array(repeating: dotSize, count: barCount)
        }
    }
    
    /// Starts the waiting pulse animation
    private func startWaitingPulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            waitingPulse = true
        }
    }
}

// MARK: - WaveformBar

/// Individual bar in the waveform
struct WaveformBar: View {
    
    let height: CGFloat
    let maxHeight: CGFloat
    let width: CGFloat
    let color: Color
    
    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .frame(height: maxHeight, alignment: .center)
    }
}

// MARK: - Previews

#Preview("Waveform - Idle") {
    ZStack {
        AppColors.backgroundSecondary
        DockWaveformView(state: .idle)
    }
    .frame(height: 60)
    .padding()
}

#Preview("Waveform - Playing (Auto-Animating)") {
    ZStack {
        AppColors.backgroundSecondary
        DockWaveformView(state: .playing, audioLevel: 0)
    }
    .frame(height: 60)
    .padding()
}

#Preview("Waveform - Listening (Green, Auto-Animating)") {
    ZStack {
        AppColors.backgroundSecondary
        DockWaveformView(state: .listening, audioLevel: 0)
    }
    .frame(height: 60)
    .padding()
}

#Preview("Waveform - Waiting") {
    ZStack {
        AppColors.backgroundSecondary
        DockWaveformView(state: .waiting)
    }
    .frame(height: 60)
    .padding()
}

#Preview("Waveform - All States") {
    VStack(spacing: 20) {
        Group {
            VStack {
                Text("Idle").font(.caption)
                DockWaveformView(state: .idle)
            }
            
            VStack {
                Text("Waiting").font(.caption)
                DockWaveformView(state: .waiting)
            }
            
            VStack {
                Text("Playing (auto)").font(.caption)
                DockWaveformView(state: .playing)
            }
            
            VStack {
                Text("Listening (green, auto)").font(.caption)
                DockWaveformView(state: .listening)
            }
        }
        .frame(height: 50)
    }
    .padding()
    .background(AppColors.backgroundSecondary)
}
