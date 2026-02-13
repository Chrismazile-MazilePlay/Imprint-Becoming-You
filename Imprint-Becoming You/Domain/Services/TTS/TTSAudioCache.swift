//
//  TTSAudioCache.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/5/26.
//

import Foundation

// MARK: - TTS Audio Cache

/// In-memory cache for pre-synthesized TTS audio data keyed by affirmation UUID.
///
/// Keying by UUID (instead of positional index) means cached audio survives
/// shuffle reordering — the same affirmation resolves to the same audio
/// regardless of its position in the session.
///
/// ## Memory Profile
/// Kokoro outputs Float32 PCM at 24kHz — a 30s affirmation uses ~2.88MB,
/// a 60s affirmation ~5.76MB. A typical 7-affirmation session: ~20–40MB.
///
/// ## Thread Safety
/// All access is `@MainActor` isolated, matching `SessionTTSQueueService`.
@MainActor
final class TTSAudioCache {

    // MARK: - Storage

    /// Audio data keyed by affirmation UUID
    private var storage: [UUID: Data] = [:]

    // MARK: - Properties

    /// Number of cached audio entries
    var count: Int {
        storage.count
    }

    /// Total memory footprint in bytes of all cached audio data
    var memorySizeBytes: Int {
        storage.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Access

    /// Retrieves cached audio data for an affirmation.
    ///
    /// - Parameter id: The affirmation's unique identifier
    /// - Returns: Audio data if cached, `nil` if not yet synthesized
    func get(_ id: UUID) -> Data? {
        storage[id]
    }

    /// Maximum number of cached entries.
    ///
    /// Defensive cap well above the practical maximum (~20 for expanded spaced-rep sessions).
    /// Prevents runaway memory if session teardown is missed. At ~4MB per entry, 50 entries
    /// caps in-memory audio at ~200MB.
    private static let maxEntries = 50

    /// Stores audio data for an affirmation.
    ///
    /// Skips the insert if the cache is at capacity (defensive guard — not expected
    /// to fire in normal operation since session lifecycle clears the cache).
    ///
    /// - Parameters:
    ///   - id: The affirmation's unique identifier
    ///   - data: The synthesized audio data (PCM or WAV)
    func set(_ id: UUID, data: Data) {
        guard storage.count < Self.maxEntries else {
            #if DEBUG
            AppLogger.debug("TTSAudioCache at capacity (\(storage.count) entries), skipping insert", category: .tts)
            #endif
            return
        }
        storage[id] = data
    }

    /// Checks whether audio data exists for a given affirmation.
    ///
    /// - Parameter id: The affirmation's unique identifier
    /// - Returns: `true` if audio data is cached for this affirmation
    func contains(_ id: UUID) -> Bool {
        storage[id] != nil
    }

    /// Removes all cached audio data.
    ///
    /// Frees all memory held by cached PCM audio. Call on session end
    /// (`cancelAll`) or background memory release (`clearQueue`).
    func clear() {
        storage.removeAll()
    }

    // MARK: - Diagnostics

    /// Logs cache memory usage for debugging.
    ///
    /// Prints entry count and total byte size. Call at session start/end
    /// for visibility into cache memory consumption.
    func logMemoryUsage() {
        #if DEBUG
        let sizeMB = Double(memorySizeBytes) / (1024.0 * 1024.0)
        print("[TTSAudioCache] entries=\(count), size=\(String(format: "%.2f", sizeMB))MB")
        #endif
    }
}
