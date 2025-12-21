//
//  AudioCacheManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import CryptoKit

// MARK: - AudioCacheManager

/// Manages cached audio files for TTS playback.
///
/// Implements LRU (Least Recently Used) eviction when the cache exceeds
/// the maximum size limit. Audio files are stored with content-based
/// hashing to avoid duplicates.
///
/// ## Cache Policy
/// - Maximum size: 500 MB
/// - Expiration: 30 days
/// - Eviction: LRU when size limit exceeded
///
/// ## Usage
/// ```swift
/// let cache = AudioCacheManager.shared
/// let fileName = try await cache.cacheAudio(data, forText: "I am confident", voiceId: "abc123")
/// let data = await cache.getCachedAudio(forText: "I am confident", voiceId: "abc123")
/// ```
actor AudioCacheManager: AudioCacheServiceProtocol {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide cache management
    static let shared = AudioCacheManager()
    
    // MARK: - Properties
    
    /// File manager for file operations
    private let fileManager = FileManager.default
    
    /// Cache directory URL
    private let cacheDirectory: URL
    
    /// Metadata file URL
    private let metadataURL: URL
    
    /// Cache metadata (maps cache keys to file info)
    private var metadata: CacheMetadata
    
    /// Maximum cache size in bytes
    let maxCacheSize: Int64 = Constants.Cache.maxAudioCacheSize
    
    /// Current cache size in bytes
    var cacheSize: Int64 {
        get async {
            metadata.totalSize
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Setup cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent(Constants.Cache.audioCacheDirectory, isDirectory: true)
        metadataURL = cacheDirectory.appendingPathComponent("metadata.json")
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Load existing metadata
        metadata = CacheMetadata.load(from: metadataURL) ?? CacheMetadata()
        
        // Clean expired entries on startup
        Task {
            await cleanExpiredEntries()
        }
    }
    
    // MARK: - Public Methods
    
    /// Retrieves cached audio for the given text and voice
    /// - Parameters:
    ///   - text: The affirmation text
    ///   - voiceId: The voice identifier
    /// - Returns: Audio data if cached and not expired, nil otherwise
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        let key = cacheKey(forText: text, voiceId: voiceId)
        
        guard let entry = metadata.entries[key],
              !entry.isExpired else {
            // Remove expired entry if exists
            if metadata.entries[key] != nil {
                await removeEntry(forKey: key)
            }
            return nil
        }
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // File missing - remove metadata entry
            await removeEntry(forKey: key)
            return nil
        }
        
        // Update last accessed time
        metadata.entries[key]?.lastAccessedAt = Date()
        await saveMetadata()
        
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            print("⚠️ Failed to read cached audio: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Caches audio data for the given text and voice
    /// - Parameters:
    ///   - data: The audio data to cache
    ///   - text: The affirmation text
    ///   - voiceId: The voice identifier
    /// - Returns: The filename of the cached file
    @discardableResult
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        let key = cacheKey(forText: text, voiceId: voiceId)
        let fileName = "\(key).mp3"
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        // Check if we need to evict to make room
        let dataSize = Int64(data.count)
        await evictIfNeeded(forNewDataSize: dataSize)
        
        // Write file
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.cacheError(reason: "Failed to write audio file: \(error.localizedDescription)")
        }
        
        // Create metadata entry
        let expirationDate = Date().addingTimeInterval(
            TimeInterval(Constants.Cache.expirationDays * 24 * 60 * 60)
        )
        
        let entry = CacheEntry(
            key: key,
            fileName: fileName,
            size: dataSize,
            createdAt: Date(),
            lastAccessedAt: Date(),
            expiresAt: expirationDate,
            text: text,
            voiceId: voiceId
        )
        
        metadata.entries[key] = entry
        metadata.totalSize += dataSize
        
        await saveMetadata()
        
        return fileName
    }
    
    /// Removes a cached audio file
    /// - Parameter fileName: The filename to remove
    func removeCachedAudio(fileName: String) async {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        // Find and remove metadata entry
        if let entry = metadata.entries.first(where: { $0.value.fileName == fileName }) {
            metadata.entries.removeValue(forKey: entry.key)
            metadata.totalSize -= entry.value.size
        }
        
        // Delete file
        try? fileManager.removeItem(at: fileURL)
        
        await saveMetadata()
    }
    
    /// Clears the entire cache
    func clearCache() async {
        // Remove all files
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent != "metadata.json" {
                try? fileManager.removeItem(at: file)
            }
        }
        
        // Reset metadata
        metadata = CacheMetadata()
        await saveMetadata()
    }
    
    /// Gets the file URL for a cached audio file
    /// - Parameter fileName: The filename
    /// - Returns: URL to the file, or nil if not found
    func fileURL(forFileName fileName: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Checks if audio is cached for the given text and voice
    /// - Parameters:
    ///   - text: The affirmation text
    ///   - voiceId: The voice identifier
    /// - Returns: True if cached and not expired
    func isCached(forText text: String, voiceId: String) -> Bool {
        let key = cacheKey(forText: text, voiceId: voiceId)
        guard let entry = metadata.entries[key] else { return false }
        return !entry.isExpired
    }
    
    // MARK: - Private Methods
    
    /// Generates a cache key from text and voice ID
    private func cacheKey(forText text: String, voiceId: String) -> String {
        let combined = "\(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(voiceId)"
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }
    
    /// Removes an entry from the cache
    private func removeEntry(forKey key: String) async {
        guard let entry = metadata.entries.removeValue(forKey: key) else { return }
        
        metadata.totalSize -= entry.size
        
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        
        await saveMetadata()
    }
    
    /// Cleans expired entries from the cache
    private func cleanExpiredEntries() async {
        let expiredKeys = metadata.entries
            .filter { $0.value.isExpired }
            .map { $0.key }
        
        for key in expiredKeys {
            await removeEntry(forKey: key)
        }
    }
    
    /// Evicts entries if needed to make room for new data
    private func evictIfNeeded(forNewDataSize newSize: Int64) async {
        var targetSize = maxCacheSize - newSize
        
        guard metadata.totalSize > targetSize else { return }
        
        // Sort by last accessed time (oldest first)
        let sortedEntries = metadata.entries.values
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }
        
        for entry in sortedEntries {
            if metadata.totalSize <= targetSize {
                break
            }
            await removeEntry(forKey: entry.key)
        }
    }
    
    /// Saves metadata to disk
    private func saveMetadata() async {
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("⚠️ Failed to save cache metadata: \(error.localizedDescription)")
        }
    }
}

// MARK: - CacheMetadata

/// Metadata for the audio cache
private struct CacheMetadata: Codable {
    /// Cache entries indexed by key
    var entries: [String: CacheEntry] = [:]
    
    /// Total size of all cached files
    var totalSize: Int64 = 0
    
    /// Last cleanup date
    var lastCleanupAt: Date?
    
    /// Loads metadata from a file
    static func load(from url: URL) -> CacheMetadata? {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }
}

// MARK: - CacheEntry

/// Individual cache entry metadata
private struct CacheEntry: Codable {
    /// Unique key for this entry
    let key: String
    
    /// Filename on disk
    let fileName: String
    
    /// File size in bytes
    let size: Int64
    
    /// When the entry was created
    let createdAt: Date
    
    /// When the entry was last accessed
    var lastAccessedAt: Date
    
    /// When the entry expires
    let expiresAt: Date
    
    /// Original affirmation text
    let text: String
    
    /// Voice ID used for synthesis
    let voiceId: String
    
    /// Whether this entry has expired
    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Cache Statistics

extension AudioCacheManager {
    
    /// Returns cache statistics for debugging/settings display
    func getStatistics() async -> CacheStatistics {
        CacheStatistics(
            totalSize: metadata.totalSize,
            maxSize: maxCacheSize,
            entryCount: metadata.entries.count,
            oldestEntry: metadata.entries.values.min(by: { $0.createdAt < $1.createdAt })?.createdAt,
            newestEntry: metadata.entries.values.max(by: { $0.createdAt < $1.createdAt })?.createdAt
        )
    }
}

/// Cache statistics for display
struct CacheStatistics: Sendable {
    let totalSize: Int64
    let maxSize: Int64
    let entryCount: Int
    let oldestEntry: Date?
    let newestEntry: Date?
    
    /// Formatted total size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Formatted max size
    var formattedMaxSize: String {
        ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
    }
    
    /// Usage percentage (0.0 - 1.0)
    var usagePercentage: Double {
        guard maxSize > 0 else { return 0 }
        return Double(totalSize) / Double(maxSize)
    }
}
