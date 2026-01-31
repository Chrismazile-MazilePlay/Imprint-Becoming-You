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
        print("🎤 KokoroTTSEngine: Starting warm-up...")
        #endif
        
        guard let kokoroPath = findKokoroFolder() else {
            throw AppError.ttsError("Kokoro folder not found in bundle")
        }
        
        // Cache path for potential re-initialization
        cachedKokoroPath = kokoroPath
        
        #if DEBUG
        print("📁 Found Kokoro at: \(kokoroPath)")
        #endif
        
        // Build paths per library API
        let modelsPath = (kokoroPath as NSString).appendingPathComponent("Models")
        let g2pPath = (kokoroPath as NSString).appendingPathComponent("G2P")
        let posModelPath = (kokoroPath as NSString).appendingPathComponent("POS")
        let espeakPath = (kokoroPath as NSString).appendingPathComponent("Espeak/espeak-ng-data")
        
        #if DEBUG
        print("📁 Models folder: \(FileManager.default.fileExists(atPath: modelsPath))")
        print("📁 G2P folder: \(FileManager.default.fileExists(atPath: g2pPath))")
        print("📁 POS model: \(FileManager.default.fileExists(atPath: posModelPath))")
        print("📁 eSpeak folder: \(FileManager.default.fileExists(atPath: espeakPath))")
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsPath) {
            print("📁 Models contents: \(contents)")
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
        
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        
        let modelsURL = URL(fileURLWithPath: modelsPath)
        let g2pURL = URL(fileURLWithPath: g2pPath)
        let posURL = URL(fileURLWithPath: posModelPath)
        
        // Initialize US English pipeline
        #if DEBUG
        print("🎤 KokoroTTSEngine: Initializing US English pipeline...")
        #endif
        
        usPipeline = try TTSPipeline(
            modelPath: modelsURL,
            vocabURL: g2pURL,
            postaggerModelURL: posURL,
            language: .englishUS,
            espeakDataPath: espeakPath,
            configuration: config
        )
        
        #if DEBUG
        print("✅ KokoroTTSEngine: US English pipeline ready")
        #endif
        
        // Initialize GB English pipeline
        #if DEBUG
        print("🎤 KokoroTTSEngine: Initializing British English pipeline...")
        #endif
        
        gbPipeline = try TTSPipeline(
            modelPath: modelsURL,
            vocabURL: g2pURL,
            postaggerModelURL: posURL,
            language: .englishGB,
            espeakDataPath: espeakPath,
            configuration: config
        )
        
        #if DEBUG
        print("✅ KokoroTTSEngine: British English pipeline ready")
        #endif
        
        isWarmedUp = true
        
        #if DEBUG
        print("✅ KokoroTTSEngine: Warm-up complete (US + GB pipelines ready)")
        #endif
    }
    
    /// Synthesizes text to audio data using the appropriate pipeline for the voice.
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voiceStyle: The Kokoro voice style (e.g., "af_heart", "bf_emma")
    ///   - speed: Speech rate multiplier
    /// - Returns: WAV audio data
    func synthesizeToData(text: String, voiceStyle: VoiceStyle, speed: Float) async throws -> Data {
        // Determine language variant from voice style
        let variant = detectLanguageVariant(from: voiceStyle)
        let pipeline = try getPipeline(for: variant)
        
        #if DEBUG
        print("🎤 Synthesizing text: '\(text)'")
        print("🎤 Text length: \(text.count) characters")
        print("🎤 Using pipeline: \(variant.displayName)")
        #endif
        
        let options = GenerationOptions(style: voiceStyle, speed: speed)
        let samples = try await pipeline.generate(text: text, options: options)
        
        #if DEBUG
        print("🎤 Generated \(samples.count) samples")
        print("🎤 Audio duration: \(Float(samples.count) / Float(TTSConfiguration.kokoroSampleRate)) seconds")
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
            print("🎤 KokoroTTSEngine: Already released or never initialized")
            #endif
            return
        }
        
        #if DEBUG
        print("🎤 KokoroTTSEngine: Releasing ML pipelines for background...")
        #endif
        
        // Nil out the pipelines to release memory
        usPipeline = nil
        gbPipeline = nil
        isWarmedUp = false
        
        #if DEBUG
        print("✅ KokoroTTSEngine: ML pipelines released")
        #endif
    }
    
    /// Checks if the engine can be re-initialized.
    ///
    /// Returns `true` if the Kokoro resources are available in the bundle.
    var canReinitialize: Bool {
        cachedKokoroPath != nil || findKokoroFolder() != nil
    }
    
    // MARK: - Private Methods
    
    /// Detects the language variant from the voice style prefix.
    /// - af_ / am_ = American Female / Male
    /// - bf_ / bm_ = British Female / Male
    private func detectLanguageVariant(from voiceStyle: VoiceStyle) -> LanguageVariant {
        let styleString = voiceStyle.rawValue.lowercased()
        
        if styleString.hasPrefix("bf_") || styleString.hasPrefix("bm_") {
            return .britishEnglish
        }
        
        // Default to American English for af_, am_, and any unknown prefixes
        return .americanEnglish
    }
    
    /// Gets the pipeline for the specified language variant.
    private func getPipeline(for variant: LanguageVariant) throws -> TTSPipeline {
        switch variant {
        case .americanEnglish:
            guard let pipeline = usPipeline else {
                throw AppError.ttsError("US pipeline not initialized. Call warmUp() first.")
            }
            return pipeline
            
        case .britishEnglish:
            guard let pipeline = gbPipeline else {
                throw AppError.ttsError("GB pipeline not initialized. Call warmUp() first.")
            }
            return pipeline
        }
    }
    
    private func findKokoroFolder() -> String? {
        // Use cached path if available
        if let cached = cachedKokoroPath, FileManager.default.fileExists(atPath: cached) {
            return cached
        }
        
        let fm = FileManager.default
        let bundle = Bundle.main
        
        let possiblePaths: [String] = [
            bundle.bundlePath + "/Kokoro",
            bundle.bundlePath + "/Resources/Kokoro",
            (bundle.resourcePath ?? "") + "/Kokoro"
        ]
        
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    private func createWAVData(from samples: [Float], sampleRate: Int) -> Data {
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize
        
        var data = Data()
        data.reserveCapacity(Int(44 + dataSize))
        
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }
        
        return data
    }
}
