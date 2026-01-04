//
//  MockAudioCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Audio Cache Service

/// Mock implementation of audio cache service for previews and testing.
///
/// Simulates audio caching without actual file system operations.
final class MockAudioCacheService: AudioCacheServiceProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Maximum cache size (from Constants)
    var maxCacheSize: Int64 = Constants.Cache.maxAudioCacheSize
    
    /// Simulated current cache size
    var simulatedCacheSize: Int64 = 0
    
    /// In-memory cache for testing
    private var cache: [String: Data] = [:]
    
    // MARK: - AudioCacheServiceProtocol
    
    var cacheSize: Int64 {
        get async { simulatedCacheSize }
    }
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        let key = "\(text)-\(voiceId)"
        return cache[key]
    }
    
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        let key = "\(text)-\(voiceId)"
        cache[key] = data
        simulatedCacheSize += Int64(data.count)
        return "cached-\(UUID().uuidString).mp3"
    }
    
    func removeCachedAudio(fileName: String) async {
        // No-op for mock - we don't track by filename
    }
    
    func clearCache() async {
        cache.removeAll()
        simulatedCacheSize = 0
    }
}
