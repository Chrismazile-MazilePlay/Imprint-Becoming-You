//
//  AudioInputManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import Accelerate
import os.log

// MARK: - Logger

private let audioInputLog = Logger(subsystem: "com.imprint.audio", category: "AudioInputManager")

// MARK: - AudioInputManager

/// Manages microphone input capture using AVAudioEngine.
///
/// Provides real-time audio buffers for speech recognition and
/// audio analysis (RMS, pitch detection).
///
/// ## SOLID Compliance
/// - **SRP**: Only handles audio input capture
/// - **OCP**: Works with any `AudioSessionControllerProtocol` implementation
/// - **DIP**: Depends on protocols, not concrete implementations
///
/// ## Usage
/// ```swift
/// let manager = AudioInputManager(sessionController: AudioSessionController())
/// try await manager.startCapture()
/// for await buffer in manager.audioBufferStream {
///     // Process buffer
/// }
/// ```
@MainActor
final class AudioInputManager {

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

    /// Session controller for audio session management
    private let sessionController: any AudioSessionControllerProtocol

    /// Buffer size for analysis
    private let analysisBufferSize: AVAudioFrameCount
    
    // MARK: - Streams
    
    /// Stream of audio buffers for analysis
    private(set) lazy var audioBufferStream: AsyncStream<AudioAnalysisBuffer> = {
        AsyncStream { [weak self] continuation in
            Task { @MainActor in
                self?.bufferContinuation = continuation
            }
        }
    }()
    
    // MARK: - Initialization
    
    /// Creates a new audio input manager
    /// - Parameter sessionController: Controller for audio session operations (defaults to a new `AudioSessionController` instance)
    init(sessionController: (any AudioSessionControllerProtocol)? = nil) {
        self.audioEngine = AVAudioEngine()
        self.sessionController = sessionController ?? AudioSessionController()
        self.analysisBufferSize = Constants.Audio.bufferSize

        audioInputLog.info("✅ AudioInputManager initialized")
    }
    
    // MARK: - Public Methods
    
    /// Starts capturing audio from the microphone
    /// - Throws: `AppError.microphoneAccessDenied` or `AppError.audioRecordingFailed`
    func startCapture() async throws {
        guard !isCapturing else {
            audioInputLog.debug("Already capturing, ignoring startCapture")
            return
        }
        
        audioInputLog.info("🎤 Starting audio capture...")
        
        // Check permission
        guard sessionController.hasMicrophonePermission else {
            audioInputLog.error("❌ Microphone permission denied")
            throw AppError.microphoneAccessDenied
        }

        // Configure session for recording via session controller
        do {
            try await sessionController.transition(
                to: .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers],
                engineAction: .none
            )
        } catch {
            audioInputLog.error("❌ Failed to configure session: \(error.localizedDescription)")
            throw AppError.audioRecordingFailed(reason: "Session configuration failed: \(error.localizedDescription)")
        }
        
        // Get input format
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            audioInputLog.error("❌ Invalid input format (sample rate: \(format.sampleRate))")
            throw AppError.audioRecordingFailed(reason: "Invalid input format")
        }
        inputFormat = format
        
        audioInputLog.info("📊 Input format: \(format.sampleRate) Hz, \(format.channelCount) ch")
        
        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: analysisBufferSize,
            format: format
        ) { [weak self] buffer, time in
            Task { @MainActor in
                self?.processBuffer(buffer, time: time)
            }
        }
        
        // Start engine
        do {
            try audioEngine.start()
            isCapturing = true
            audioInputLog.info("✅ Audio capture started")
        } catch {
            inputNode.removeTap(onBus: 0)
            audioInputLog.error("❌ Failed to start engine: \(error.localizedDescription)")
            throw AppError.audioRecordingFailed(reason: error.localizedDescription)
        }
    }
    
    /// Stops capturing audio
    func stopCapture() {
        guard isCapturing else { return }
        
        audioInputLog.info("🛑 Stopping audio capture")
        
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        
        bufferContinuation?.finish()
    }
    
    /// Requests microphone permission
    /// - Returns: Whether permission was granted
    func requestPermission() async -> Bool {
        audioInputLog.info("🎤 Requesting microphone permission")
        return await sessionController.requestMicrophonePermission()
    }

    /// Whether microphone permission is granted
    var hasPermission: Bool {
        sessionController.hasMicrophonePermission
    }
    
    // MARK: - Private Methods
    
    /// Processes an incoming audio buffer
    private func processBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        
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
        
        // Log periodically (not every buffer to avoid spam)
        if Int.random(in: 0..<50) == 0 {
            audioInputLog.debug("📊 Buffer: \(frameLength) frames, RMS: \(String(format: "%.4f", rms)), Speech: \(analysisBuffer.containsSpeech)")
        }
        
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
@MainActor
final class AudioLevelMonitor {
    
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
            Task { @MainActor in
                self?.levelContinuation = continuation
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
