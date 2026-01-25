//
//  AudioCacheManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import CryptoKit

// MARK: - Audio Cache Manager

/// Manages cached TTS audio files with LRU eviction.
///
/// Caches synthesized audio data by text and voiceId to reduce synthesis calls
/// and enable offline playback of previously heard content.
///
/// ## Cache Policy
/// - Maximum size: 500 MB (configurable)
/// - Expiration: 30 days since last access
/// - Eviction: LRU when size limit exceeded
/// - Storage: App's Caches directory (system can purge if needed)
///
/// ## Usage
/// ```swift
/// let cache = AudioCacheManager.shared
///
/// // Check cache first
/// if let data = await cache.getCachedAudio(forText: "Hello", voiceId: "kokoro_afHeart") {
///     // Play cached audio
/// } else {
///     // Synthesize and cache
///     let data = try await tts.synthesize(text: "Hello", voiceId: "kokoro_afHeart")
///     try await cache.cacheAudio(data, forText: "Hello", voiceId: "kokoro_afHeart")
/// }
/// ```
actor AudioCacheManager: AudioCacheServiceProtocol {
    
    // MARK: - Singleton
    
    static let shared = AudioCacheManager()
    
    // MARK: - Configuration
    
    /// Cache directory name
    private static let directoryName = "TTSAudioCache"
    
    /// Metadata file name
    private static let metadataFileName = "cache_metadata.json"
    
    /// Default max cache size: 500 MB
    private static let defaultMaxSize: Int64 = 500 * 1024 * 1024
    
    /// Minimum allowed cache size: 50 MB
    private static let minimumSize: Int64 = 50 * 1024 * 1024
    
    /// Maximum allowed cache size: 2 GB
    private static let maximumSize: Int64 = 2 * 1024 * 1024 * 1024
    
    /// Expiration: 30 days (fileprivate so CacheEntry can access)
    fileprivate static let expirationDays: Int = 30
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let metadataURL: URL
    private var metadata: CacheMetadata
    
    /// Maximum cache size in bytes
    let maxCacheSize: Int64
    
    /// Current cache size in bytes
    var cacheSize: Int64 {
        metadata.totalSize
    }
    
    // MARK: - Initialization
    
    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
        metadataURL = cacheDirectory.appendingPathComponent(Self.metadataFileName)
        maxCacheSize = Self.defaultMaxSize
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Load existing metadata
        metadata = CacheMetadata.load(from: metadataURL) ?? CacheMetadata()
        
        // Clean expired entries on startup
        Task { await cleanExpiredEntries() }
    }
    
    // MARK: - AudioCacheServiceProtocol
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        let key = cacheKey(for: text, voiceId: voiceId)
        
        guard let entry = metadata.entries[key], !entry.isExpired else {
            // Remove expired entry if exists
            if metadata.entries[key] != nil {
                await removeEntry(forKey: key)
            }
            return nil
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            await removeEntry(forKey: key)
            return nil
        }
        
        do {
            let audioData = try Data(contentsOf: fileURL)
            
            // Update access time (LRU tracking)
            metadata.entries[key]?.lastAccessedAt = Date()
            metadata.entries[key]?.accessCount += 1
            saveMetadata()
            
            return audioData
        } catch {
            return nil
        }
    }
    
    @discardableResult
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        let key = cacheKey(for: text, voiceId: voiceId)
        let fileName = "\(key).wav"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        let dataSize = Int64(data.count)
        
        // Evict old entries if needed
        await evictIfNeeded(forNewDataSize: dataSize)
        
        // Write audio file
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.cacheError(reason: "Failed to cache audio: \(error.localizedDescription)")
        }
        
        // Update total size if replacing existing entry
        if let existingEntry = metadata.entries[key] {
            metadata.totalSize -= existingEntry.sizeBytes
        }
        
        // Create metadata entry
        let entry = CacheEntry(
            key: key,
            fileName: fileName,
            textHash: text.hashValue,
            voiceId: voiceId,
            sizeBytes: dataSize,
            createdAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 1
        )
        
        metadata.entries[key] = entry
        metadata.totalSize += dataSize
        
        saveMetadata()
        
        return fileName
    }
    
    func removeCachedAudio(fileName: String) async {
        // Find entry by fileName
        guard let entry = metadata.entries.values.first(where: { $0.fileName == fileName }) else {
            return
        }
        await removeEntry(forKey: entry.key)
    }
    
    func clearCache() async {
        // Remove all files except metadata
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent != Self.metadataFileName {
                try? fileManager.removeItem(at: file)
            }
        }
        
        // Reset metadata
        metadata = CacheMetadata()
        saveMetadata()
    }
    
    // MARK: - Additional Methods
    
    /// Gets the file URL for a cached audio file by filename.
    ///
    /// Used by audio players to play cached files directly.
    func fileURL(forFileName fileName: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Gets the file URL for cached audio by text and voiceId.
    func fileURL(forText text: String, voiceId: String) -> URL? {
        let key = cacheKey(for: text, voiceId: voiceId)
        guard let entry = metadata.entries[key], !entry.isExpired else {
            return nil
        }
        return fileURL(forFileName: entry.fileName)
    }
    
    /// Checks if audio is cached for the given text and voiceId.
    func isCached(text: String, voiceId: String) -> Bool {
        let key = cacheKey(for: text, voiceId: voiceId)
        guard let entry = metadata.entries[key] else { return false }
        return !entry.isExpired
    }
    
    /// Returns cache statistics for debugging.
    func statistics() -> (itemCount: Int, totalSize: Int64, maxSize: Int64) {
        (metadata.entries.count, metadata.totalSize, maxCacheSize)
    }
    
    // MARK: - Private Methods
    
    /// Generates a cache key from text and voiceId.
    private func cacheKey(for text: String, voiceId: String) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(normalized)|\(voiceId)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }
    
    private func removeEntry(forKey key: String) async {
        guard let entry = metadata.entries.removeValue(forKey: key) else { return }
        
        metadata.totalSize -= entry.sizeBytes
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        
        saveMetadata()
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
        let targetSize = maxCacheSize - newSize
        
        guard metadata.totalSize > targetSize else { return }
        
        // Sort by last accessed time (oldest first) for LRU eviction
        let sortedEntries = metadata.entries.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        
        for entry in sortedEntries {
            if metadata.totalSize <= targetSize { break }
            await removeEntry(forKey: entry.key)
        }
    }
    
    private func saveMetadata() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            // Silent failure - cache still works, just won't persist across launches
            #if DEBUG
            print("⚠️ AudioCacheManager: Failed to save metadata - \(error)")
            #endif
        }
    }
}

// MARK: - Cache Metadata

private struct CacheMetadata: Codable {
    var entries: [String: CacheEntry] = [:]
    var totalSize: Int64 = 0
    
    static func load(from url: URL) -> CacheMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CacheMetadata.self, from: data)
    }
}

// MARK: - Cache Entry

private struct CacheEntry: Codable {
    let key: String
    let fileName: String
    let textHash: Int
    let voiceId: String
    let sizeBytes: Int64
    let createdAt: Date
    var lastAccessedAt: Date
    var accessCount: Int
    
    /// Entry expires 30 days after last access
    var isExpired: Bool {
        let expirationInterval = TimeInterval(AudioCacheManager.expirationDays * 24 * 60 * 60)
        return Date().timeIntervalSince(lastAccessedAt) > expirationInterval
    }
}
