//
//  AudioInputManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import Accelerate

// MARK: - AudioInputManager

/// Manages microphone input capture using AVAudioEngine.
///
/// Provides real-time audio buffers for speech recognition and
/// audio analysis (RMS, pitch detection).
///
/// ## Usage
/// ```swift
/// let manager = AudioInputManager()
/// try await manager.startCapture()
/// for await buffer in manager.audioBufferStream {
///     // Process buffer
/// }
/// ```
actor AudioInputManager {
    
    // MARK: - Properties
    
    /// The audio engine for input capture
    private let audioEngine: AVAudioEngine
    
    /// Input node for microphone
    private var inputNode: AVAudioInputNode {
        audioEngine.inputNode
    }
    
    /// Whether capture is currently active
    private(set) var isCapturing: Bool = false
    
    /// Audio format for input
    private var inputFormat: AVAudioFormat?
    
    /// Continuation for audio buffer stream
    private var bufferContinuation: AsyncStream<AudioAnalysisBuffer>.Continuation?
    
    /// Session manager reference
    private let sessionManager: AudioSessionManager
    
    /// Buffer size for analysis
    private let analysisBufferSize: AVAudioFrameCount
    
    // MARK: - Streams
    
    /// Stream of audio buffers for analysis
    private(set) lazy var audioBufferStream: AsyncStream<AudioAnalysisBuffer> = {
        AsyncStream { [weak self] continuation in
            Task {
                await self?.setBufferContinuation(continuation)
            }
        }
    }()
    
    // MARK: - Initialization
    
    /// Creates a new audio input manager
    /// - Parameter sessionManager: Audio session manager for permissions
    init(sessionManager: AudioSessionManager = .shared) {
        self.audioEngine = AVAudioEngine()
        self.sessionManager = sessionManager
        self.analysisBufferSize = Constants.Audio.bufferSize
    }
    
    // MARK: - Public Methods
    
    /// Starts capturing audio from the microphone
    /// - Throws: `AppError.microphoneAccessDenied` or `AppError.audioRecordingFailed`
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        // Check permission
        let hasPermission = await sessionManager.hasMicrophonePermission
        guard hasPermission else {
            throw AppError.microphoneAccessDenied
        }
        
        // Configure session for recording
        try await sessionManager.configureForPlaybackAndRecording()
        try await sessionManager.activate()
        
        // Get input format
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AppError.audioRecordingFailed(reason: "Invalid input format")
        }
        inputFormat = format
        
        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: analysisBufferSize,
            format: format
        ) { [weak self] buffer, time in
            Task {
                await self?.processBuffer(buffer, time: time)
            }
        }
        
        // Start engine
        do {
            try audioEngine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AppError.audioRecordingFailed(reason: error.localizedDescription)
        }
    }
    
    /// Stops capturing audio
    func stopCapture() {
        guard isCapturing else { return }
        
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        
        bufferContinuation?.finish()
    }
    
    /// Requests microphone permission
    /// - Returns: Whether permission was granted
    func requestPermission() async -> Bool {
        await sessionManager.requestMicrophonePermission()
    }
    
    /// Whether microphone permission is granted
    var hasPermission: Bool {
        get async {
            await sessionManager.hasMicrophonePermission
        }
    }
    
    // MARK: - Private Methods
    
    /// Sets the buffer continuation
    private func setBufferContinuation(_ continuation: AsyncStream<AudioAnalysisBuffer>.Continuation) {
        bufferContinuation = continuation
    }
    
    /// Processes an incoming audio buffer
    private func processBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Get samples from first channel
        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: frameLength
        ))
        
        // Calculate RMS (Root Mean Square) for volume level
        let rms = calculateRMS(samples)
        
        // Calculate peak amplitude
        let peak = samples.map { abs($0) }.max() ?? 0
        
        // Create analysis buffer
        let analysisBuffer = AudioAnalysisBuffer(
            samples: samples,
            sampleRate: buffer.format.sampleRate,
            frameCount: frameLength,
            timestamp: time.sampleTime,
            rmsLevel: rms,
            peakLevel: peak
        )
        
        // Yield to stream
        bufferContinuation?.yield(analysisBuffer)
    }
    
    /// Calculates RMS (Root Mean Square) of audio samples
    /// - Parameter samples: Audio samples
    /// - Returns: RMS value (0.0 - 1.0 typically)
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var sumOfSquares: Float = 0
        vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(samples.count))
        
        let meanSquare = sumOfSquares / Float(samples.count)
        return sqrt(meanSquare)
    }
}

// MARK: - AudioAnalysisBuffer

/// A processed audio buffer ready for analysis
struct AudioAnalysisBuffer: Sendable {
    
    /// Raw audio samples
    let samples: [Float]
    
    /// Sample rate in Hz
    let sampleRate: Double
    
    /// Number of frames in buffer
    let frameCount: Int
    
    /// Timestamp in samples
    let timestamp: Int64
    
    /// RMS level (volume indicator)
    let rmsLevel: Float
    
    /// Peak amplitude level
    let peakLevel: Float
    
    /// Duration of this buffer in seconds
    var duration: TimeInterval {
        Double(frameCount) / sampleRate
    }
    
    /// Decibel level from RMS
    var decibelLevel: Float {
        guard rmsLevel > 0 else { return -160 }
        return 20 * log10(rmsLevel)
    }
    
    /// Whether this buffer likely contains speech (above noise floor)
    var containsSpeech: Bool {
        decibelLevel > -40 // Typical speech threshold
    }
}

// MARK: - Audio Level Monitor

/// Monitors audio levels for UI visualization
actor AudioLevelMonitor {
    
    // MARK: - Properties
    
    /// Current smoothed RMS level
    private(set) var currentLevel: Float = 0
    
    /// Peak hold level
    private(set) var peakLevel: Float = 0
    
    /// Smoothing factor (0.0 - 1.0)
    private let smoothingFactor: Float = 0.3
    
    /// Peak decay rate per update
    private let peakDecay: Float = 0.95
    
    /// Continuation for level updates
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?
    
    /// Stream of audio level updates
    private(set) lazy var levelStream: AsyncStream<AudioLevel> = {
        AsyncStream { [weak self] continuation in
            Task {
                await self?.setLevelContinuation(continuation)
            }
        }
    }()
    
    // MARK: - Methods
    
    /// Updates with a new audio buffer
    func update(with buffer: AudioAnalysisBuffer) {
        // Smooth the RMS level
        currentLevel = (smoothingFactor * buffer.rmsLevel) + ((1 - smoothingFactor) * currentLevel)
        
        // Update peak with decay
        if buffer.peakLevel > peakLevel {
            peakLevel = buffer.peakLevel
        } else {
            peakLevel *= peakDecay
        }
        
        // Emit level update
        let level = AudioLevel(
            rms: currentLevel,
            peak: peakLevel,
            decibels: buffer.decibelLevel
        )
        levelContinuation?.yield(level)
    }
    
    /// Resets levels to zero
    func reset() {
        currentLevel = 0
        peakLevel = 0
    }
    
    /// Sets the level continuation
    private func setLevelContinuation(_ continuation: AsyncStream<AudioLevel>.Continuation) {
        levelContinuation = continuation
    }
}

// MARK: - AudioLevel

/// Current audio level for UI display
struct AudioLevel: Sendable {
    /// Smoothed RMS level (0.0 - 1.0)
    let rms: Float
    
    /// Peak level (0.0 - 1.0)
    let peak: Float
    
    /// Level in decibels
    let decibels: Float
    
    /// Normalized level for UI (0.0 - 1.0)
    var normalizedLevel: Float {
        // Map -60dB to 0dB range to 0.0 - 1.0
        let minDb: Float = -60
        let maxDb: Float = 0
        let clampedDb = max(minDb, min(maxDb, decibels))
        return (clampedDb - minDb) / (maxDb - minDb)
    }
}
