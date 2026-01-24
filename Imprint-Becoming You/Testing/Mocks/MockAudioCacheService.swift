//
//  MockAudioCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Audio Cache Service

/// Mock implementation of AudioCacheServiceProtocol for testing and previews.
actor MockAudioCacheService: AudioCacheServiceProtocol {
    
    // MARK: - Properties
    
    private var cache: [String: TTSResult] = [:]
    
    /// Maximum cache size - nonisolated for protocol conformance
    nonisolated(unsafe) private(set) var maxSize: Int64 = AudioCacheConfiguration.defaultMaxSize
    
    private var hitCount: Int = 0
    private var missCount: Int = 0
    
    // Test hooks
    var shouldFailOnStore: Bool = false
    var storeDelay: TimeInterval = 0
    
    // MARK: - Protocol Properties
    
    var currentSize: Int64 {
        get async {
            Int64(cache.values.reduce(0) { $0 + $1.audioData.count })
        }
    }
    
    var itemCount: Int {
        get async { cache.count }
    }
    
    // MARK: - Cache Key
    
    nonisolated func cacheKey(for text: String, voice: Voice, speed: Float) -> String {
        "\(text.hashValue)_\(voice.id)_\(speed)"
    }
    
    // MARK: - Cache Operations
    
    func get(key: String) async -> TTSResult? {
        if let result = cache[key] {
            hitCount += 1
            return result
        }
        missCount += 1
        return nil
    }
    
    @discardableResult
    func store(key: String, result: TTSResult) async throws -> String {
        if shouldFailOnStore {
            throw TTSError.audioEncodingError(message: "Mock store failure")
        }
        
        if storeDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(storeDelay * 1_000_000_000))
        }
        
        cache[key] = result
        return "\(key).mp3"
    }
    
    func remove(key: String) async {
        cache.removeValue(forKey: key)
    }
    
    func clearAll() async {
        cache.removeAll()
        hitCount = 0
        missCount = 0
    }
    
    // MARK: - Pre-generation
    
    func pregenerate(
        texts: [String],
        voice: Voice,
        speed: Float,
        using synthesizer: TTSServiceProtocol
    ) async {
        for text in texts {
            let key = cacheKey(for: text, voice: voice, speed: speed)
            if cache[key] == nil {
                if let result = try? await synthesizer.synthesize(text: text, voice: voice, speed: speed) {
                    cache[key] = result
                }
            }
        }
    }
    
    func cancelPregeneration() async {
        // No-op for mock
    }
    
    // MARK: - Cache Management
    
    func setMaxSize(_ bytes: Int64) async {
        maxSize = bytes
    }
    
    func statistics() async -> AudioCacheStatistics {
        AudioCacheStatistics(
            totalSize: await currentSize,
            maxSize: maxSize,
            itemCount: cache.count,
            hitCount: hitCount,
            missCount: missCount,
            oldestEntry: nil,
            newestEntry: nil
        )
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        cache.removeAll()
        hitCount = 0
        missCount = 0
        shouldFailOnStore = false
        storeDelay = 0
    }
    
    func seedCache(with results: [String: TTSResult]) {
        for (key, result) in results {
            cache[key] = result
        }
    }
}
