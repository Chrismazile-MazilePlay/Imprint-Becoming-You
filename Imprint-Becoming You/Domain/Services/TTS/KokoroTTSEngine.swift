//
//  KokoroTTSEngine.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation
import AVFoundation
import iOS_TTS
import CoreML

// MARK: - Kokoro TTS Engine

/// On-device neural text-to-speech engine using Kokoro.
/// Supports both American English (en-US) and British English (en-GB) voices.
///
/// ## Memory Management
/// The ML pipelines consume significant memory (~500MB-1GB total).
/// Use `releaseForBackground()` when the app enters background to free memory,
/// and `warmUp()` again when returning to foreground.
///
/// ```swift
/// // When entering background
/// await kokoroEngine.releaseForBackground()
///
/// // When returning to foreground
/// try await kokoroEngine.warmUp()
/// ```
actor KokoroTTSEngine {
    
    // MARK: - Types
    
    /// Supported language variants
    enum LanguageVariant {
        case americanEnglish
        case britishEnglish
        
        var displayName: String {
            switch self {
            case .americanEnglish: return "en-US"
            case .britishEnglish: return "en-GB"
            }
        }
    }
    
    // MARK: - Properties
    
    private var usPipeline: TTSPipeline?
    private var gbPipeline: TTSPipeline?
    private var isWarmedUp: Bool = false
    
    /// Cached paths for re-initialization after release
    private var cachedKokoroPath: String?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Warms up both US and GB English pipelines.
    /// This runs asynchronously and does not block the UI.
    func warmUp() async throws {
        guard !isWarmedUp else { return }
        
        #if DEBUG
        print("KokoroTTSEngine: Starting warm-up...")
        #endif
        
        guard let kokoroPath = findKokoroFolder() else {
            throw AppError.ttsError("Kokoro folder not found in bundle")
        }
        
        // Cache path for potential re-initialization
        cachedKokoroPath = kokoroPath
        
        #if DEBUG
        print("Found Kokoro at: \(kokoroPath)")
        #endif
        
        // Build paths per library API
        let modelsPath = (kokoroPath as NSString).appendingPathComponent("Models")
        let g2pPath = (kokoroPath as NSString).appendingPathComponent("G2P")
        let posModelPath = (kokoroPath as NSString).appendingPathComponent("POS")
        let espeakPath = (kokoroPath as NSString).appendingPathComponent("Espeak/espeak-ng-data")
        
        #if DEBUG
        print("Models folder: \(FileManager.default.fileExists(atPath: modelsPath))")
        print("G2P folder: \(FileManager.default.fileExists(atPath: g2pPath))")
        print("POS model: \(FileManager.default.fileExists(atPath: posModelPath))")
        print("eSpeak folder: \(FileManager.default.fileExists(atPath: espeakPath))")
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsPath) {
            print("Models contents: \(contents)")
        }
        #endif
        
        guard FileManager.default.fileExists(atPath: modelsPath) else {
            throw AppError.ttsError("Models folder not found")
        }
        guard FileManager.default.fileExists(atPath: g2pPath) else {
            throw AppError.ttsError("G2P folder not found")
        }
        guard FileManager.default.fileExists(atPath: posModelPath) else {
            throw AppError.ttsError("POS model not found")
        }
        guard FileManager.default.fileExists(atPath: espeakPath) else {
            throw AppError.ttsError("eSpeak data not found")
        }
        
        // Configure for GPU/Neural Engine
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        let modelsURL = URL(fileURLWithPath: modelsPath)
        
        // vocabURL: TTSPipeline/Lexicon expects the G2P DIRECTORY
        // It internally looks for en_us_gold.json, en_us_silver.json, en_us_vocab.json, etc.
        let vocabURL = URL(fileURLWithPath: g2pPath)
        
        // posURL: SwiftPOSTagger expects the POS DIRECTORY
        // It internally appends "Model.mlmodelc" to find the CoreML model
        let posURL = URL(fileURLWithPath: posModelPath)
        
        // Initialize US English pipeline
        #if DEBUG
        print("KokoroTTSEngine: Initializing US English pipeline...")
        print("  vocabURL: \(vocabURL.path)")
        print("  posURL: \(posURL.path)")
        #endif
        
        do {
            usPipeline = try TTSPipeline(
                modelPath: modelsURL,
                vocabURL: vocabURL,
                postaggerModelURL: posURL,
                language: .englishUS,
                espeakDataPath: espeakPath,
                configuration: config
            )
            
            #if DEBUG
            print("US English pipeline initialized")
            #endif
        } catch {
            #if DEBUG
            print("Failed to initialize US pipeline: \(error)")
            #endif
            throw error
        }
        
        // Initialize GB English pipeline
        #if DEBUG
        print("KokoroTTSEngine: Initializing British English pipeline...")
        #endif
        
        do {
            gbPipeline = try TTSPipeline(
                modelPath: modelsURL,
                vocabURL: vocabURL,
                postaggerModelURL: posURL,
                language: .englishGB,
                espeakDataPath: espeakPath,
                configuration: config
            )
            
            #if DEBUG
            print("GB English pipeline initialized")
            #endif
        } catch {
            #if DEBUG
            print("Failed to initialize GB pipeline: \(error)")
            #endif
            throw error
        }
        
        isWarmedUp = true
        
        #if DEBUG
        print("KokoroTTSEngine: Warm-up complete")
        #endif
    }
    
    /// Synthesizes text to audio data with voice settings.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voiceStyle: The Kokoro voice style (e.g., .afHeart, .bfEmma)
    ///   - speed: Speech rate multiplier (0.5 - 2.0)
    ///   - pitchShiftSemitones: Pitch shift in semitones (-12 to +12, default 0)
    ///   - pitchRangeScale: Pitch variation scale (0.5 - 1.5, default 1.0)
    /// - Returns: WAV audio data
    func synthesizeToData(
        text: String,
        voiceStyle: VoiceStyle,
        speed: Float,
        pitchShiftSemitones: Float = 0.0,
        pitchRangeScale: Float = 1.0
    ) async throws -> Data {
        // Determine language variant from voice style
        let variant = detectLanguageVariant(from: voiceStyle)
        let pipeline = try getPipeline(for: variant)
        
        #if DEBUG
        print("Synthesizing text: '\(text)'")
        print("Text length: \(text.count) characters")
        print("Using pipeline: \(variant.displayName)")
        print("Voice settings: speed=\(speed), pitch=\(pitchShiftSemitones), range=\(pitchRangeScale)")
        #endif
        
        let options = GenerationOptions(
            style: voiceStyle,
            speed: speed,
            pitchShiftSemitones: pitchShiftSemitones,
            pitchRangeScale: pitchRangeScale
        )
        let samples = try await pipeline.generate(text: text, options: options)
        
        #if DEBUG
        print("Generated \(samples.count) samples")
        print("Audio duration: \(Float(samples.count) / Float(TTSConfiguration.kokoroSampleRate)) seconds")
        #endif
        
        return createWAVData(from: samples, sampleRate: TTSConfiguration.kokoroSampleRate)
    }
    
    var isReady: Bool { isWarmedUp }
    
    // MARK: - Memory Management
    
    /// Releases ML pipelines to free memory.
    ///
    /// Call when app enters background or receives memory warning.
    /// After calling this, `isReady` will return `false` and synthesis
    /// will fail until `warmUp()` is called again.
    ///
    /// This can free ~500MB-1GB of memory.
    func releaseForBackground() {
        guard isWarmedUp else {
            #if DEBUG
            print("KokoroTTSEngine: Already released or never initialized")
            #endif
            return
        }
        
        #if DEBUG
        print("KokoroTTSEngine: Releasing ML pipelines for background...")
        #endif
        
        // Nil out the pipelines to release memory
        usPipeline = nil
        gbPipeline = nil
        isWarmedUp = false
        
        #if DEBUG
        print("KokoroTTSEngine: ML pipelines released")
        #endif
    }
    
    /// Checks if the engine can be re-initialized.
    ///
    /// Returns `true` if the Kokoro resources are available in the bundle.
    var canReinitialize: Bool {
        cachedKokoroPath != nil || findKokoroFolder() != nil
    }
    
    // MARK: - Private Methods
    
    private func detectLanguageVariant(from voiceStyle: VoiceStyle) -> LanguageVariant {
        let styleString = voiceStyle.rawValue
        if styleString.hasPrefix("bf_") || styleString.hasPrefix("bm_") {
            return .britishEnglish
        }
        return .americanEnglish
    }
    
    private func getPipeline(for variant: LanguageVariant) throws -> TTSPipeline {
        switch variant {
        case .americanEnglish:
            guard let pipeline = usPipeline else {
                throw AppError.ttsError("US English pipeline not initialized")
            }
            return pipeline
        case .britishEnglish:
            guard let pipeline = gbPipeline else {
                throw AppError.ttsError("GB English pipeline not initialized")
            }
            return pipeline
        }
    }
    
    private func findKokoroFolder() -> String? {
        // Use cached path if available
        if let cached = cachedKokoroPath, FileManager.default.fileExists(atPath: cached) {
            return cached
        }
        
        // Try main bundle first
        if let path = Bundle.main.path(forResource: "Kokoro", ofType: nil) {
            return path
        }
        
        // Try Resources folder in main bundle
        if let resourcePath = Bundle.main.resourcePath {
            let kokoroPath = (resourcePath as NSString).appendingPathComponent("Kokoro")
            if FileManager.default.fileExists(atPath: kokoroPath) {
                return kokoroPath
            }
        }
        
        return nil
    }
    
    private func createWAVData(from samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        
        // WAV header
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = Int16(numChannels * bitsPerSample / 8)
        let dataSize = Int32(samples.count * 2)
        let fileSize = 36 + dataSize
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Audio samples (convert Float to Int16)
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clampedSample * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }
        
        return data
    }
}
