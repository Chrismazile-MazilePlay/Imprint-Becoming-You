//
//  VoicePreviewCacheServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Voice Preview Cache Service Protocol

/// Protocol for caching synthesized voice preview audio.
///
/// Provides persistent storage for voice preview clips to enable
/// instant playback in voice selection UI (onboarding and settings).
///
/// ## Lifecycle
/// 1. App launch: `startBackgroundSynthesis()` begins caching missing voices
/// 2. Voice selection UI: Check `isReady(_:)` before playback
/// 3. Playback: Use `getPreviewAudio(for:)` for cached audio, or `synthesizeNow(_:)` for on-demand
///
/// ## Storage
/// Previews are stored persistently in Application Support/VoicePreviewCache/
/// and survive app restarts. Cache is invalidated when:
/// - Preview phrase changes
/// - Cache version is bumped (new voices added)
///
/// ## Usage
/// ```swift
/// let cache = dependencies.voicePreviewCacheService
///
/// // Start background synthesis at app launch
/// await cache.startBackgroundSynthesis()
///
/// // In voice selection UI
/// if cache.isReady(voiceId) {
///     let audio = cache.getPreviewAudio(for: voiceId)
///     playAudio(audio)
/// } else {
///     showLoadingIndicator()
///     let audio = try await cache.synthesizeNow(voiceId)
///     playAudio(audio)
/// }
/// ```
@MainActor
protocol VoicePreviewCacheServiceProtocol: AnyObject {
    
    // MARK: - State
    
    /// Whether all voice previews are cached and ready
    var isComplete: Bool { get }
    
    /// Number of voices currently cached
    var cachedCount: Int { get }
    
    /// Total number of voices to cache
    var totalCount: Int { get }
    
    /// Progress of background synthesis (0.0 - 1.0)
    var synthesisProgress: Float { get }
    
    /// Whether background synthesis is currently running
    var isSynthesizing: Bool { get }
    
    // MARK: - Cache Access
    
    /// Check if a specific voice preview is cached and ready.
    ///
    /// - Parameter voiceId: The voice ID (raw format, e.g., "af_heart")
    /// - Returns: `true` if preview audio is available for immediate playback
    func isReady(_ voiceId: String) -> Bool
    
    /// Get cached audio data for a voice preview.
    ///
    /// - Parameter voiceId: The voice ID (raw format, e.g., "af_heart")
    /// - Returns: Audio data (WAV format) if cached, `nil` otherwise
    func getPreviewAudio(for voiceId: String) -> Data?
    
    // MARK: - Synthesis
    
    /// Start background synthesis of all missing voice previews.
    ///
    /// Call this at app launch. Synthesizes voices in priority order:
    /// 1. Default voice (af_heart)
    /// 2. American Female voices
    /// 3. American Male voices
    /// 4. British Female voices
    /// 5. British Male voices
    /// 6. System voice
    ///
    /// Safe to call multiple times - no-op if already complete or in progress.
    func startBackgroundSynthesis() async
    
    /// Synthesize a single voice preview immediately.
    ///
    /// Use when user taps a voice that isn't cached yet.
    /// The result is automatically added to the cache.
    ///
    /// - Parameter voiceId: The voice ID (raw format, e.g., "af_heart")
    /// - Returns: Audio data (WAV format)
    /// - Throws: `AppError.ttsError` if synthesis fails
    func synthesizeNow(_ voiceId: String) async throws -> Data
    
    // MARK: - Cache Management
    
    /// Clear all cached previews.
    ///
    /// Use during development or if cache becomes corrupted.
    func clearCache()
}
