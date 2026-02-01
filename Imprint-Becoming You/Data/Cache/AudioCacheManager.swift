//
//  AudioCacheManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import CryptoKit

// MARK: - Cache Cleanup Statistics

/// Statistics from a cache cleanup operation.
///
/// Used for debugging and monitoring cache health.
struct CacheCleanupStats {
    /// Number of entries successfully removed
    let removedCount: Int
    
    /// Number of entries that failed to delete
    let failedCount: Int
    
    /// Total bytes freed
    let freedBytes: Int64
    
    /// Time taken for cleanup
    let duration: TimeInterval
    
    /// Keys that failed to delete (for debugging)
    let failedKeys: [String]
}

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
/// ## Batch Operations
/// For efficiency, cleanup operations use batch deletion:
/// - Multiple files are deleted in a single pass
/// - Metadata is saved only once after all deletions
/// - Failed deletions don't break the entire batch
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
        
        // Evict old entries if needed (using batch eviction)
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
    
    /// Clears the entire cache efficiently.
    ///
    /// Unlike calling `removeEntry` for each item, this:
    /// 1. Removes the entire cache directory
    /// 2. Recreates an empty directory
    /// 3. Resets metadata in one operation
    ///
    /// This is much faster than sequential deletion for large caches.
    func clearCache() async {
        let startTime = Date()
        let previousCount = metadata.entries.count
        let previousSize = metadata.totalSize
        
        do {
            // Remove entire cache directory
            try fileManager.removeItem(at: cacheDirectory)
            
            // Recreate empty directory
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            
            // Reset metadata
            metadata = CacheMetadata()
            saveMetadata()
            
            let duration = Date().timeIntervalSince(startTime)
            AppLogger.info(
                "Cache cleared completely",
                category: .data,
                context: [
                    "previousEntries": previousCount,
                    "freedBytes": previousSize,
                    "durationMs": Int(duration * 1000)
                ]
            )
        } catch {
            // Fallback to individual file deletion
            AppLogger.warning(
                "Directory removal failed, falling back to individual deletion",
                category: .data,
                context: ["error": error.localizedDescription]
            )
            
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
    
    /// Performs a full cache cleanup and returns statistics.
    ///
    /// Useful for debugging and testing cache behavior.
    ///
    /// - Returns: Statistics about the cleanup operation
    func performCleanup() async -> CacheCleanupStats {
        let startTime = Date()
        
        // Find expired entries
        let expiredKeys = metadata.entries
            .filter { $0.value.isExpired }
            .map { $0.key }
        
        guard !expiredKeys.isEmpty else {
            return CacheCleanupStats(
                removedCount: 0,
                failedCount: 0,
                freedBytes: 0,
                duration: Date().timeIntervalSince(startTime),
                failedKeys: []
            )
        }
        
        // Batch remove expired entries
        let result = await batchRemoveEntries(keys: expiredKeys)
        
        return CacheCleanupStats(
            removedCount: result.removedCount,
            failedCount: result.failedKeys.count,
            freedBytes: result.freedBytes,
            duration: Date().timeIntervalSince(startTime),
            failedKeys: result.failedKeys
        )
    }
    
    // MARK: - Private Methods
    
    /// Generates a cache key from text and voiceId.
    private func cacheKey(for text: String, voiceId: String) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(normalized)|\(voiceId)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }
    
    /// Removes a single entry from the cache.
    ///
    /// For removing multiple entries, prefer `batchRemoveEntries` for efficiency.
    private func removeEntry(forKey key: String) async {
        guard let entry = metadata.entries.removeValue(forKey: key) else { return }
        
        metadata.totalSize -= entry.sizeBytes
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        
        saveMetadata()
    }
    
    // MARK: - Batch Operations
    
    /// Removes multiple cache entries in a single batch operation.
    ///
    /// Optimizes for:
    /// - Single metadata save at the end
    /// - Graceful handling of individual failures
    /// - Progress tracking for large operations
    ///
    /// - Parameter keys: Array of cache keys to remove
    /// - Returns: Tuple with removed count, freed bytes, and failed keys
    private func batchRemoveEntries(keys: [String]) async -> (removedCount: Int, freedBytes: Int64, failedKeys: [String]) {
        guard !keys.isEmpty else {
            return (0, 0, [])
        }
        
        var removedCount = 0
        var freedBytes: Int64 = 0
        var failedKeys: [String] = []
        
        // Batch file deletions
        for key in keys {
            guard let entry = metadata.entries[key] else { continue }
            
            let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
            
            do {
                try fileManager.removeItem(at: fileURL)
                
                // Update metadata in memory (not persisted yet)
                metadata.entries.removeValue(forKey: key)
                metadata.totalSize -= entry.sizeBytes
                
                freedBytes += entry.sizeBytes
                removedCount += 1
                
            } catch {
                // Track failures for logging, don't fail entire batch
                failedKeys.append(key)
                
                // Still remove from metadata to avoid orphaned entries
                if let removedEntry = metadata.entries.removeValue(forKey: key) {
                    metadata.totalSize -= removedEntry.sizeBytes
                }
                
                #if DEBUG
                print("⚠️ AudioCacheManager: Failed to delete \(entry.fileName): \(error)")
                #endif
            }
        }
        
        // Single metadata save at the end
        saveMetadata()
        
        // Log failures if any
        if !failedKeys.isEmpty {
            AppLogger.warning(
                "Some cache entries failed to delete",
                category: .data,
                context: [
                    "failedCount": failedKeys.count,
                    "succeededCount": removedCount
                ]
            )
        }
        
        return (removedCount, freedBytes, failedKeys)
    }
    
    /// Cleans expired entries using batch deletion.
    private func cleanExpiredEntries() async {
        let expiredKeys = metadata.entries
            .filter { $0.value.isExpired }
            .map { $0.key }
        
        guard !expiredKeys.isEmpty else { return }
        
        AppLogger.debug(
            "Cleaning expired cache entries",
            category: .data,
            context: ["count": expiredKeys.count]
        )
        
        let result = await batchRemoveEntries(keys: expiredKeys)
        
        AppLogger.info(
            "Expired cache entries cleaned",
            category: .data,
            context: [
                "removed": result.removedCount,
                "freedBytes": result.freedBytes
            ]
        )
    }
    
    /// Evicts entries in batch if needed to make room for new data.
    ///
    /// This optimized version:
    /// 1. Calculates all entries to remove upfront
    /// 2. Deletes files in a single pass
    /// 3. Updates metadata once at the end
    ///
    /// - Parameter newSize: Size of new data being cached
    private func evictIfNeeded(forNewDataSize newSize: Int64) async {
        let targetSize = maxCacheSize - newSize
        
        guard metadata.totalSize > targetSize else { return }
        
        // Sort by last accessed time (oldest first) for LRU eviction
        let sortedEntries = metadata.entries.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        
        var keysToRemove: [String] = []
        var projectedSize = metadata.totalSize
        
        // Collect entries to remove without modifying state
        for entry in sortedEntries {
            if projectedSize <= targetSize { break }
            keysToRemove.append(entry.key)
            projectedSize -= entry.sizeBytes
        }
        
        // Early exit if nothing to remove
        guard !keysToRemove.isEmpty else { return }
        
        AppLogger.info(
            "Cache eviction starting",
            category: .data,
            context: [
                "entriesToRemove": keysToRemove.count,
                "currentSize": metadata.totalSize,
                "targetSize": targetSize
            ]
        )
        
        // Batch remove entries
        let result = await batchRemoveEntries(keys: keysToRemove)
        
        AppLogger.info(
            "Cache eviction complete",
            category: .data,
            context: [
                "removed": result.removedCount,
                "freedBytes": result.freedBytes,
                "newSize": metadata.totalSize
            ]
        )
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
