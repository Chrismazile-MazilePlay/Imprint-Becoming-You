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
/// | `.showingScore`   | Score display (animated %) |
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
        ZStack {
            // Waveform (visible for most states) - uses injected type
            if showsWaveform {
                waveformView
                    .transition(.opacity)
            }
            
            // Score display (visible only for showingScore)
            if case .showingScore(let score) = state {
                DockScoreDisplay(score: score)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 40)
        .animation(tokens.standardAnimation, value: isShowingScore)
        .opacity(state == .hidden ? 0 : 1)
    }
    
    // MARK: - Waveform View
    
    /// Renders the appropriate waveform based on the selected type.
    @ViewBuilder
    private var waveformView: some View {
        switch waveformType {
        case .layeredWaves:
            LayeredWavesWaveformView(state: state, tokens: tokens)
        case .classicBars:
            ClassicBarsWaveformView(state: state, tokens: tokens)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether the current state shows the waveform.
    private var showsWaveform: Bool {
        switch state {
        case .hidden, .showingScore:
            return false
        default:
            return true
        }
    }
    
    /// Whether the current state is showing a score.
    private var isShowingScore: Bool {
        if case .showingScore = state {
            return true
        }
        return false
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

#Preview("Center Content - Score") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockCenterContentView(state: .showingScore(percentScore: 87))
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
            .settling,
            .showingScore(percentScore: 85)
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
