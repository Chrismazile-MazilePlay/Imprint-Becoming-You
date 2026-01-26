//
//  VoicePreviewCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Voice Preview Cache Service

/// Production implementation of voice preview caching.
///
/// Synthesizes and caches voice preview audio clips for instant playback
/// in voice selection UI. Supports background synthesis with priority ordering
/// and persistent disk storage.
///
/// ## Storage Structure
/// ```
/// Application Support/
/// └── VoicePreviewCache/
///     ├── manifest.json          ← Version + completion status
///     ├── preview_af_heart.wav
///     ├── preview_af_bella.wav
///     └── ... (26 total)
/// ```
@MainActor
final class VoicePreviewCacheService: VoicePreviewCacheServiceProtocol {
    
    // MARK: - Types
    
    /// Cache manifest for version tracking
    private struct CacheManifest: Codable {
        let version: Int
        let previewPhrase: String
        let generatedAt: Date
        var cachedVoices: [String]
        
        static let currentVersion = 1
    }
    
    // MARK: - Properties
    
    /// TTS service for synthesis
    private let ttsService: any TTSServiceProtocol
    
    /// In-memory cache of audio data
    private var memoryCache: [String: Data] = [:]
    
    /// Current manifest
    private var manifest: CacheManifest?
    
    /// Cache directory URL
    private let cacheDirectoryURL: URL
    
    /// Manifest file URL
    private var manifestURL: URL {
        cacheDirectoryURL.appendingPathComponent("manifest.json")
    }
    
    // MARK: - State
    
    private(set) var isSynthesizing: Bool = false
    
    var isComplete: Bool {
        cachedCount >= totalCount
    }
    
    var cachedCount: Int {
        manifest?.cachedVoices.count ?? 0
    }
    
    var totalCount: Int {
        Voice.allEnglishVoiceIds.count
    }
    
    var synthesisProgress: Float {
        guard totalCount > 0 else { return 0 }
        return Float(cachedCount) / Float(totalCount)
    }
    
    // MARK: - Initialization
    
    init(ttsService: any TTSServiceProtocol) {
        self.ttsService = ttsService
        
        // Setup cache directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDirectoryURL = appSupport.appendingPathComponent("VoicePreviewCache", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        
        // Load manifest and cached audio
        loadManifest()
        loadCachedAudioIntoMemory()
        
        #if DEBUG
        print("🎤 VoicePreviewCache: Initialized (\(cachedCount)/\(totalCount) cached)")
        #endif
    }
    
    // MARK: - Cache Access
    
    func isReady(_ voiceId: String) -> Bool {
        // Check memory cache first (fastest)
        if memoryCache[voiceId] != nil {
            return true
        }
        
        // Check manifest (file exists but not loaded)
        if manifest?.cachedVoices.contains(voiceId) == true {
            // Try to load from disk
            if let data = loadFromDisk(voiceId: voiceId) {
                memoryCache[voiceId] = data
                return true
            }
        }
        
        return false
    }
    
    func getPreviewAudio(for voiceId: String) -> Data? {
        // Try memory cache first
        if let data = memoryCache[voiceId] {
            return data
        }
        
        // Try loading from disk
        if let data = loadFromDisk(voiceId: voiceId) {
            memoryCache[voiceId] = data
            return data
        }
        
        return nil
    }
    
    // MARK: - Synthesis
    
    func startBackgroundSynthesis() async {
        // Skip if already complete
        guard !isComplete else {
            #if DEBUG
            print("🎤 VoicePreviewCache: Already complete (\(cachedCount)/\(totalCount))")
            #endif
            return
        }
        
        // Skip if already synthesizing
        guard !isSynthesizing else {
            #if DEBUG
            print("🎤 VoicePreviewCache: Background synthesis already in progress")
            #endif
            return
        }
        
        // Check if manifest needs reset (phrase changed, version bumped)
        if let manifest = manifest {
            if manifest.previewPhrase != Voice.previewPhrase || manifest.version != CacheManifest.currentVersion {
                #if DEBUG
                print("🎤 VoicePreviewCache: Manifest outdated, clearing cache")
                #endif
                clearCache()
            }
        }
        
        isSynthesizing = true
        
        #if DEBUG
        print("🎤 VoicePreviewCache: Starting background synthesis (\(cachedCount)/\(totalCount) cached)")
        let startTime = Date()
        #endif
        
        // Get voices to synthesize (those not yet cached)
        let voicesToSynthesize = Voice.allEnglishVoiceIds.filter { !isReady($0) }
        
        for voiceId in voicesToSynthesize {
            // Check if task was cancelled
            guard !Task.isCancelled else { break }
            
            do {
                _ = try await synthesizeAndCache(voiceId: voiceId)
                
                #if DEBUG
                print("🎤 VoicePreviewCache: Cached \(voiceId) (\(cachedCount)/\(totalCount))")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ VoicePreviewCache: Failed to synthesize \(voiceId): \(error)")
                #endif
                // Continue with next voice - don't fail entire process
            }
            
            // Small delay to avoid overwhelming the system
            try? await Task.sleep(for: .milliseconds(50))
        }
        
        isSynthesizing = false
        
        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("🎤 VoicePreviewCache: Background synthesis complete (\(cachedCount)/\(totalCount)) in \(String(format: "%.1f", elapsed))s")
        #endif
    }
    
    func synthesizeNow(_ voiceId: String) async throws -> Data {
        // Return cached if available
        if let cached = getPreviewAudio(for: voiceId) {
            #if DEBUG
            print("🎤 VoicePreviewCache: Cache hit for \(voiceId)")
            #endif
            return cached
        }
        
        #if DEBUG
        print("🎤 VoicePreviewCache: Cache miss, synthesizing \(voiceId)")
        #endif
        
        // Synthesize and cache
        return try await synthesizeAndCache(voiceId: voiceId)
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        // Clear memory cache
        memoryCache.removeAll()
        
        // Clear disk cache
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        
        // Reset manifest
        manifest = nil
        
        #if DEBUG
        print("🎤 VoicePreviewCache: Cache cleared")
        #endif
    }
    
    // MARK: - Private Methods
    
    private func synthesizeAndCache(voiceId: String) async throws -> Data {
        // Synthesize using TTS service
        #if DEBUG
        print("🎤 VoicePreviewCache: Synthesizing \(voiceId)...")
        #endif
        
        let audioData = try await ttsService.synthesize(text: Voice.previewPhrase, voiceId: voiceId)
        
        #if DEBUG
        print("🎤 VoicePreviewCache: Synthesized \(voiceId) (\(audioData.count) bytes)")
        #endif
        
        // Cache to memory
        memoryCache[voiceId] = audioData
        
        // Cache to disk
        saveToDisk(voiceId: voiceId, data: audioData)
        
        // Update manifest
        updateManifest(addingVoice: voiceId)
        
        return audioData
    }
    
    private func previewFileURL(for voiceId: String) -> URL {
        cacheDirectoryURL.appendingPathComponent("preview_\(voiceId).wav")
    }
    
    private func loadFromDisk(voiceId: String) -> Data? {
        let fileURL = previewFileURL(for: voiceId)
        return try? Data(contentsOf: fileURL)
    }
    
    private func saveToDisk(voiceId: String, data: Data) {
        let fileURL = previewFileURL(for: voiceId)
        try? data.write(to: fileURL)
    }
    
    private func loadManifest() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(CacheManifest.self, from: data)
        } catch {
            #if DEBUG
            print("⚠️ VoicePreviewCache: Failed to load manifest: \(error)")
            #endif
        }
    }
    
    private func saveManifest() {
        guard let manifest = manifest else { return }
        
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestURL)
        } catch {
            #if DEBUG
            print("⚠️ VoicePreviewCache: Failed to save manifest: \(error)")
            #endif
        }
    }
    
    private func updateManifest(addingVoice voiceId: String) {
        if manifest == nil {
            manifest = CacheManifest(
                version: CacheManifest.currentVersion,
                previewPhrase: Voice.previewPhrase,
                generatedAt: Date(),
                cachedVoices: []
            )
        }
        
        if !(manifest?.cachedVoices.contains(voiceId) ?? false) {
            manifest?.cachedVoices.append(voiceId)
            saveManifest()
        }
    }
    
    private func loadCachedAudioIntoMemory() {
        guard let manifest = manifest else { return }
        
        var loadedCount = 0
        for voiceId in manifest.cachedVoices {
            if let data = loadFromDisk(voiceId: voiceId) {
                memoryCache[voiceId] = data
                loadedCount += 1
            }
        }
        
        #if DEBUG
        print("🎤 VoicePreviewCache: Loaded \(loadedCount) previews into memory")
        #endif
    }
}
