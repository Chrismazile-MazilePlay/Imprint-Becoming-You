//
//  LayeredWavesWaveform.swift
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
/// - Eliminates 180 UIColor allocations/second (60fps × 3 layers)
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

// MARK: - LayeredWavesWaveformStyle

/// Layered waves waveform style using overlapping sine curves.
///
/// This is the default waveform visualization, featuring multiple
/// overlapping sine curves that create depth and organic movement.
public struct LayeredWavesWaveformStyle: DockWaveformStyle {
    
    public init() {}
    
    public func makeBody(state: DockCenterContentState, tokens: DockDesignTokens) -> some View {
        // Note: When used through the style protocol, we need internal TimelineView
        // When used directly from DockCenterContentView, breathingPhase is provided
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((elapsed / 2.0).truncatingRemainder(dividingBy: 1.0))
            LayeredWavesWaveformView(state: state, tokens: tokens, breathingPhase: phase)
        }
    }
}

// MARK: - LayeredWavesWaveformView

/// A layered wave visualization using pure SwiftUI animations.
///
/// Renders multiple overlapping sine curves that respond to different states
/// (playing, listening, waiting, etc.) with smooth transitions.
///
/// ## Animation Architecture
///
/// The `breathingPhase` is provided by the parent container (`DockCenterContentView`)
/// which wraps all waveforms in a single `TimelineView`. This ensures:
/// - All waveforms animate in perfect sync
/// - No duplicate TimelineView instances
/// - Consistent timing across different waveform styles
///
/// ## Performance Optimizations
///
/// - **Single Animation Loop**: One `breathingPhase` drives all waves
/// - **Animatable Shape**: Uses `animatableData` for GPU-accelerated path interpolation
/// - **Efficient Path Calculation**: Optimized step count based on view width
/// - **Pre-computed Colors**: Uses `ColorCache` to avoid UIColor bridge creation per frame
struct LayeredWavesWaveformView: View {
    
    // MARK: - Properties
    
    let state: DockCenterContentState
    let tokens: DockDesignTokens
    
    /// Continuous breathing phase (0.0-1.0) provided by parent TimelineView.
    let breathingPhase: CGFloat
    
    // MARK: - Pre-computed Colors
    
    /// Cached color values for efficient interpolation.
    private let colorCache: ColorCache
    
    // MARK: - Configuration Constants
    
    private let layerCount: Int = 3
    private let baseFrequency: CGFloat = 1.5
    private let frequencyStep: CGFloat = 0.5
    private let lineWidth: CGFloat = 2.0
    
    // MARK: - Transition Timing
    
    private let scaleDownDuration: TimeInterval = 0.2
    private let colorMorphDuration: TimeInterval = 0.15
    private let scaleUpDuration: TimeInterval = 0.2
    
    // MARK: - Animation State
    
    @State private var config: LayeredWavesConfiguration = .idle
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
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<layerCount, id: \.self) { index in
                    WaveLayer(
                        index: index,
                        layerCount: layerCount,
                        width: geometry.size.width,
                        height: geometry.size.height,
                        config: config,
                        audioLevel: isInChoreographedTransition ? 0 : (state.audioLevel ?? 0),
                        breathingPhase: breathingPhase,
                        baseFrequency: baseFrequency,
                        frequencyStep: frequencyStep,
                        lineWidth: lineWidth,
                        colorCache: colorCache
                    )
                }
            }
        }
        .onAppear {
            config = configuration(for: state)
            previousState = state
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
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
        
        // Phase 1: Scale down (still orange)
        withAnimation(.easeIn(duration: scaleDownDuration)) {
            config = .transitionScaledDown
        }
        
        // Phase 2: Color morph (keep transition flag true to suppress audio level jumps)
        DispatchQueue.main.asyncAfter(deadline: .now() + scaleDownDuration) {
            withAnimation(.easeInOut(duration: self.colorMorphDuration)) {
                self.config = .preparingToListen
            }
        }
        
        // Release transition flag AFTER both animations complete
        // This prevents visual hesitation from audioLevel jumping mid-transition
        let totalDuration = scaleDownDuration + colorMorphDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            self.isInChoreographedTransition = false
        }
    }
    
    private func performPreparingToListeningTransition() {
        withAnimation(.easeOut(duration: scaleUpDuration)) {
            config = .listening
        }
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
        }
    }
    
    // MARK: - Standard Transitions
    
    private func transitionToState(_ newState: DockCenterContentState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            config = configuration(for: newState)
        }
    }
    
    // MARK: - Configuration Mapping
    
    private func configuration(for state: DockCenterContentState) -> LayeredWavesConfiguration {
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
            return .settling
        case .showingScore:
            return .hidden
        }
    }
}

// MARK: - WaveLayer

private struct WaveLayer: View {
    let index: Int
    let layerCount: Int
    let width: CGFloat
    let height: CGFloat
    let config: LayeredWavesConfiguration
    let audioLevel: CGFloat
    let breathingPhase: CGFloat
    let baseFrequency: CGFloat
    let frequencyStep: CGFloat
    let lineWidth: CGFloat
    let colorCache: ColorCache
    
    var body: some View {
        WaveShape(
            width: width,
            height: height,
            phase: effectivePhase,
            amplitude: effectiveAmplitude,
            frequency: layerFrequency
        )
        .stroke(
            layerColor,
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        // Note: Implicit .animation() modifiers removed to prevent conflicts
        // with choreographed withAnimation blocks in state transitions.
        // Amplitude changes are smoothed by WaveShape.animatableData instead.
    }
    
    // MARK: - Layer Properties
    
    private var layerFrequency: CGFloat {
        baseFrequency + CGFloat(index) * frequencyStep
    }
    
    private var layerPhaseOffset: CGFloat {
        CGFloat(index) / CGFloat(layerCount) * 0.33
    }
    
    private var layerOpacity: CGFloat {
        let baseOpacity: CGFloat = 0.25
        let opacityStep: CGFloat = 0.25
        return (baseOpacity + CGFloat(index) * opacityStep) * config.intensity
    }
    
    private var effectivePhase: CGFloat {
        breathingPhase + layerPhaseOffset
    }
    
    private var effectiveAmplitude: CGFloat {
        var amplitude = config.intensity * 0.7
        
        let breathingWave = sin(breathingPhase * .pi * 2)
        amplitude += breathingWave * config.breathingAmplitude
        
        if config.audioReactivity > 0 {
            let audioBoost = audioLevel * config.audioReactivity * 0.35
            amplitude += audioBoost
        }
        
        let layerScale = 0.6 + (CGFloat(index) / CGFloat(layerCount)) * 0.4
        amplitude *= layerScale
        
        return max(0, min(1, amplitude))
    }
    
    private var layerColor: Color {
        // Use cached color interpolation (no UIColor bridge creation)
        let baseColor = colorCache.lerp(t: config.colorBlend)
        return baseColor.opacity(layerOpacity)
    }
}

// MARK: - WaveShape

private struct WaveShape: Shape {
    let width: CGFloat
    let height: CGFloat
    let phase: CGFloat
    var amplitude: CGFloat
    let frequency: CGFloat
    
    /// Only amplitude is animatable - phase is driven by TimelineView
    /// and should never be interpolated by SwiftUI animations.
    /// Animating phase causes horizontal "snap back" during state transitions.
    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = height / 2
        let maxWaveAmplitude = height * 0.4
        
        let stepCount = max(Int(width / 2), 50)
        
        for i in 0...stepCount {
            let x = CGFloat(i) / CGFloat(stepCount) * width
            let normalizedX = x / width
            
            let angle = normalizedX * .pi * 2 * frequency + phase * .pi * 2
            let y = midY + sin(angle) * maxWaveAmplitude * amplitude
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

// MARK: - LayeredWavesConfiguration

private struct LayeredWavesConfiguration: Equatable {
    let intensity: CGFloat
    let colorBlend: CGFloat
    let audioReactivity: CGFloat
    let breathingAmplitude: CGFloat
    
    // MARK: - Presets
    
    static let hidden = LayeredWavesConfiguration(
        intensity: 0,
        colorBlend: 0,
        audioReactivity: 0,
        breathingAmplitude: 0
    )
    
    static let idle = LayeredWavesConfiguration(
        intensity: 0.2,
        colorBlend: 0,
        audioReactivity: 0,
        breathingAmplitude: 0.03
    )
    
    static let speaking = LayeredWavesConfiguration(
        intensity: 0.70,
        colorBlend: 0,
        audioReactivity: 0.5,
        breathingAmplitude: 0.18
    )
    
    static let preparingToListen = LayeredWavesConfiguration(
        intensity: 0.35,
        colorBlend: 1.0,
        audioReactivity: 0,
        breathingAmplitude: 0.25
    )
    
    static let listening = LayeredWavesConfiguration(
        intensity: 0.55,
        colorBlend: 1.0,
        audioReactivity: 0.7,
        breathingAmplitude: 0.08
    )
    
    static let settling = LayeredWavesConfiguration(
        intensity: 0.25,
        colorBlend: 0.5,
        audioReactivity: 0,
        breathingAmplitude: 0.15
    )
    
    // MARK: - Transition States
    
    static let transitionScaledDown = LayeredWavesConfiguration(
        intensity: 0.05,
        colorBlend: 0,
        audioReactivity: 0,
        breathingAmplitude: 0.20
    )
    
    static let transitionColorMorphed = LayeredWavesConfiguration(
        intensity: 0.05,
        colorBlend: 1.0,
        audioReactivity: 0,
        breathingAmplitude: 0.20
    )
}

// MARK: - Previews

#Preview("Layered Waves - Idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        LayeredWavesWaveformView(
            state: .idle,
            tokens: DefaultDockDesignTokens(),
            breathingPhase: 0.5
        )
        .frame(height: 60)
        .padding(.horizontal, 20)
    }
}

#Preview("Layered Waves - Playing") {
    ZStack {
        Color.black.ignoresSafeArea()
        LayeredWavesWaveformView(
            state: .playing(audioLevel: 0.7),
            tokens: DefaultDockDesignTokens(),
            breathingPhase: 0.5
        )
        .frame(height: 60)
        .padding(.horizontal, 20)
    }
}

#Preview("Layered Waves - Listening") {
    ZStack {
        Color.black.ignoresSafeArea()
        LayeredWavesWaveformView(
            state: .listening(audioLevel: 0.6),
            tokens: DefaultDockDesignTokens(),
            breathingPhase: 0.5
        )
        .frame(height: 60)
        .padding(.horizontal, 20)
    }
}

#Preview("Layered Waves - Animated") {
    ZStack {
        Color.black.ignoresSafeArea()
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((elapsed / 2.0).truncatingRemainder(dividingBy: 1.0))
            LayeredWavesWaveformView(
                state: .playing(audioLevel: 0.7),
                tokens: DefaultDockDesignTokens(),
                breathingPhase: phase
            )
        }
        .frame(height: 60)
        .padding(.horizontal, 20)
    }
}
