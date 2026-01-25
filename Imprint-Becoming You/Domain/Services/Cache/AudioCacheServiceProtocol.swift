//
//  AudioCacheServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Audio Cache Service Protocol

/// Protocol for managing cached TTS audio files.
///
/// Provides disk-based caching for synthesized audio to reduce synthesis calls
/// and enable offline playback of previously heard content.
///
/// ## Usage
/// ```swift
/// let cache: AudioCacheServiceProtocol = AudioCacheManager.shared
///
/// // Check for cached audio
/// if let data = await cache.getCachedAudio(forText: "Hello", voiceId: "kokoro_afHeart") {
///     // Play cached audio
/// } else {
///     // Synthesize and cache
///     let data = try await tts.synthesize(text: "Hello", voiceId: "kokoro_afHeart")
///     try await cache.cacheAudio(data, forText: "Hello", voiceId: "kokoro_afHeart")
/// }
/// ```
protocol AudioCacheServiceProtocol: AnyObject, Sendable {
    
    /// Retrieves cached audio data for the given text and voice combination.
    /// - Parameters:
    ///   - text: The original text that was synthesized
    ///   - voiceId: The voice ID used for synthesis
    /// - Returns: Cached audio data if available, nil otherwise
    func getCachedAudio(forText text: String, voiceId: String) async -> Data?
    
    /// Caches audio data for later retrieval.
    /// - Parameters:
    ///   - data: The audio data to cache
    ///   - text: The original text that was synthesized
    ///   - voiceId: The voice ID used for synthesis
    /// - Returns: The filename of the cached file
    /// - Throws: Cache errors if storage fails
    @discardableResult
    func cacheAudio(_ data: Data, forText text: String, voiceId: String) async throws -> String
    
    /// Removes a specific cached audio file.
    /// - Parameter fileName: The name of the file to remove
    func removeCachedAudio(fileName: String) async
    
    /// Clears all cached audio files.
    func clearCache() async
    
    /// Current total size of cached audio in bytes.
    var cacheSize: Int64 { get async }
    
    /// Maximum allowed cache size in bytes.
    var maxCacheSize: Int64 { get }
}
