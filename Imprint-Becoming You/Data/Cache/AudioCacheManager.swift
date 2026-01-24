//
//  AudioCacheManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import CryptoKit

// MARK: - AudioCacheManager

/// Manages cached TTS audio files with LRU eviction.
///
/// ## Cache Policy
/// - Maximum size: 500 MB (configurable)
/// - Expiration: 30 days since last access
/// - Eviction: LRU when size limit exceeded
/// - Storage: App's Caches directory
///
/// ## Usage
/// ```swift
/// let cache = AudioCacheManager.shared
/// let key = cache.cacheKey(for: "Hello", voice: voice, speed: 1.0)
///
/// if let result = await cache.get(key: key) {
///     // Use cached result
/// } else {
///     let result = try await ttsService.synthesize(text: "Hello", voice: voice)
///     try await cache.store(key: key, result: result)
/// }
/// ```
actor AudioCacheManager: AudioCacheServiceProtocol {
    
    // MARK: - Singleton
    
    static let shared = AudioCacheManager()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let metadataURL: URL
    private var metadata: CacheMetadata
    private var pregenerationTask: Task<Void, Never>?
    
    /// Statistics tracking
    private var hitCount: Int = 0
    private var missCount: Int = 0
    
    // MARK: - Protocol Properties
    
    /// Maximum cache size - nonisolated for frequent reads, modified via setMaxSize()
    nonisolated(unsafe) private(set) var maxSize: Int64
    
    var currentSize: Int64 {
        get async { metadata.totalSize }
    }
    
    var itemCount: Int {
        get async { metadata.entries.count }
    }
    
    // MARK: - File Access
    
    /// Gets the file URL for a cached audio file by filename.
    ///
    /// Used by `AudioPlayerService` to play cached files directly.
    ///
    /// - Parameter fileName: The filename (returned from `store()`)
    /// - Returns: URL to the file, or `nil` if not found
    func fileURL(forFileName fileName: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Gets the file URL for a cached entry by key.
    ///
    /// - Parameter key: The cache key
    /// - Returns: URL to the file, or `nil` if not cached
    func fileURL(forKey key: String) -> URL? {
        guard let entry = metadata.entries[key], !entry.isExpired else {
            return nil
        }
        return fileURL(forFileName: entry.fileName)
    }
    
    // MARK: - Initialization
    
    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent(
            AudioCacheConfiguration.directoryName,
            isDirectory: true
        )
        metadataURL = cacheDirectory.appendingPathComponent(AudioCacheConfiguration.metadataFileName)
        maxSize = AudioCacheConfiguration.defaultMaxSize
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Load existing metadata
        metadata = CacheMetadata.load(from: metadataURL) ?? CacheMetadata()
        
        // Clean expired entries on startup
        Task { await cleanExpiredEntries() }
    }
    
    // MARK: - Cache Key Generation
    
    nonisolated func cacheKey(for text: String, voice: Voice, speed: Float) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(normalized)|\(voice.id)|\(speed)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }
    
    // MARK: - Cache Operations
    
    func get(key: String) async -> TTSResult? {
        guard let entry = metadata.entries[key], !entry.isExpired else {
            if metadata.entries[key] != nil {
                await removeEntry(forKey: key)
            }
            missCount += 1
            return nil
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            await removeEntry(forKey: key)
            missCount += 1
            return nil
        }
        
        do {
            let audioData = try Data(contentsOf: fileURL)
            
            // Update access time and count
            metadata.entries[key]?.lastAccessedAt = Date()
            metadata.entries[key]?.accessCount += 1
            await saveMetadata()
            
            hitCount += 1
            
            return reconstructResult(from: entry, audioData: audioData)
        } catch {
            missCount += 1
            return nil
        }
    }
    
    @discardableResult
    func store(key: String, result: TTSResult) async throws -> String {
        let fileName = "\(key).\(result.audioFormat.fileExtension)"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        let dataSize = Int64(result.audioData.count)
        await evictIfNeeded(forNewDataSize: dataSize)
        
        // Write audio file
        do {
            try result.audioData.write(to: fileURL, options: .atomic)
        } catch {
            throw TTSError.audioEncodingError(message: "Failed to cache audio: \(error.localizedDescription)")
        }
        
        // Create metadata entry
        let entry = CacheEntryMetadata(
            key: key,
            fileName: fileName,
            text: result.originalText,
            voiceId: result.voice.id,
            speed: 1.0,
            audioFormat: result.audioFormat,
            duration: result.duration,
            sizeBytes: dataSize,
            createdAt: result.synthesizedAt,
            lastAccessedAt: Date(),
            accessCount: 1,
            wordTimings: result.wordTimings.isEmpty ? nil : result.wordTimings
        )
        
        // Update total size if replacing existing entry
        if let existingEntry = metadata.entries[key] {
            metadata.totalSize -= existingEntry.sizeBytes
        }
        
        metadata.entries[key] = entry
        metadata.totalSize += dataSize
        
        await saveMetadata()
        
        return fileName
    }
    
    func remove(key: String) async {
        await removeEntry(forKey: key)
    }
    
    func clearAll() async {
        // Cancel ongoing pregeneration
        pregenerationTask?.cancel()
        pregenerationTask = nil
        
        // Remove all files except metadata
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent != AudioCacheConfiguration.metadataFileName {
                try? fileManager.removeItem(at: file)
            }
        }
        
        // Reset state
        metadata = CacheMetadata()
        hitCount = 0
        missCount = 0
        await saveMetadata()
    }
    
    // MARK: - Pre-generation
    
    func pregenerate(
        texts: [String],
        voice: Voice,
        speed: Float,
        using synthesizer: TTSServiceProtocol
    ) async {
        // Cancel existing pregeneration
        pregenerationTask?.cancel()
        
        pregenerationTask = Task(priority: .background) {
            for text in texts {
                guard !Task.isCancelled else { break }
                
                let key = cacheKey(for: text, voice: voice, speed: speed)
                
                // Skip if already cached
                if let entry = metadata.entries[key], !entry.isExpired {
                    continue
                }
                
                do {
                    let result = try await synthesizer.synthesize(text: text, voice: voice, speed: speed)
                    try await store(key: key, result: result)
                } catch {
                    // Continue with next text on failure
                    continue
                }
            }
        }
        
        await pregenerationTask?.value
    }
    
    func cancelPregeneration() async {
        pregenerationTask?.cancel()
        pregenerationTask = nil
    }
    
    // MARK: - Cache Management
    
    func setMaxSize(_ bytes: Int64) async {
        let clampedSize = max(
            AudioCacheConfiguration.minimumSize,
            min(bytes, AudioCacheConfiguration.maximumSize)
        )
        maxSize = clampedSize
        await evictIfNeeded(forNewDataSize: 0)
    }
    
    func statistics() async -> AudioCacheStatistics {
        AudioCacheStatistics(
            totalSize: metadata.totalSize,
            maxSize: maxSize,
            itemCount: metadata.entries.count,
            hitCount: hitCount,
            missCount: missCount,
            oldestEntry: metadata.entries.values.min(by: { $0.createdAt < $1.createdAt })?.createdAt,
            newestEntry: metadata.entries.values.max(by: { $0.createdAt < $1.createdAt })?.createdAt
        )
    }
    
    // MARK: - Private Methods
    
    private func removeEntry(forKey key: String) async {
        guard let entry = metadata.entries.removeValue(forKey: key) else { return }
        
        metadata.totalSize -= entry.sizeBytes
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        
        await saveMetadata()
    }
    
    private func cleanExpiredEntries() async {
        let expiredKeys = metadata.entries
            .filter { $0.value.isExpired }
            .map { $0.key }
        
        for key in expiredKeys {
            await removeEntry(forKey: key)
        }
    }
    
    private func evictIfNeeded(forNewDataSize newSize: Int64) async {
        let targetSize = maxSize - newSize
        
        guard metadata.totalSize > targetSize else { return }
        
        // Sort by last accessed time (oldest first) for LRU eviction
        let sortedEntries = metadata.entries.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        
        for entry in sortedEntries {
            if metadata.totalSize <= targetSize { break }
            await removeEntry(forKey: entry.key)
        }
    }
    
    private func saveMetadata() async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            // Silent failure - cache still works, just won't persist
        }
    }
    
    private func reconstructResult(from entry: CacheEntryMetadata, audioData: Data) -> TTSResult? {
        guard let voice = VoiceCatalog.findVoice(id: entry.voiceId) else {
            return nil
        }
        
        return TTSResult(
            audioData: audioData,
            audioFormat: entry.audioFormat,
            duration: entry.duration,
            originalText: entry.text,
            voice: voice,
            wordTimings: entry.wordTimings ?? [],
            source: .cached,
            synthesizedAt: entry.createdAt
        )
    }
}

// MARK: - Cache Metadata

private struct CacheMetadata: Codable {
    var entries: [String: CacheEntryMetadata] = [:]
    var totalSize: Int64 = 0
    var lastCleanupAt: Date?
    
    static func load(from url: URL) -> CacheMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CacheMetadata.self, from: data)
    }
}

// MARK: - Cache Entry Metadata

private struct CacheEntryMetadata: Codable {
    let key: String
    let fileName: String
    let text: String
    let voiceId: String
    let speed: Float
    let audioFormat: TTSAudioFormat
    let duration: TimeInterval
    let sizeBytes: Int64
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
    let wordTimings: [WordTiming]?
    
    var isExpired: Bool {
        let expirationInterval = TimeInterval(AudioCacheConfiguration.expirationDays * 24 * 60 * 60)
        return Date().timeIntervalSince(lastAccessedAt) > expirationInterval
    }
}

// MARK: - Voice Catalog Helper

/// Helper for looking up voices by ID.
enum VoiceCatalog {
    
    static func findVoice(id: String) -> Voice? {
        // Check free Kokoro voices
        if let voice = Voice.freeKokoroVoices.first(where: { $0.id == id }) {
            return voice
        }
        
        // Check premium Kokoro voices
        if let voice = Voice.premiumKokoroVoices.first(where: { $0.id == id }) {
            return voice
        }
        
        // Check Qwen preset voices
        if let voice = Voice.qwenPresetVoices.first(where: { $0.id == id }) {
            return voice
        }
        
        // Handle system voices
        if id.hasPrefix("system_") {
            let systemId = String(id.dropFirst(7))
            return Voice.systemVoice(identifier: systemId, name: "System", languageCode: "en-US")
        }
        
        return nil
    }
}
