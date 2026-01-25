//
//  MockAudioCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Audio Cache Service

/// Mock implementation of AudioCacheServiceProtocol for testing.
actor MockAudioCacheService: AudioCacheServiceProtocol {
    
    // MARK: - Properties
    
    private var cache: [String: Data] = [:]
    private var sizes: [String: Int64] = [:]
    private var _cacheSize: Int64 = 0
    
    let maxCacheSize: Int64 = 100 * 1024 * 1024
    
    // MARK: - Test Hooks
    
    var cacheError: Error?
    private(set) var getCacheCallCount: Int = 0
    private(set) var cacheCallCount: Int = 0
    
    // MARK: - AudioCacheServiceProtocol
    
    var cacheSize: Int64 {
        get async { _cacheSize }
    }
    
    func getCachedAudio(forText text: String, voiceId: String) async -> Data? {
        getCacheCallCount += 1
        let key = cacheKey(for: text, voiceId: voiceId)
        return cache[key]
    }
    
    @discardableResult
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String {
        if let error = cacheError {
            throw error
        }
        
        cacheCallCount += 1
        let key = cacheKey(for: text, voiceId: voiceId)
        
        if let existingSize = sizes[key] {
            _cacheSize -= existingSize
        }
        
        cache[key] = data
        sizes[key] = Int64(data.count)
        _cacheSize += Int64(data.count)
        
        return "\(key).wav"
    }
    
    func removeCachedAudio(fileName: String) async {
        let key = fileName.replacingOccurrences(of: ".wav", with: "")
            .replacingOccurrences(of: ".mp3", with: "")
        
        if let size = sizes[key] {
            _cacheSize -= size
        }
        cache.removeValue(forKey: key)
        sizes.removeValue(forKey: key)
    }
    
    func clearCache() async {
        cache.removeAll()
        sizes.removeAll()
        _cacheSize = 0
    }
    
    // MARK: - Private
    
    private func cacheKey(for text: String, voiceId: String) -> String {
        "\(text.hashValue)_\(voiceId)"
    }
    
    // MARK: - Test Helpers
    
    func reset() async {
        cache.removeAll()
        sizes.removeAll()
        _cacheSize = 0
        getCacheCallCount = 0
        cacheCallCount = 0
        cacheError = nil
    }
}
