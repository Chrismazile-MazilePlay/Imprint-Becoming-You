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
/// ## Lazy Pipeline Loading
/// Only the pipeline for the actively-used language is loaded into memory.
/// Each pipeline consumes ~300-350MB. By defaulting to American English and
/// loading British English on-demand, peak memory is reduced by ~330MB
/// compared to loading both pipelines at startup.
///
/// ## Long Text Handling
/// The underlying BERT model has a fixed 256-token context window.
/// Text exceeding this limit is automatically split at natural language
/// boundaries (sentences, clauses), synthesized per-chunk, and the raw
/// audio samples are concatenated before WAV encoding. Short text
/// (<=150 characters) takes a zero-overhead fast path.
///
/// ## Memory Management
/// The ML pipelines consume significant memory (~300-350MB each).
/// Use `releasePipelines()` to free memory. The caller (`TTSService`)
/// determines whether Kokoro is logically disabled (background) or
/// stays ready for lazy reload (session end, idle timer).
///
/// After first launch, CoreML caches compiled models on disk, so
/// pipeline reloads take ~1-2s (vs ~7-8s for the initial compilation).
///
/// ```swift
/// // Release pipelines (from any context)
/// await kokoroEngine.releasePipelines()
///
/// // Warm up again (reloads from CoreML cache in ~1-2s)
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
    
    // MARK: - Constants
    
    /// Maximum input characters for a single synthesis pass.
    ///
    /// The Kokoro BERT model accepts a maximum of 256 tokens in its
    /// attention_mask dimension. Phoneme tokenization produces roughly
    /// 1.0-1.1 BERT tokens per input character (confirmed empirically:
    /// 177 chars -> 180 tokens, 270 chars -> 286 tokens).
    ///
    /// Using 150 characters keeps BERT input under ~165 tokens, which
    /// reduces Generator Core intermediate tensor sizes and peak memory
    /// by ~40% compared to 200-char chunks. This prevents memory warnings
    /// on devices with 2GB limits.
    private static let maxChunkCharacters = 150
    
    // MARK: - Properties
    
    private var usPipeline: TTSPipeline?
    private var gbPipeline: TTSPipeline?
    
    /// Whether resources have been validated (paths exist, configs built).
    /// Set to true after the first successful warmUp() call.
    private var resourcesValidated: Bool = false
    
    /// Cached paths for re-initialization after release
    private var cachedKokoroPath: String?
    
    /// Cached resource URLs built once during validation, reused for lazy loading.
    private var cachedModelsURL: URL?
    private var cachedVocabURL: URL?
    private var cachedPosURL: URL?
    private var cachedEspeakPath: String?
    private var cachedMLConfig: MLModelConfiguration?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Validates resources and eagerly loads the preferred language pipeline.
    ///
    /// Loads the specified language pipeline into memory (~300-350MB) to ensure
    /// the fastest possible first synthesis. The CoreML compilation cache is
    /// populated on first-ever load (~7-8s), making all subsequent pipeline
    /// reloads fast (~1-2s) even after memory release.
    ///
    /// The synthesis idle timer in `TTSService` automatically releases the
    /// pipeline after 30s of inactivity, so this eager load is self-correcting
    /// if the user doesn't immediately use TTS.
    ///
    /// - Parameter preferredLanguage: The language to pre-load (default: US English)
    func warmUp(preferredLanguage: LanguageVariant = .americanEnglish) async throws {
        // If already validated, just ensure the preferred pipeline is loaded
        if resourcesValidated {
            _ = try await ensurePipeline(for: preferredLanguage)
            return
        }
        
        #if DEBUG
        print("KokoroTTSEngine: Starting warm-up...")
        #endif
        
        // Validate and cache all resource paths (one-time)
        try validateAndCacheResources()
        
        // Eagerly load the preferred language pipeline
        _ = try await ensurePipeline(for: preferredLanguage)
        
        #if DEBUG
        print("KokoroTTSEngine: Warm-up complete (\(preferredLanguage.displayName) pipeline loaded)")
        #endif
    }
    
    /// Synthesizes text to audio data with voice settings.
    ///
    /// Automatically handles text that exceeds the BERT model's 256-token
    /// context window by splitting at natural language boundaries and
    /// concatenating the resulting audio samples.
    ///
    /// If the required language pipeline is not yet loaded (e.g., first use
    /// of a British voice), it will be loaded on-demand before synthesis.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize (any length)
    ///   - voiceStyle: The Kokoro voice style (e.g., .afHeart, .bfEmma)
    ///   - speed: Speech rate multiplier (0.5 - 2.0)
    ///   - pitchShiftSemitones: Pitch shift in semitones (-12 to +12, default 0)
    ///   - pitchRangeScale: Pitch variation scale (0.5 - 1.5, default 1.0)
    ///   - onChunkProgress: Optional callback reporting (completedChunks, totalChunks)
    ///     after each chunk is synthesized. For short text (single chunk), reports (1, 1).
    /// - Returns: WAV audio data
    func synthesizeToData(
        text: String,
        voiceStyle: VoiceStyle,
        speed: Float,
        pitchShiftSemitones: Float = 0.0,
        pitchRangeScale: Float = 1.0,
        onChunkProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Data {
        // Determine language variant from voice style and ensure pipeline is loaded
        let variant = detectLanguageVariant(from: voiceStyle)
        let pipeline = try await ensurePipeline(for: variant)
        
        let options = GenerationOptions(
            style: voiceStyle,
            speed: speed,
            pitchShiftSemitones: pitchShiftSemitones,
            pitchRangeScale: pitchRangeScale
        )
        
        #if DEBUG
        print("Synthesizing text: '\(text)'")
        print("Text length: \(text.count) characters")
        print("Using pipeline: \(variant.displayName)")
        print("Voice settings: speed=\(speed), pitch=\(pitchShiftSemitones), range=\(pitchRangeScale)")
        #endif
        
        // Fast path: short text fits within BERT model's 256-token context window.
        // Zero overhead - no splitting, no array concatenation.
        if text.count <= Self.maxChunkCharacters {
            let samples = try await pipeline.generate(text: text, options: options)
            
            #if DEBUG
            print("Generated \(samples.count) samples")
            print("Audio duration: \(Float(samples.count) / Float(TTSConfiguration.kokoroSampleRate)) seconds")
            #endif

            onChunkProgress?(1, 1)

            return createWAVData(from: samples, sampleRate: TTSConfiguration.kokoroSampleRate)
        }
        
        // Long text path: split into chunks that each fit the BERT context window,
        // synthesize each to raw Float samples, concatenate, then WAV-encode once.
        let chunks = splitTextForSynthesis(text)
        
        #if DEBUG
        print("KokoroTTSEngine: Text exceeds single-pass limit (\(text.count) chars > \(Self.maxChunkCharacters))")
        print("KokoroTTSEngine: Split into \(chunks.count) chunks:")
        for (i, chunk) in chunks.enumerated() {
            let preview = chunk.count > 60 ? String(chunk.prefix(60)) + "..." : chunk
            print("  Chunk \(i): \(chunk.count) chars - \"\(preview)\"")
        }
        #endif
        
        // Pre-allocate with estimated capacity (~1100 samples per input character
        // at 24kHz with typical speech rate). Prevents repeated reallocations.
        var allSamples: [Float] = []
        allSamples.reserveCapacity(text.count * 1100)
        
        for (index, chunk) in chunks.enumerated() {
            let samples = try await pipeline.generate(text: chunk, options: options)
            allSamples.append(contentsOf: samples)
            
            #if DEBUG
            let duration = Float(samples.count) / Float(TTSConfiguration.kokoroSampleRate)
            print("KokoroTTSEngine: Chunk \(index) -> \(samples.count) samples (\(String(format: "%.2f", duration))s)")
            #endif

            onChunkProgress?(index + 1, chunks.count)
        }
        
        #if DEBUG
        let totalDuration = Float(allSamples.count) / Float(TTSConfiguration.kokoroSampleRate)
        print("KokoroTTSEngine: Combined \(allSamples.count) samples (\(String(format: "%.2f", totalDuration))s)")
        #endif
        
        return createWAVData(from: allSamples, sampleRate: TTSConfiguration.kokoroSampleRate)
    }
    
    /// Whether the engine has validated resources and has at least one pipeline loaded.
    var isReady: Bool { resourcesValidated && (usPipeline != nil || gbPipeline != nil) }
    
    // MARK: - Memory Management
    
    /// Releases all ML pipelines to free CoreML prediction buffer memory.
    ///
    /// Nils pipeline objects to trigger deallocation of both the model weights
    /// (~300-350MB per pipeline) and accumulated CoreML prediction buffers
    /// (~500MB-1GB). Total savings: ~800MB-1.5GB.
    ///
    /// `resourcesValidated` remains `true` so `ensurePipeline()` can reload
    /// on-demand without re-validating file paths. `isReady` also remains
    /// `true` — the caller (`TTSService`) controls whether Kokoro is
    /// logically disabled (background) or stays ready (session end / idle).
    ///
    /// ## Performance Impact
    /// First-ever pipeline load compiles the CoreML model (~7-8s). After that,
    /// CoreML's on-disk compilation cache makes all subsequent reloads ~1-2s.
    /// This cost is absorbed by the session "Preparing..." UI or masked by
    /// the "Synthesizing..." indicator on voice previews.
    func releasePipelines() {
        guard usPipeline != nil || gbPipeline != nil else {
            #if DEBUG
            print("KokoroTTSEngine: No pipelines to release")
            #endif
            return
        }
        
        #if DEBUG
        let releasedUS = usPipeline != nil
        let releasedGB = gbPipeline != nil
        print("KokoroTTSEngine: Releasing ML pipelines (US: \(releasedUS), GB: \(releasedGB))")
        #endif
        
        usPipeline = nil
        gbPipeline = nil
        
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
    
    // MARK: - Pipeline Management
    
    /// Ensures the pipeline for the given language variant is loaded.
    ///
    /// If already loaded, returns it immediately (fast path).
    /// If not loaded, creates it using cached resource paths.
    ///
    /// - Parameter variant: The language variant to ensure
    /// - Returns: The loaded pipeline
    private func ensurePipeline(for variant: LanguageVariant) async throws -> TTSPipeline {
        // Fast path: pipeline already loaded
        switch variant {
        case .americanEnglish:
            if let pipeline = usPipeline { return pipeline }
        case .britishEnglish:
            if let pipeline = gbPipeline { return pipeline }
        }
        
        // Ensure resources are validated
        guard resourcesValidated,
              let modelsURL = cachedModelsURL,
              let vocabURL = cachedVocabURL,
              let posURL = cachedPosURL,
              let espeakPath = cachedEspeakPath,
              let config = cachedMLConfig else {
            throw AppError.ttsError("Resources not validated. Call warmUp() first.")
        }
        
        #if DEBUG
        print("KokoroTTSEngine: Loading \(variant.displayName) pipeline on-demand...")
        #endif
        
        do {
            let pipeline = try TTSPipeline(
                modelPath: modelsURL,
                vocabURL: vocabURL,
                postaggerModelURL: posURL,
                language: variant == .americanEnglish ? .englishUS : .englishGB,
                espeakDataPath: espeakPath,
                configuration: config
            )
            
            switch variant {
            case .americanEnglish:
                usPipeline = pipeline
            case .britishEnglish:
                gbPipeline = pipeline
            }
            
            #if DEBUG
            print("KokoroTTSEngine: \(variant.displayName) pipeline loaded")
            #endif
            
            return pipeline
        } catch {
            #if DEBUG
            print("KokoroTTSEngine: Failed to load \(variant.displayName) pipeline: \(error)")
            #endif
            throw error
        }
    }
    
    /// Validates that all required Kokoro resources exist and caches their paths.
    ///
    /// Called once during the first `warmUp()`. Subsequent calls to
    /// `ensurePipeline()` reuse the cached paths without re-validating.
    private func validateAndCacheResources() throws {
        guard let kokoroPath = findKokoroFolder() else {
            throw AppError.ttsError("Kokoro folder not found in bundle")
        }
        
        cachedKokoroPath = kokoroPath
        
        #if DEBUG
        print("Found Kokoro at: \(kokoroPath)")
        #endif
        
        // Build and validate paths
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
        
        // Cache everything for lazy pipeline loading
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        cachedModelsURL = URL(fileURLWithPath: modelsPath)
        cachedVocabURL = URL(fileURLWithPath: g2pPath)
        cachedPosURL = URL(fileURLWithPath: posModelPath)
        cachedEspeakPath = espeakPath
        cachedMLConfig = config
        
        resourcesValidated = true
        
        #if DEBUG
        print("KokoroTTSEngine: Resources validated and cached")
        #endif
    }
    
    // MARK: - Text Chunking
    
    /// Splits text into chunks that each fit within the BERT model's
    /// 256-token context window.
    ///
    /// Uses a tiered boundary strategy for natural-sounding splits:
    /// 1. Sentence boundaries (`.` `!` `?`) - preserves intonation contours
    /// 2. Clause boundaries (`;` `,`) - preserves phrase-level prosody
    /// 3. Word boundaries (space) - last resort before hard split
    /// 4. Hard character limit - emergency fallback for pathological input
    ///
    /// Punctuation is included in the preceding chunk so the TTS model
    /// produces correct sentence-final or clause-final intonation.
    ///
    /// - Parameter text: The full input text to split
    /// - Returns: Array of text chunks, each under `maxChunkCharacters`
    private func splitTextForSynthesis(_ text: String) -> [String] {
        guard text.count > Self.maxChunkCharacters else {
            return [text]
        }
        
        var chunks: [String] = []
        var remaining = text[text.startIndex...]
        
        while !remaining.isEmpty {
            // If remainder fits in a single pass, append and finish
            if remaining.count <= Self.maxChunkCharacters {
                let trimmed = remaining.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    chunks.append(trimmed)
                }
                break
            }
            
            let searchEnd = remaining.index(
                remaining.startIndex,
                offsetBy: Self.maxChunkCharacters
            )
            let window = remaining[remaining.startIndex..<searchEnd]
            
            // Tier 1: Split at sentence boundary (. ! ?)
            // Include the punctuation in the chunk for proper intonation.
            if let idx = lastIndex(in: window, where: { ".!?".contains($0) }) {
                let chunkEnd = remaining.index(after: idx)
                appendChunk(from: remaining, upTo: chunkEnd, into: &chunks)
                remaining = remaining[chunkEnd...].drop(while: \.isWhitespace)
                continue
            }
            
            // Tier 2: Split at clause boundary (; ,)
            if let idx = lastIndex(in: window, where: { ";,".contains($0) }) {
                let chunkEnd = remaining.index(after: idx)
                appendChunk(from: remaining, upTo: chunkEnd, into: &chunks)
                remaining = remaining[chunkEnd...].drop(while: \.isWhitespace)
                continue
            }
            
            // Tier 3: Split at last word boundary (space)
            if let idx = window.lastIndex(of: " ") {
                appendChunk(from: remaining, upTo: idx, into: &chunks)
                remaining = remaining[idx...].drop(while: \.isWhitespace)
                continue
            }
            
            // Tier 4: Hard split at character limit (pathological input)
            appendChunk(from: remaining, upTo: searchEnd, into: &chunks)
            remaining = remaining[searchEnd...]
        }
        
        return chunks
    }
    
    /// Finds the last index in a substring where the character satisfies a predicate.
    /// Iterates backwards from the end for early termination.
    private func lastIndex(
        in text: Substring,
        where predicate: (Character) -> Bool
    ) -> String.Index? {
        var idx = text.endIndex
        while idx > text.startIndex {
            text.formIndex(before: &idx)
            if predicate(text[idx]) {
                return idx
            }
        }
        return nil
    }
    
    /// Extracts a chunk from source up to the given index, trims whitespace,
    /// and appends to the chunks array if non-empty.
    private func appendChunk(
        from source: Substring,
        upTo end: String.Index,
        into chunks: inout [String]
    ) {
        let chunk = String(source[source.startIndex..<end])
            .trimmingCharacters(in: .whitespaces)
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
    }
    
    // MARK: - Private Methods
    
    private func detectLanguageVariant(from voiceStyle: VoiceStyle) -> LanguageVariant {
        let styleString = voiceStyle.rawValue
        if styleString.hasPrefix("bf_") || styleString.hasPrefix("bm_") {
            return .britishEnglish
        }
        return .americanEnglish
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
