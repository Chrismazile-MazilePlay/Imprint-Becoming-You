//
//  AudioCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Audio Cache Service

/// Production implementation of audio caching service.
///
/// Provides disk-based caching for synthesized TTS audio files.
/// Wraps `AudioCacheManager` with the `AudioCacheServiceProtocol` interface.
///
/// ## Caching Strategy
/// - Key: Hash of (text + voiceId) for unique identification
/// - Storage: App's caches directory (can be cleared by system)
/// - Limit: 500MB maximum cache size
/// - Expiration: 30 days since last access
final class AudioCacheService: AudioCacheServiceProtocol, @unchecked Sendable {
    
    // MARK: - Dependencies
    
    private let cacheManager: AudioCacheManager
    
    // MARK: - Initialization
    
    /// Creates a new audio cache service with the shared cache manager
    init() {
        self.cacheManager = AudioCacheManager.shared
    }
    
    /// Creates an audio cache service with an injected cache manager (for testing)
    /// - Parameter cacheManager: The cache manager to use
    init(cacheManager: AudioCacheManager) {
        self.cacheManager = cacheManager
    }
    
    // MARK: - AudioCacheServiceProtocol
    
    var maxCacheSize: Int64 {
        cacheManager.maxCacheSize
    }
    
    var cacheSize: Int64 {
        get async {
            await cacheManager.cacheSize
        }
    }
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        await cacheManager.getCachedAudio(forText: text, voiceId: voiceId)
    }
    
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        try await cacheManager.cacheAudio(data, forText: text, voiceId: voiceId)
    }
    
    func removeCachedAudio(fileName: String) async {
        await cacheManager.removeCachedAudio(fileName: fileName)
    }
    
    func clearCache() async {
        await cacheManager.clearCache()
    }
}
