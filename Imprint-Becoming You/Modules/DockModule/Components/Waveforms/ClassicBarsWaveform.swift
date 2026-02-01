//
//  ClassicBarsWaveform.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/21/26.
//

import SwiftUI

// MARK: - Pre-computed Color Values

/// Pre-computed RGBA values for efficient color interpolation.
///
/// Caches the RGBA components of accent and listening colors to avoid
/// repeated `UIColor` bridge creation during animation frames.
///
/// ## Performance Benefits
/// - Extracts RGBA values once at initialization (not per frame)
/// - Caches common blend values (0, 0.5, 1.0) for fast lookup
/// - Eliminates 540 UIColor allocations/second (60fps × 9 bars)
///
/// ## Usage
/// ```swift
/// let cache = ColorCache(accent: tokens.accent, listening: tokens.success)
/// let blendedColor = cache.lerp(t: 0.5)
/// ```
private struct ColorCache: Equatable {
    
    // MARK: - Pre-computed RGBA Components
    
    private let accentRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    private let listeningRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    
    // MARK: - Cached Colors for Common Blend Values
    
    /// Original accent color (colorBlend = 0)
    let accentColor: Color
    
    /// Original listening color (colorBlend = 1)
    let listeningColor: Color
    
    /// Pre-computed 50% blend for quick lookup
    let midBlendColor: Color
    
    // MARK: - Initialization
    
    /// Creates a color cache with pre-computed RGBA values.
    ///
    /// - Parameters:
    ///   - accent: The accent color (used when colorBlend = 0)
    ///   - listening: The listening color (used when colorBlend = 1)
    init(accent: Color, listening: Color) {
        // Extract RGBA once at initialization
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        
        #if canImport(UIKit)
        UIColor(accent).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        UIColor(listening).getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        #endif
        
        self.accentRGBA = (ar, ag, ab, aa)
        self.listeningRGBA = (lr, lg, lb, la)
        
        // Cache original colors
        self.accentColor = accent
        self.listeningColor = listening
        
        // Pre-compute 50% blend
        self.midBlendColor = Color(
            red: (ar + lr) / 2,
            green: (ag + lg) / 2,
            blue: (ab + lb) / 2,
            opacity: (aa + la) / 2
        )
    }
    
    // MARK: - Fast Interpolation
    
    /// Fast color interpolation using pre-computed RGBA values.
    ///
    /// - Parameter t: Blend factor (0 = accent, 1 = listening)
    /// - Returns: Interpolated color
    func lerp(t: CGFloat) -> Color {
        // Fast paths for common values
        if t <= 0 { return accentColor }
        if t >= 1 { return listeningColor }
        if abs(t - 0.5) < 0.01 { return midBlendColor }
        
        // General interpolation using pre-computed RGBA
        let clampedT = max(0, min(1, t))
        return Color(
            red: accentRGBA.r + (listeningRGBA.r - accentRGBA.r) * clampedT,
            green: accentRGBA.g + (listeningRGBA.g - accentRGBA.g) * clampedT,
            blue: accentRGBA.b + (listeningRGBA.b - accentRGBA.b) * clampedT,
            opacity: accentRGBA.a + (listeningRGBA.a - accentRGBA.a) * clampedT
        )
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ColorCache, rhs: ColorCache) -> Bool {
        // Compare by RGBA values (more reliable than Color equality)
        lhs.accentRGBA.r == rhs.accentRGBA.r &&
        lhs.accentRGBA.g == rhs.accentRGBA.g &&
        lhs.accentRGBA.b == rhs.accentRGBA.b &&
        lhs.accentRGBA.a == rhs.accentRGBA.a &&
        lhs.listeningRGBA.r == rhs.listeningRGBA.r &&
        lhs.listeningRGBA.g == rhs.listeningRGBA.g &&
        lhs.listeningRGBA.b == rhs.listeningRGBA.b &&
        lhs.listeningRGBA.a == rhs.listeningRGBA.a
    }
}

// MARK: - ClassicBarsWaveformStyle

/// Classic bar-based waveform style using equalizer-style animated bars.
///
/// This is the original waveform visualization, featuring animated bars
/// that respond to audio levels with rhythmic movement.
public struct ClassicBarsWaveformStyle: DockWaveformStyle {
    
    public init() {}
    
    public func makeBody(state: DockCenterContentState, tokens: DockDesignTokens) -> some View {
        // Note: When used through the style protocol, we need internal TimelineView
        // When used directly from DockCenterContentView, breathingPhase is provided
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((elapsed / 2.0).truncatingRemainder(dividingBy: 1.0))
            ClassicBarsWaveformView(state: state, tokens: tokens, breathingPhase: phase)
        }
    }
}

// MARK: - ClassicBarsWaveformView

/// A bar-based waveform visualization using pure SwiftUI animations.
///
/// Renders animated bars that respond to different states (playing, listening,
/// waiting, etc.) with smooth transitions.
///
/// ## Animation Architecture
///
/// The `breathingPhase` is provided by the parent container (`DockCenterContentView`)
/// which wraps all waveforms in a single `TimelineView`. This ensures:
/// - All waveforms animate in perfect sync
/// - No duplicate TimelineView instances
/// - Consistent timing across different waveform styles
///
/// ## Performance Optimization
///
/// Color interpolation uses pre-computed RGBA values via `ColorCache` to avoid
/// creating `UIColor` bridge objects on every animation frame. This eliminates
/// ~540 allocations/second (60fps × 9 bars).
struct ClassicBarsWaveformView: View {
    
    // MARK: - Properties
    
    let state: DockCenterContentState
    let tokens: DockDesignTokens
    
    /// Continuous breathing phase (0.0-1.0) provided by parent TimelineView.
    let breathingPhase: CGFloat
    
    // MARK: - Pre-computed Colors
    
    /// Cached color values for efficient interpolation.
    private let colorCache: ColorCache
    
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
    
    @State private var config: ClassicBarsConfiguration = .idle
    @State private var barOffsets: [CGFloat] = []
    @State private var previousState: DockCenterContentState?
    @State private var isInChoreographedTransition: Bool = false
    
    // MARK: - Initialization
    
    init(state: DockCenterContentState, tokens: DockDesignTokens, breathingPhase: CGFloat) {
        self.state = state
        self.tokens = tokens
        self.breathingPhase = breathingPhase
        
        // Pre-compute colors once at initialization
        self.colorCache = ColorCache(accent: tokens.accent, listening: tokens.success)
    }
    
    // MARK: - Body
    
    var body: some View {
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
                    colorCache: colorCache
                )
            }
        }
        .onAppear {
            initializeBarOffsets()
            config = configuration(for: state)
            previousState = state
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
    }
    
    // MARK: - Initialization Helpers
    
    private func initializeBarOffsets() {
        barOffsets = (0..<barCount).map { index in
            let seed = CGFloat(index) * 1.618
            return (seed.truncatingRemainder(dividingBy: 1.0)) * 2 - 1
        }
    }
    
    // MARK: - State Change Handling
    
    private func handleStateChange(from oldState: DockCenterContentState, to newState: DockCenterContentState) {
        let transitionType = determineTransitionType(from: oldState, to: newState)
        
        switch transitionType {
        case .playingToPreparing:
            performPlayingToPreparingTransition()
        case .preparingToListening:
            performPreparingToListeningTransition()
        case .playingToListening:
            performFullPlayingToListeningTransition(targetState: newState)
        case .standard:
            transitionToState(newState)
        }
        
        previousState = newState
    }
    
    private enum TransitionType {
        case playingToPreparing
        case preparingToListening
        case playingToListening
        case standard
    }
    
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
            return .playingToListening
        default:
            return .standard
        }
    }
    
    // MARK: - Choreographed Transitions
    
    private func performPlayingToPreparingTransition() {
        isInChoreographedTransition = true
        
        withAnimation(.easeIn(duration: scaleDownDuration)) {
            config = .transitionScaledDown
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + scaleDownDuration) {
            self.isInChoreographedTransition = false
            withAnimation(.easeInOut(duration: self.colorMorphDuration)) {
                self.config = .preparingToListen
            }
        }
    }
    
    private func performPreparingToListeningTransition() {
        withAnimation(.easeOut(duration: scaleUpDuration)) {
            config = .listening
        }
        shuffleBarOffsets()
    }
    
    private func performFullPlayingToListeningTransition(targetState: DockCenterContentState) {
        isInChoreographedTransition = true
        
        withAnimation(.easeIn(duration: scaleDownDuration)) {
            config = .transitionScaledDown
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + scaleDownDuration) {
            withAnimation(.easeInOut(duration: self.colorMorphDuration)) {
                self.config = .transitionColorMorphed
            }
        }
        
        let phase3Delay = scaleDownDuration + colorMorphDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + phase3Delay) {
            self.isInChoreographedTransition = false
            withAnimation(.easeOut(duration: self.scaleUpDuration)) {
                self.config = self.configuration(for: targetState)
            }
            self.shuffleBarOffsets()
        }
    }
    
    // MARK: - Standard Transitions
    
    private func transitionToState(_ newState: DockCenterContentState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            config = configuration(for: newState)
        }
    }
    
    private func shuffleBarOffsets() {
        withAnimation(.easeInOut(duration: 0.2)) {
            barOffsets = barOffsets.map { _ in
                CGFloat.random(in: -1...1)
            }
        }
    }
    
    // MARK: - Configuration Mapping
    
    private func configuration(for state: DockCenterContentState) -> ClassicBarsConfiguration {
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

private struct WaveformBar: View {
    let index: Int
    let barCount: Int
    let config: ClassicBarsConfiguration
    let audioLevel: CGFloat
    let breathingPhase: CGFloat
    let randomOffset: CGFloat
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let colorCache: ColorCache
    
    var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(barColor)
            .frame(width: barWidth, height: barHeight)
            .animation(.easeInOut(duration: 0.15), value: audioLevel)
            .animation(.easeInOut(duration: 0.3), value: config)
    }
    
    // MARK: - Computed Properties
    
    private var normalizedIndex: CGFloat {
        CGFloat(index) / CGFloat(barCount - 1)
    }
    
    private var centerWeight: CGFloat {
        let distanceFromCenter = abs(normalizedIndex - 0.5) * 2
        return 1.0 - pow(distanceFromCenter, config.dampingScale)
    }
    
    private var barHeight: CGFloat {
        let range = maxHeight - minHeight
        var height = minHeight
        
        height += centerWeight * config.intensity * range * 0.6
        
        // Use continuous breathingPhase from TimelineView (convert to sine wave)
        let breathingWave = sin(breathingPhase * .pi * 2)
        let breathingContribution = (breathingWave * 0.5 + 0.5) * config.breathingAmplitude * range
        height += breathingContribution * centerWeight
        
        if config.audioReactivity > 0 {
            let audioContribution = audioLevel * config.audioReactivity * range * 0.8
            let randomizedAudio = audioContribution * (1.0 + randomOffset * config.randomization * 0.5)
            height += randomizedAudio * centerWeight
        }
        
        return max(minHeight, min(maxHeight, height))
    }
    
    private var barColor: Color {
        // Use cached color interpolation (no UIColor bridge creation)
        colorCache.lerp(t: config.colorBlend)
    }
}

// MARK: - ClassicBarsConfiguration

private struct ClassicBarsConfiguration: Equatable {
    let intensity: CGFloat
    let colorBlend: CGFloat
    let audioReactivity: CGFloat
    let breathingAmplitude: CGFloat
    let dampingScale: CGFloat
    let randomization: CGFloat
    
    // MARK: - Presets
    
    static let hidden = ClassicBarsConfiguration(
        intensity: 0, colorBlend: 0, audioReactivity: 0,
        breathingAmplitude: 0, dampingScale: 3.5, randomization: 0
    )
    
    static let idle = ClassicBarsConfiguration(
        intensity: 0.15, colorBlend: 0, audioReactivity: 0,
        breathingAmplitude: 0.02, dampingScale: 3.5, randomization: 0
    )
    
    static let speaking = ClassicBarsConfiguration(
        intensity: 0.45, colorBlend: 0, audioReactivity: 0.5,
        breathingAmplitude: 0.05, dampingScale: 3.5, randomization: 0.65
    )
    
    static let preparingToListen = ClassicBarsConfiguration(
        intensity: 0.25, colorBlend: 1.0, audioReactivity: 0,
        breathingAmplitude: 0.25, dampingScale: 3.5, randomization: 0
    )
    
    static let listening = ClassicBarsConfiguration(
        intensity: 0.45, colorBlend: 1.0, audioReactivity: 0.65,
        breathingAmplitude: 0.05, dampingScale: 3.5, randomization: 0.65
    )
    
    static let listeningSettling = ClassicBarsConfiguration(
        intensity: 0.25, colorBlend: 1.0, audioReactivity: 0,
        breathingAmplitude: 0.3, dampingScale: 3.5, randomization: 0
    )
    
    // MARK: - Transition States
    
    static let transitionScaledDown = ClassicBarsConfiguration(
        intensity: 0.05, colorBlend: 0, audioReactivity: 0,
        breathingAmplitude: 0, dampingScale: 3.5, randomization: 0
    )
    
    static let transitionColorMorphed = ClassicBarsConfiguration(
        intensity: 0.05, colorBlend: 1.0, audioReactivity: 0,
        breathingAmplitude: 0, dampingScale: 3.5, randomization: 0
    )
}

// MARK: - Previews

#Preview("Classic Bars - Idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        ClassicBarsWaveformView(
            state: .idle,
            tokens: DefaultDockDesignTokens(),
            breathingPhase: 0.5
        )
        .frame(height: 40)
    }
}

#Preview("Classic Bars - Playing") {
    ZStack {
        Color.black.ignoresSafeArea()
        ClassicBarsWaveformView(
            state: .playing(audioLevel: 0.7),
            tokens: DefaultDockDesignTokens(),
            breathingPhase: 0.5
        )
        .frame(height: 40)
    }
}

#Preview("Classic Bars - Listening") {
    ZStack {
        Color.black.ignoresSafeArea()
        ClassicBarsWaveformView(
            state: .listening(audioLevel: 0.6),
            tokens: DefaultDockDesignTokens(),
            breathingPhase: 0.5
        )
        .frame(height: 40)
    }
}

#Preview("Classic Bars - Animated") {
    ZStack {
        Color.black.ignoresSafeArea()
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((elapsed / 2.0).truncatingRemainder(dividingBy: 1.0))
            ClassicBarsWaveformView(
                state: .playing(audioLevel: 0.7),
                tokens: DefaultDockDesignTokens(),
                breathingPhase: phase
            )
        }
        .frame(height: 40)
    }
}
