//
//  AudioCacheServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation
import CryptoKit

// MARK: - Audio Cache Service Protocol

/// Protocol for caching synthesized TTS audio.
///
/// ## Cache Strategy
/// - **Key**: SHA256(text + voice.id + speed)
/// - **Storage**: Caches directory (system can purge)
/// - **Limit**: 500MB default, LRU eviction
/// - **Expiration**: 30 days since last access
///
/// ## Usage
/// ```swift
/// let key = cache.cacheKey(for: text, voice: voice, speed: 1.0)
///
/// // Check cache first
/// if let result = await cache.get(key: key) {
///     return result
/// }
///
/// // Synthesize and cache
/// let result = try await ttsService.synthesize(text: text, voice: voice)
/// try await cache.store(key: key, result: result)
/// ```
protocol AudioCacheServiceProtocol: AnyObject, Sendable {
    
    // MARK: - Cache Operations
    
    /// Generates a unique cache key for the given parameters.
    func cacheKey(for text: String, voice: Voice, speed: Float) -> String
    
    /// Retrieves a cached TTS result.
    func get(key: String) async -> TTSResult?
    
    /// Stores a TTS result in the cache.
    @discardableResult
    func store(key: String, result: TTSResult) async throws -> String
    
    /// Removes a cached entry.
    func remove(key: String) async
    
    /// Clears all cached audio.
    func clearAll() async
    
    // MARK: - Pre-generation
    
    /// Pre-generates audio for multiple texts (background processing).
    func pregenerate(
        texts: [String],
        voice: Voice,
        speed: Float,
        using synthesizer: TTSServiceProtocol
    ) async
    
    /// Cancels ongoing pre-generation.
    func cancelPregeneration() async
    
    // MARK: - Cache Info
    
    /// Current cache size in bytes.
    var currentSize: Int64 { get async }
    
    /// Maximum cache size in bytes.
    var maxSize: Int64 { get }
    
    /// Number of cached items.
    var itemCount: Int { get async }
    
    /// Sets maximum cache size (triggers eviction if needed).
    func setMaxSize(_ bytes: Int64) async
    
    /// Cache statistics for debugging/settings.
    func statistics() async -> AudioCacheStatistics
}

// MARK: - Default Cache Key Implementation

extension AudioCacheServiceProtocol {
    
    func cacheKey(for text: String, voice: Voice, speed: Float) -> String {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(normalized)|\(voice.id)|\(speed)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }
    
    /// Convenience: check if cached
    func isCached(text: String, voice: Voice, speed: Float) async -> Bool {
        let key = cacheKey(for: text, voice: voice, speed: speed)
        return await get(key: key) != nil
    }
}

// MARK: - Audio Cache Statistics

struct AudioCacheStatistics: Sendable {
    let totalSize: Int64
    let maxSize: Int64
    let itemCount: Int
    let hitCount: Int
    let missCount: Int
    let oldestEntry: Date?
    let newestEntry: Date?
    
    var usagePercentage: Double {
        guard maxSize > 0 else { return 0 }
        return Double(totalSize) / Double(maxSize)
    }
    
    var hitRate: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedMaxSize: String {
        ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
    }
    
    static let empty = AudioCacheStatistics(
        totalSize: 0,
        maxSize: AudioCacheConfiguration.defaultMaxSize,
        itemCount: 0,
        hitCount: 0,
        missCount: 0,
        oldestEntry: nil,
        newestEntry: nil
    )
}

// MARK: - Audio Cache Configuration

enum AudioCacheConfiguration {
    static let defaultMaxSize: Int64 = 500 * 1024 * 1024  // 500 MB
    static let minimumSize: Int64 = 50 * 1024 * 1024      // 50 MB
    static let maximumSize: Int64 = 2 * 1024 * 1024 * 1024 // 2 GB
    static let expirationDays = 30
    static let directoryName = "TTSAudioCache"
    static let metadataFileName = "cache_metadata.json"
    
    static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent(directoryName, isDirectory: true)
    }
}

// MARK: - Cache Entry Metadata

/// Internal metadata for cache entries.
struct AudioCacheEntry: Codable, Sendable {
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
