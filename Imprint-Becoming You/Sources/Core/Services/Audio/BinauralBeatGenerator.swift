//
//  BinauralBeatGenerator.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import Accelerate

// MARK: - BinauralBeatGenerator

/// Generates binaural beats using stereo sine wave oscillators.
///
/// Binaural beats are created by playing slightly different frequencies
/// in each ear, causing the brain to perceive a third "beat" frequency
/// equal to the difference between the two tones.
///
/// ## Presets
/// - **Focus (14 Hz)**: Beta waves for alertness and concentration
/// - **Relax (10 Hz)**: Alpha waves for calm awareness
/// - **Sleep (6 Hz)**: Theta waves for deep relaxation
///
/// ## Usage
/// ```swift
/// let generator = BinauralBeatGenerator()
/// try generator.attachTo(engine: audioEngine)
/// generator.start(preset: .focus)
/// ```
final class BinauralBeatGenerator: @unchecked Sendable {
    
    // MARK: - Shared State
    
    /// Thread-safe state holder for audio rendering
    private final class RenderState: @unchecked Sendable {
        var carrierFrequency: Float = Constants.Audio.binauralCarrierFrequency
        var beatFrequency: Float = 0
        var volume: Float = Constants.Audio.binauralVolume
        var leftPhase: Float = 0
        var rightPhase: Float = 0
        var sampleRate: Float = Float(Constants.Audio.sampleRate)
        var isPlaying: Bool = false
        let lock = NSLock()
        
        func withLock<T>(_ block: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return block()
        }
    }
    
    // MARK: - Properties
    
    /// Shared state for render callbacks
    private let state = RenderState()
    
    /// Left channel oscillator node
    private var leftOscillator: AVAudioSourceNode!
    
    /// Right channel oscillator node
    private var rightOscillator: AVAudioSourceNode!
    
    /// Mixer node for combining and controlling volume
    private let mixerNode: AVAudioMixerNode
    
    /// Whether the generator is currently playing
    var isPlaying: Bool {
        state.withLock { state.isPlaying }
    }
    
    /// Current preset being used
    private(set) var currentPreset: BinauralPreset?
    
    // MARK: - Initialization
    
    /// Creates a new binaural beat generator
    init() {
        mixerNode = AVAudioMixerNode()
        
        // Create oscillators with state capture (not self)
        let renderState = state
        
        leftOscillator = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            Self.generateSineWave(
                state: renderState,
                bufferList: audioBufferList,
                frameCount: frameCount,
                isLeftChannel: true
            )
        }
        
        rightOscillator = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            Self.generateSineWave(
                state: renderState,
                bufferList: audioBufferList,
                frameCount: frameCount,
                isLeftChannel: false
            )
        }
    }
    
    // MARK: - Engine Attachment
    
    /// Attaches the generator nodes to an audio engine
    /// - Parameter engine: The AVAudioEngine to attach to
    /// - Throws: `AppError.binauralGenerationFailed` if attachment fails
    func attachTo(engine: AVAudioEngine) throws {
        let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: Constants.Audio.sampleRate,
            channels: 1
        )!
        
        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: Constants.Audio.sampleRate,
            channels: 2
        )!
        
        // Attach nodes
        engine.attach(leftOscillator)
        engine.attach(rightOscillator)
        engine.attach(mixerNode)
        
        // Connect left oscillator to mixer (pan left)
        engine.connect(leftOscillator, to: mixerNode, format: monoFormat)
        
        // Connect right oscillator to mixer (pan right)
        engine.connect(rightOscillator, to: mixerNode, format: monoFormat)
        
        // Connect mixer to main output
        engine.connect(mixerNode, to: engine.mainMixerNode, format: stereoFormat)
        
        // Set panning for stereo separation
        // Note: We'll handle stereo in the render callback instead
        
        // Set initial volume
        mixerNode.outputVolume = 0
    }
    
    /// Detaches the generator nodes from an audio engine
    /// - Parameter engine: The AVAudioEngine to detach from
    func detachFrom(engine: AVAudioEngine) {
        stop()
        engine.detach(leftOscillator)
        engine.detach(rightOscillator)
        engine.detach(mixerNode)
    }
    
    // MARK: - Playback Control
    
    /// Starts generating binaural beats with the specified preset
    /// - Parameter preset: The binaural preset to use
    func start(preset: BinauralPreset) {
        guard preset != .off else {
            stop()
            return
        }
        
        state.withLock {
            currentPreset = preset
            state.beatFrequency = preset.frequencyDifference
            state.volume = state.volume // ensure current volume
            state.isPlaying = true
        }
        
        // Fade in
        mixerNode.outputVolume = state.volume
    }
    
    /// Stops generating binaural beats
    func stop() {
        mixerNode.outputVolume = 0
        
        state.withLock {
            state.isPlaying = false
            currentPreset = nil
            state.beatFrequency = 0
            state.leftPhase = 0
            state.rightPhase = 0
        }
    }
    
    /// Changes the preset without stopping playback
    /// - Parameter preset: The new preset to use
    func changePreset(_ preset: BinauralPreset) {
        if preset == .off {
            stop()
            return
        }
        
        state.withLock {
            currentPreset = preset
            state.beatFrequency = preset.frequencyDifference
            
            if !state.isPlaying {
                state.isPlaying = true
            }
        }
        
        mixerNode.outputVolume = state.volume
    }
    
    /// Sets the playback volume
    /// - Parameter newVolume: Volume level (0.0 - 1.0)
    func setVolume(_ newVolume: Float) {
        let isCurrentlyPlaying = state.withLock {
            state.volume = max(0, min(1, newVolume))
            return state.isPlaying
        }
        
        if isCurrentlyPlaying {
            mixerNode.outputVolume = state.volume
        }
    }
    
    /// Sets the carrier (base) frequency
    /// - Parameter frequency: Carrier frequency in Hz (typically 100-500 Hz)
    func setCarrierFrequency(_ frequency: Float) {
        state.withLock {
            state.carrierFrequency = max(20, min(500, frequency))
        }
    }
    
    // MARK: - Private Methods
    
    /// Generates a sine wave for the audio buffer (static to avoid self capture)
    private static func generateSineWave(
        state: RenderState,
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount,
        isLeftChannel: Bool
    ) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        
        guard let buffer = ablPointer.first,
              let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        
        // Get current state
        let (frequency, currentVolume, sampleRate) = state.withLock {
            let freq: Float
            if isLeftChannel {
                freq = state.carrierFrequency
            } else {
                freq = state.carrierFrequency + state.beatFrequency
            }
            let vol = state.isPlaying ? state.volume : 0
            return (freq, vol, state.sampleRate)
        }
        
        let phaseIncrement = (2.0 * Float.pi * frequency) / sampleRate
        
        // Generate samples
        state.lock.lock()
        for frame in 0..<Int(frameCount) {
            if isLeftChannel {
                data[frame] = sin(state.leftPhase) * currentVolume
                state.leftPhase += phaseIncrement
                
                // Keep phase in reasonable range to prevent floating point issues
                if state.leftPhase > 2.0 * Float.pi {
                    state.leftPhase -= 2.0 * Float.pi
                }
            } else {
                data[frame] = sin(state.rightPhase) * currentVolume
                state.rightPhase += phaseIncrement
                
                if state.rightPhase > 2.0 * Float.pi {
                    state.rightPhase -= 2.0 * Float.pi
                }
            }
        }
        state.lock.unlock()
        
        return noErr
    }
}

// MARK: - Stereo Binaural Generator (Alternative Implementation)

/// Alternative implementation that generates true stereo binaural beats in a single node
final class StereoBinauralGenerator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Stereo source node
    private var sourceNode: AVAudioSourceNode?
    
    /// Current carrier frequency
    private var carrierFrequency: Float = Constants.Audio.binauralCarrierFrequency
    
    /// Current beat frequency
    private var beatFrequency: Float = 0
    
    /// Current volume
    private var volume: Float = Constants.Audio.binauralVolume
    
    /// Phase for left channel
    private var leftPhase: Float = 0
    
    /// Phase for right channel
    private var rightPhase: Float = 0
    
    /// Sample rate
    private var sampleRate: Float = Float(Constants.Audio.sampleRate)
    
    /// Whether currently playing
    private(set) var isPlaying: Bool = false
    
    /// Current preset
    private(set) var currentPreset: BinauralPreset?
    
    /// Thread safety lock
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Engine Attachment
    
    /// Creates and attaches the stereo source node to an engine
    /// - Parameter engine: The audio engine
    func attachTo(engine: AVAudioEngine) throws {
        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: Constants.Audio.sampleRate,
            channels: 2
        )!
        
        sourceNode = AVAudioSourceNode(format: stereoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            return self.renderStereoBuffer(
                bufferList: audioBufferList,
                frameCount: frameCount
            )
        }
        
        guard let sourceNode = sourceNode else {
            throw AppError.binauralGenerationFailed(reason: "Failed to create source node")
        }
        
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: stereoFormat)
    }
    
    /// Detaches from the engine
    func detachFrom(engine: AVAudioEngine) {
        stop()
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
    }
    
    // MARK: - Playback Control
    
    /// Starts playback with preset
    func start(preset: BinauralPreset) {
        guard preset != .off else {
            stop()
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        currentPreset = preset
        beatFrequency = preset.frequencyDifference
        isPlaying = true
    }
    
    /// Stops playback
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        isPlaying = false
        currentPreset = nil
        beatFrequency = 0
        leftPhase = 0
        rightPhase = 0
    }
    
    /// Changes preset
    func changePreset(_ preset: BinauralPreset) {
        if preset == .off {
            stop()
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        currentPreset = preset
        beatFrequency = preset.frequencyDifference
        isPlaying = true
    }
    
    /// Sets volume
    func setVolume(_ newVolume: Float) {
        lock.lock()
        defer { lock.unlock() }
        volume = max(0, min(1, newVolume))
    }
    
    // MARK: - Private Methods
    
    /// Renders stereo binaural beat buffer
    private func renderStereoBuffer(
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount
    ) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        
        lock.lock()
        let leftFreq = carrierFrequency
        let rightFreq = carrierFrequency + beatFrequency
        let currentVolume = isPlaying ? volume : 0
        lock.unlock()
        
        let leftIncrement = (2.0 * Float.pi * leftFreq) / sampleRate
        let rightIncrement = (2.0 * Float.pi * rightFreq) / sampleRate
        
        // Stereo interleaved format: L R L R L R ...
        guard let buffer = ablPointer.first,
              let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        
        for frame in 0..<Int(frameCount) {
            // Left channel (even indices in interleaved)
            data[frame * 2] = sin(leftPhase) * currentVolume
            
            // Right channel (odd indices in interleaved)
            data[frame * 2 + 1] = sin(rightPhase) * currentVolume
            
            leftPhase += leftIncrement
            rightPhase += rightIncrement
            
            // Keep phases in range
            if leftPhase > 2.0 * Float.pi {
                leftPhase -= 2.0 * Float.pi
            }
            if rightPhase > 2.0 * Float.pi {
                rightPhase -= 2.0 * Float.pi
            }
        }
        
        return noErr
    }
}
