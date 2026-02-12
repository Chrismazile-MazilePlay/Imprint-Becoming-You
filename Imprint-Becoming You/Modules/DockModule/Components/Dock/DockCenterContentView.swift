//
//  DockCenterContentView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockCenterContentView

/// The unified center content view that orchestrates waveform and score display.
///
/// This is the **single instance** view that handles all center content states.
/// It routes between waveform visualization and score display based on the
/// current state, with smooth transitions between them.
///
/// ## Animation Architecture
///
/// This view wraps content in a `TimelineView(.animation)` to provide a single,
/// consistent animation source for all waveforms. The computed `breathingPhase`
/// (0.0-1.0 continuous) is passed to each waveform, ensuring:
/// - All waveforms animate in perfect sync
/// - No duplicate TimelineView instances
/// - Consistent timing across different waveform styles
///
/// ## Waveform Style Selection
///
/// The waveform type is set via environment using `dockWaveformType`:
///
/// ```swift
/// DockCenterContentView(state: .playing(audioLevel: 0.7))
///     .dockWaveformType(.layeredWaves)  // or .classicBars
/// ```
///
/// ## State Routing
///
/// | State             | Display                    |
/// |-------------------|----------------------------|
/// | `.hidden`         | Nothing (zero opacity)     |
/// | `.idle`           | Waveform (small dots)      |
/// | `.playing`        | Waveform (animated, accent)|
/// | `.preparing`      | Waveform (breathing, green)|
/// | `.listening`      | Waveform (animated, green) |
/// | `.settling`       | Waveform (settling down)   |
/// | `.settling`       | Waveform (settling down)   |
///
/// ## Usage
///
/// ```swift
/// DockCenterContentView(state: adapter.centerContentState)
/// ```
public struct DockCenterContentView: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    @Environment(\.dockWaveformType) private var waveformType
    
    // MARK: - Properties
    
    /// The current center content state.
    public let state: DockCenterContentState
    
    // MARK: - Initialization
    
    /// Creates a new center content view.
    ///
    /// - Parameter state: The current center content state
    public init(state: DockCenterContentState) {
        self.state = state
    }
    
    // MARK: - Body
    
    public var body: some View {
        TimelineView(.animation) { timeline in
            let breathingPhase = computeBreathingPhase(from: timeline.date)
            
            ZStack {
                // Waveform (visible for most states) - uses injected type
                if showsWaveform {
                    waveformView(breathingPhase: breathingPhase)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: 40)
        .animation(tokens.standardAnimation, value: state)
        .opacity(state == .hidden ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(accessibilityValue)
    }
    
    // MARK: - Accessibility
    
    /// Accessibility description based on current state
    private var accessibilityDescription: String {
        switch state {
        case .hidden:
            return "Audio visualization hidden"
        case .idle:
            return "Audio visualization idle"
        case .playing:
            return "Audio playing"
        case .preparing:
            return "Preparing to listen"
        case .listening:
            return "Listening to your voice"
        case .settling:
            return "Processing your speech"
        }
    }
    
    /// Accessibility value for states that have values
    private var accessibilityValue: String {
        switch state {
        case .playing(let audioLevel):
            return "Audio level \(Int(audioLevel * 100)) percent"
        case .listening(let audioLevel):
            return "Audio level \(Int(audioLevel * 100)) percent"
        default:
            return ""
        }
    }
    
    // MARK: - Breathing Phase Calculation
    
    /// Computes a continuous breathing phase (0.0-1.0) from the timeline date.
    ///
    /// Uses a 2-second cycle for smooth, natural breathing animation.
    /// This provides a single animation source for all waveforms.
    ///
    /// - Parameter date: The current timeline date
    /// - Returns: A value from 0.0 to 1.0 representing the breathing phase
    private func computeBreathingPhase(from date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate
        return CGFloat((elapsed / 2.0).truncatingRemainder(dividingBy: 1.0))
    }
    
    // MARK: - Waveform View
    
    /// Renders the appropriate waveform based on the selected type.
    @ViewBuilder
    private func waveformView(breathingPhase: CGFloat) -> some View {
        switch waveformType {
        case .layeredWaves:
            LayeredWavesWaveformView(state: state, tokens: tokens, breathingPhase: breathingPhase)
        case .classicBars:
            ClassicBarsWaveformView(state: state, tokens: tokens, breathingPhase: breathingPhase)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether the current state shows the waveform.
    private var showsWaveform: Bool {
        switch state {
        case .hidden:
            return false
        default:
            return true
        }
    }
}

// MARK: - Previews

#Preview("Center Content - Idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockCenterContentView(state: .idle)
    }
}

#Preview("Center Content - Playing") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockCenterContentView(state: .playing(audioLevel: 0.7))
    }
}

#Preview("Center Content - Listening") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockCenterContentView(state: .listening(audioLevel: 0.6))
    }
}

#Preview("Center Content - Classic Bars Style") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockCenterContentView(state: .playing(audioLevel: 0.7))
            .dockWaveformType(.classicBars)
    }
}

#Preview("Center Content - Layered Waves Style") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockCenterContentView(state: .playing(audioLevel: 0.7))
            .dockWaveformType(.layeredWaves)
    }
}

#Preview("Center Content - State Cycle") {
    struct CyclePreview: View {
        @State private var index = 0
        
        private let states: [DockCenterContentState] = [
            .idle,
            .playing(audioLevel: 0.7),
            .preparing,
            .listening(audioLevel: 0.6),
            .settling
        ]
        
        var body: some View {
            VStack(spacing: 32) {
                DockCenterContentView(state: states[index])
                
                Button("Next") {
                    withAnimation {
                        index = (index + 1) % states.count
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.black)
        }
    }
    
    return CyclePreview()
}
