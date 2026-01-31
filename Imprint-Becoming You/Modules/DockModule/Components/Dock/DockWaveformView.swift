//
//  DockWaveformView.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/19/26.
//

import SwiftUI

// MARK: - DockWaveformView

/// A waveform visualization using pure SwiftUI animations.
///
/// This view renders animated bars that respond to different states (playing, listening,
/// waiting, etc.) with smooth transitions. It is completely decoupled from TTS callbacks
/// and session state — it only knows about visualization states.
///
/// ## Choreographed Transition (Playing → Listening)
///
/// When transitioning from TTS playback to mic listening, the waveform performs
/// a three-phase visual choreography:
///
/// 1. **Scale Down** (~0.2s): Bars animate to minimum height (still orange)
/// 2. **Color Morph** (~0.15s): Color transitions from orange to green
/// 3. **Scale Up** (~0.2s): Bars animate back to active height (now green)
///
/// This creates a smooth "handoff" visual from TTS to microphone input.
///
/// ## Usage
///
/// ```swift
/// DockWaveformView(state: .playing(audioLevel: 0.7))
/// DockWaveformView(state: .listening(audioLevel: 0.5))
/// ```
public struct DockWaveformView: View {
    
    // MARK: - Environment
    
    @Environment(\.dockDesignTokens) private var tokens
    
    // MARK: - Properties
    
    /// The current visualization state.
    public let state: DockCenterContentState
    
    // MARK: - Configuration Constants
    
    private let barCount: Int = 9
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 4
    private let maxBarHeight: CGFloat = 32
    private let minBarHeight: CGFloat = 3
    
    // MARK: - Transition Timing
    
    private let scaleDownDuration: TimeInterval = 0.2
    private let colorMorphDuration: TimeInterval = 0.15
    private let scaleUpDuration: TimeInterval = 0.2
    
    // MARK: - Animation State
    
    /// Current waveform configuration (animatable).
    @State private var config: WaveformConfiguration = .idle
    
    /// Breathing phase toggle (0 or 1) for continuous animation.
    @State private var breathingPhase: CGFloat = 0
    
    /// Per-bar random offsets for organic movement.
    @State private var barOffsets: [CGFloat] = []
    
    /// Tracks the previous state for detecting transitions.
    @State private var previousState: DockCenterContentState?
    
    /// Whether we're in the middle of a choreographed transition.
    @State private var isInChoreographedTransition: Bool = false
    
    // MARK: - Initialization
    
    public init(state: DockCenterContentState) {
        self.state = state
    }
    
    // MARK: - Body
    
    public var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    barCount: barCount,
                    config: config,
                    audioLevel: isInChoreographedTransition ? 0 : (state.audioLevel ?? 0),
                    breathingPhase: breathingPhase,
                    randomOffset: barOffsets.indices.contains(index) ? barOffsets[index] : 0,
                    barWidth: barWidth,
                    minHeight: minBarHeight,
                    maxHeight: maxBarHeight,
                    accentColor: tokens.accent,
                    listeningColor: tokens.success
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStateDescription)
        .accessibilityValue(accessibilityValueDescription)
        .onAppear {
            initializeBarOffsets()
            config = configuration(for: state)
            previousState = state
            startBreathingAnimation()
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }
    
    // MARK: - Accessibility
    
    /// Provides a VoiceOver-friendly description of the current waveform state.
    private var accessibilityStateDescription: String {
        switch state {
        case .hidden:
            return "Audio visualization hidden"
        case .idle:
            return "Audio visualization idle"
        case .playing:
            return "Playing audio"
        case .preparing:
            return "Preparing to listen"
        case .listening:
            return "Listening for your voice"
        case .settling:
            return "Processing speech"
        case .showingScore:
            return "Showing score"
        }
    }
    
    /// Provides the audio level as an accessibility value when applicable.
    private var accessibilityValueDescription: String {
        guard let audioLevel = state.audioLevel else {
            return ""
        }
        let percentage = Int(audioLevel * 100)
        return "Audio level \(percentage) percent"
    }
    
    // MARK: - Initialization Helpers
    
    private func initializeBarOffsets() {
        barOffsets = (0..<barCount).map { index in
            // Golden ratio based distribution for organic feel
            let seed = CGFloat(index) * 1.618
            return (seed.truncatingRemainder(dividingBy: 1.0)) * 2 - 1 // -1 to 1
        }
    }
    
    // MARK: - Breathing Animation
    
    private func startBreathingAnimation() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            breathingPhase = 1
        }
    }
    
    // MARK: - State Change Handling
    
    private func handleStateChange(from oldState: DockCenterContentState, to newState: DockCenterContentState) {
        // Check if this needs a choreographed transition
        let transitionType = determineTransitionType(from: oldState, to: newState)
        
        switch transitionType {
        case .playingToPreparing:
            performPlayingToPreparingTransition()
        case .preparingToListening:
            performPreparingToListeningTransition()
        case .playingToListening:
            // Direct transition (legacy support) - do full choreography
            performFullPlayingToListeningTransition(targetState: newState)
        case .standard:
            transitionToState(newState)
        }
        
        previousState = newState
    }
    
    /// Types of state transitions
    private enum TransitionType {
        case playingToPreparing    // Scale down + color morph to green
        case preparingToListening  // Scale up (already green)
        case playingToListening    // Full choreography (legacy)
        case standard              // Normal animated transition
    }
    
    /// Determines which transition choreography to use.
    private func determineTransitionType(
        from oldState: DockCenterContentState,
        to newState: DockCenterContentState
    ) -> TransitionType {
        switch (oldState, newState) {
        case (.playing, .preparing):
            return .playingToPreparing
        case (.preparing, .listening):
            return .preparingToListening
        case (.playing, .listening):
            // Direct playing → listening (legacy, in case .preparing is skipped)
            return .playingToListening
        default:
            return .standard
        }
    }
    
    // MARK: - Choreographed Transitions
    
    /// Phase 1: Playing → Preparing
    /// Scale DOWN + color MORPH (orange → green breathing)
    private func performPlayingToPreparingTransition() {
        isInChoreographedTransition = true
        
        // Phase 1: Scale DOWN (still orange)
        withAnimation(.easeIn(duration: scaleDownDuration)) {
            config = .transitionScaledDown
        }
        
        // Phase 2: Color MORPH to green + breathing
        DispatchQueue.main.asyncAfter(deadline: .now() + scaleDownDuration) {
            self.isInChoreographedTransition = false
            
            withAnimation(.easeInOut(duration: self.colorMorphDuration)) {
                self.config = .preparingToListen
            }
        }
    }
    
    /// Phase 2: Preparing → Listening
    /// Scale UP to active listening (already green)
    private func performPreparingToListeningTransition() {
        withAnimation(.easeOut(duration: scaleUpDuration)) {
            config = .listening
        }
        
        // Randomize offsets for organic feel
        shuffleBarOffsets()
    }
    
    /// Full choreography for direct playing → listening (legacy support)
    ///
    /// Phase 1: Scale DOWN (bars to minimum, still orange)
    /// Phase 2: Color MORPH (orange → green at minimum amplitude)
    /// Phase 3: Scale UP (bars to active height, now green)
    private func performFullPlayingToListeningTransition(targetState: DockCenterContentState) {
        isInChoreographedTransition = true
        
        // Phase 1: Scale DOWN (still orange)
        withAnimation(.easeIn(duration: scaleDownDuration)) {
            config = .transitionScaledDown
        }
        
        // Phase 2: Color MORPH (at minimum amplitude)
        DispatchQueue.main.asyncAfter(deadline: .now() + scaleDownDuration) {
            withAnimation(.easeInOut(duration: self.colorMorphDuration)) {
                self.config = .transitionColorMorphed
            }
        }
        
        // Phase 3: Scale UP (now green, listening)
        let phase3Delay = scaleDownDuration + colorMorphDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + phase3Delay) {
            self.isInChoreographedTransition = false
            
            withAnimation(.easeOut(duration: self.scaleUpDuration)) {
                self.config = self.configuration(for: targetState)
            }
            
            // Randomize offsets for organic feel
            self.shuffleBarOffsets()
        }
    }
    
    // MARK: - Standard Transitions
    
    private func transitionToState(_ newState: DockCenterContentState) {
        let newConfig = configuration(for: newState)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            config = newConfig
        }
        
        // Randomize offsets on state change for organic feel
        if newConfig.randomization > 0 {
            shuffleBarOffsets()
        }
    }
    
    private func shuffleBarOffsets() {
        withAnimation(.easeInOut(duration: 0.4)) {
            barOffsets = barOffsets.map { offset in
                let variation = CGFloat.random(in: -0.3...0.3)
                return max(-1, min(1, offset + variation))
            }
        }
    }
    
    // MARK: - Configuration Mapping
    
    private func configuration(for state: DockCenterContentState) -> WaveformConfiguration {
        switch state {
        case .hidden:
            return .hidden
        case .idle:
            return .idle
        case .playing:
            return .speaking
        case .preparing:
            return .preparingToListen
        case .listening:
            return .listening
        case .settling:
            return .listeningSettling
        case .showingScore:
            return .hidden
        }
    }
}

// MARK: - WaveformBar

/// Individual animated bar in the waveform.
private struct WaveformBar: View {
    let index: Int
    let barCount: Int
    let config: WaveformConfiguration
    let audioLevel: CGFloat
    let breathingPhase: CGFloat
    let randomOffset: CGFloat
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let accentColor: Color
    let listeningColor: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(barColor)
            .frame(width: barWidth, height: barHeight)
            .animation(.easeInOut(duration: 0.15), value: audioLevel)
            .animation(.easeInOut(duration: 0.3), value: config)
            .accessibilityHidden(true)
    }
    
    // MARK: - Height Calculation
    
    private var barHeight: CGFloat {
        // Base intensity from configuration
        var height = config.intensity
        
        // Breathing contribution (sine wave based on phase)
        let breathingWave = sin(breathingPhase * .pi)
        height += breathingWave * config.breathingAmplitude
        
        // Per-bar wave pattern (center bars taller)
        let centerDistance = abs(CGFloat(index) - CGFloat(barCount - 1) / 2)
        let centerFactor = 1.0 - (centerDistance / CGFloat(barCount)) * (1.0 / config.dampingScale)
        height *= centerFactor
        
        // Per-bar phase offset for wave effect
        let phaseOffset = CGFloat(index) / CGFloat(barCount) * .pi
        let wavePattern = (sin(breathingPhase * .pi * 2 + phaseOffset) + 1) / 2
        height *= (0.7 + wavePattern * 0.3)
        
        // Randomization for organic feel
        if config.randomization > 0 {
            height += randomOffset * config.randomization * 0.2
        }
        
        // Audio reactivity
        if config.audioReactivity > 0 {
            let audioBoost = audioLevel * config.audioReactivity * 0.5
            height += audioBoost
        }
        
        // Map to pixel height
        let heightRange = maxHeight - minHeight
        let pixelHeight = minHeight + (height * heightRange)
        
        return max(minHeight, min(maxHeight, pixelHeight))
    }
    
    // MARK: - Color Calculation
    
    private var barColor: Color {
        if config.colorBlend <= 0 {
            return accentColor
        } else if config.colorBlend >= 1 {
            return listeningColor
        } else {
            return Color.lerp(from: accentColor, to: listeningColor, t: config.colorBlend)
        }
    }
}

// MARK: - WaveformConfiguration

/// Configuration for waveform animation behavior.
///
/// All properties are animatable, enabling smooth transitions between states.
private struct WaveformConfiguration: Equatable {
    
    /// Base animation intensity (0.0 - 1.0)
    let intensity: CGFloat
    
    /// Color blend: 0 = accent (orange), 1 = listening (green)
    let colorBlend: CGFloat
    
    /// Audio reactivity level (0.0 - 1.0)
    let audioReactivity: CGFloat
    
    /// Breathing animation amplitude (0.0 - 0.5)
    let breathingAmplitude: CGFloat
    
    /// Per-bar damping variation scale (1.0 - 5.0)
    let dampingScale: CGFloat
    
    /// Randomization factor (0.0 - 1.0)
    let randomization: CGFloat
    
    // MARK: - Presets
    
    /// Hidden state - no animation
    static let hidden = WaveformConfiguration(
        intensity: 0,
        colorBlend: 0,
        audioReactivity: 0,
        breathingAmplitude: 0,
        dampingScale: 3.5,
        randomization: 0
    )
    
    /// Idle state - minimal subtle animation
    static let idle = WaveformConfiguration(
        intensity: 0.15,
        colorBlend: 0,
        audioReactivity: 0,
        breathingAmplitude: 0.02,
        dampingScale: 3.5,
        randomization: 0
    )
    
    /// TTS speaking - accent color (orange), animated with randomization
    static let speaking = WaveformConfiguration(
        intensity: 0.45,
        colorBlend: 0,
        audioReactivity: 0.5,
        breathingAmplitude: 0.05,
        dampingScale: 3.5,
        randomization: 0.65
    )
    
    /// Waiting for user - accent color, gentle breathing
    static let breathing = WaveformConfiguration(
        intensity: 0.25,
        colorBlend: 0,
        audioReactivity: 0,
        breathingAmplitude: 0.3,
        dampingScale: 3.5,
        randomization: 0
    )
    
    /// Preparing to listen - green color, gentle breathing
    /// Shows while speech recognition engine initializes
    static let preparingToListen = WaveformConfiguration(
        intensity: 0.25,
        colorBlend: 1.0,      // Green (success color)
        audioReactivity: 0,
        breathingAmplitude: 0.25,
        dampingScale: 3.5,
        randomization: 0
    )
    
    /// User speaking - green color, audio reactive
    static let listening = WaveformConfiguration(
        intensity: 0.45,
        colorBlend: 1.0,
        audioReactivity: 0.65,
        breathingAmplitude: 0.05,
        dampingScale: 3.5,
        randomization: 0.65
    )
    
    /// Settling after listening - green, gentle
    static let listeningSettling = WaveformConfiguration(
        intensity: 0.25,
        colorBlend: 1.0,
        audioReactivity: 0,
        breathingAmplitude: 0.3,
        dampingScale: 3.5,
        randomization: 0
    )
    
    // MARK: - Transition States (for choreographed playing → listening)
    
    /// Phase 1: Scaled down, still orange
    static let transitionScaledDown = WaveformConfiguration(
        intensity: 0.05,      // Near minimum
        colorBlend: 0,        // Still orange
        audioReactivity: 0,
        breathingAmplitude: 0,
        dampingScale: 3.5,
        randomization: 0
    )
    
    /// Phase 2: Scaled down, now green
    static let transitionColorMorphed = WaveformConfiguration(
        intensity: 0.05,      // Still near minimum
        colorBlend: 1.0,      // Now green
        audioReactivity: 0,
        breathingAmplitude: 0,
        dampingScale: 3.5,
        randomization: 0
    )
}

// MARK: - Color Interpolation

private extension Color {
    
    /// Linear interpolation between two colors.
    static func lerp(from: Color, to: Color, t: CGFloat) -> Color {
        let t = max(0, min(1, t))
        let fromRGBA = from.rgbaComponents
        let toRGBA = to.rgbaComponents
        
        return Color(
            red: fromRGBA.red + (toRGBA.red - fromRGBA.red) * t,
            green: fromRGBA.green + (toRGBA.green - fromRGBA.green) * t,
            blue: fromRGBA.blue + (toRGBA.blue - fromRGBA.blue) * t,
            opacity: fromRGBA.alpha + (toRGBA.alpha - fromRGBA.alpha) * t
        )
    }
    
    /// Extract RGBA components from color.
    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }
}

// MARK: - Previews

#Preview("Waveform - Idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockWaveformView(state: .idle)
    }
}

#Preview("Waveform - Playing (Orange)") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockWaveformView(state: .playing(audioLevel: 0.7))
    }
}

#Preview("Waveform - Listening (Green)") {
    ZStack {
        Color.black.ignoresSafeArea()
        DockWaveformView(state: .listening(audioLevel: 0.6))
    }
}

#Preview("Waveform - Transition Demo") {
    struct TransitionDemo: View {
        @State private var state: DockCenterContentState = .playing(audioLevel: 0.7)
        
        var body: some View {
            VStack(spacing: 32) {
                Text(stateLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                DockWaveformView(state: state)
                    .frame(height: 40)
                
                Button("Toggle Playing ↔ Listening") {
                    if case .playing = state {
                        state = .listening(audioLevel: 0.6)
                    } else {
                        state = .playing(audioLevel: 0.7)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.black)
        }
        
        var stateLabel: String {
            switch state {
            case .playing: return "Playing (Orange)"
            case .listening: return "Listening (Green)"
            default: return "Other"
            }
        }
    }
    
    return TransitionDemo()
}

#Preview("Waveform - All States") {
    struct StatesCyclePreview: View {
        @State private var stateIndex = 0
        
        private let states: [(String, DockCenterContentState)] = [
            ("Idle", .idle),
            ("Playing (Orange)", .playing(audioLevel: 0.7)),
            ("Listening (Green)", .listening(audioLevel: 0.6)),
            ("Settling", .settling),
        ]
        
        var body: some View {
            VStack(spacing: 32) {
                Text(states[stateIndex].0)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                DockWaveformView(state: states[stateIndex].1)
                    .frame(height: 40)
                
                Button("Next State") {
                    stateIndex = (stateIndex + 1) % states.count
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.black)
        }
    }
    
    return StatesCyclePreview()
}
