//
//  KokoroTTSEngine.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation
import CoreML
import iOS_TTS

// MARK: - Kokoro TTS Engine

/// Actor wrapping the iOS_TTS TTSPipeline for thread-safe neural TTS synthesis.
///
/// Manages CoreML model lifecycle and provides high-quality on-device
/// text-to-speech using the Kokoro neural TTS system.
///
/// ## Resource Requirements
/// The following resources must be present in `Resources/Kokoro/`:
/// - `Models/` - CoreML model files (.mlmodelc)
/// - `G2P/` - Grapheme-to-phoneme vocabulary files
/// - `POS/` - Part-of-speech tagger model
/// - `Espeak/espeak-ng-data/` - Espeak phoneme data
///
/// ## Lifecycle
/// 1. Call `warmUp()` at app launch to load CoreML models
/// 2. Use `synthesize(text:voiceStyle:)` or `synthesizeToData(text:voiceStyle:)` for TTS
/// 3. Engine handles model caching internally
///
/// ## Performance
/// - First synthesis (cold): 1-2 seconds
/// - First synthesis (warm): 200-500ms
/// - Subsequent synthesis: 50-200ms depending on text length
///
/// ## Usage
/// ```swift
/// let engine = KokoroTTSEngine()
/// try await engine.warmUp()
///
/// let samples = try await engine.synthesize(
///     text: "I am confident",
///     voiceStyle: .afHeart
/// )
/// ```
actor KokoroTTSEngine {
    
    // MARK: - Types
    
    /// Engine initialization state
    enum State: Sendable {
        case uninitialized
        case initializing
        case ready
        case failed(Error)
    }
    
    /// Errors specific to Kokoro TTS
    enum KokoroError: Error, LocalizedError {
        case notInitialized
        case initializationFailed(String)
        case synthesisFailedError(String)
        case resourceNotFound(String)
        case invalidText
        
        var errorDescription: String? {
            switch self {
            case .notInitialized:
                return "Kokoro TTS engine not initialized"
            case .initializationFailed(let reason):
                return "Failed to initialize Kokoro TTS: \(reason)"
            case .synthesisFailedError(let reason):
                return "Speech synthesis failed: \(reason)"
            case .resourceNotFound(let resource):
                return "Required resource not found: \(resource)"
            case .invalidText:
                return "Invalid or empty text provided"
            }
        }
    }
    
    // MARK: - Properties
    
    /// Current engine state
    private(set) var state: State = .uninitialized
    
    /// The underlying TTS pipeline
    private var pipeline: TTSPipeline?
    
    /// Sample rate of generated audio (24kHz)
    let sampleRate: Int = 24000
    
    /// Current language (English US by default)
    private let language: Language = .englishUS
    
    // MARK: - Initialization
    
    /// Warms up the engine by loading CoreML models.
    ///
    /// Call this at app launch to minimize first-synthesis latency.
    /// Safe to call multiple times - subsequent calls are no-ops if already ready.
    ///
    /// - Throws: `KokoroError.initializationFailed` if model loading fails
    func warmUp() async throws {
        // Skip if already ready or initializing
        switch state {
        case .ready:
            return
        case .initializing:
            // Wait for existing initialization
            while case .initializing = state {
                try await Task.sleep(for: .milliseconds(50))
            }
            if case .failed(let error) = state {
                throw error
            }
            return
        case .uninitialized, .failed:
            break
        }
        
        state = .initializing
        
        do {
            // Get resource URLs
            let resourceURLs = try getResourceURLs()
            
            // Configure ML compute units for best performance
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            
            // Initialize pipeline
            pipeline = try TTSPipeline(
                modelPath: resourceURLs.modelsURL,
                vocabURL: resourceURLs.vocabURL,
                postaggerModelURL: resourceURLs.posURL,
                language: language,
                espeakDataPath: resourceURLs.espeakPath,
                configuration: configuration
            )
            
            state = .ready
            
            #if DEBUG
            print("✅ KokoroTTSEngine: Pipeline initialized successfully")
            #endif
            
        } catch {
            state = .failed(error)
            
            #if DEBUG
            print("❌ KokoroTTSEngine: Initialization failed - \(error)")
            #endif
            
            throw KokoroError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Checks if the engine is ready for synthesis
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }
    
    // MARK: - Synthesis
    
    /// Synthesizes speech and returns raw audio samples.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize (must not be empty)
    ///   - voiceStyle: iOS_TTS VoiceStyle to use
    ///   - speed: Speech speed multiplier (0.5-2.0, default 1.0)
    /// - Returns: Array of Float32 audio samples at 24kHz
    /// - Throws: `KokoroError` if synthesis fails
    func synthesize(
        text: String,
        voiceStyle: VoiceStyle,
        speed: Float = 1.0
    ) async throws -> [Float] {
        guard case .ready = state, let pipeline = pipeline else {
            throw KokoroError.notInitialized
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw KokoroError.invalidText
        }
        
        let options = GenerationOptions(
            style: voiceStyle,
            speed: speed
        )
        
        do {
            let samples = try await pipeline.generate(text: trimmedText, options: options)
            return samples
        } catch {
            throw KokoroError.synthesisFailedError(error.localizedDescription)
        }
    }
    
    /// Synthesizes speech and returns WAV audio data.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceStyle: iOS_TTS VoiceStyle to use
    ///   - speed: Speech speed multiplier (0.5-2.0, default 1.0)
    /// - Returns: WAV format audio data
    /// - Throws: `KokoroError` if synthesis fails
    func synthesizeToData(
        text: String,
        voiceStyle: VoiceStyle,
        speed: Float = 1.0
    ) async throws -> Data {
        let samples = try await synthesize(text: text, voiceStyle: voiceStyle, speed: speed)
        return samplesToWAV(samples)
    }
    
    // MARK: - Resource Management
    
    /// Resource URLs container
    private struct ResourceURLs {
        let modelsURL: URL
        let vocabURL: URL
        let posURL: URL
        let espeakPath: String
    }
    
    /// Gets URLs for all required Kokoro resources from the app bundle.
    private func getResourceURLs() throws -> ResourceURLs {
        let bundle = Bundle.main
        
        // Models directory
        guard let modelsURL = bundle.url(forResource: "Models", withExtension: nil, subdirectory: "Kokoro") else {
            throw KokoroError.resourceNotFound("Kokoro/Models")
        }
        
        // G2P vocab directory
        guard let vocabURL = bundle.url(forResource: "G2P", withExtension: nil, subdirectory: "Kokoro") else {
            throw KokoroError.resourceNotFound("Kokoro/G2P")
        }
        
        // POS model directory
        guard let posURL = bundle.url(forResource: "POS", withExtension: nil, subdirectory: "Kokoro") else {
            throw KokoroError.resourceNotFound("Kokoro/POS")
        }
        
        // Espeak data directory (needs path string, not URL)
        guard let espeakURL = bundle.url(forResource: "espeak-ng-data", withExtension: nil, subdirectory: "Kokoro/Espeak") else {
            throw KokoroError.resourceNotFound("Kokoro/Espeak/espeak-ng-data")
        }
        
        return ResourceURLs(
            modelsURL: modelsURL,
            vocabURL: vocabURL,
            posURL: posURL,
            espeakPath: espeakURL.path
        )
    }
    
    // MARK: - Audio Conversion
    
    /// Converts Float32 samples to WAV format data.
    private func samplesToWAV(_ samples: [Float]) -> Data {
        var data = Data()
        
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(numSamples * Int(blockAlign))
        let fileSize = 36 + dataSize
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Convert Float32 samples to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }
        
        return data
    }
}
