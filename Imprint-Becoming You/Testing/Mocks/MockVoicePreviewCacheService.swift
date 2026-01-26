//
//  MockVoicePreviewCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Mock Voice Preview Cache Service

/// Mock implementation of voice preview cache for previews and testing.
///
/// Returns immediately with fake audio data, simulating a fully cached state.
@MainActor
final class MockVoicePreviewCacheService: VoicePreviewCacheServiceProtocol {
    
    // MARK: - State
    
    var isComplete: Bool = true
    var cachedCount: Int = 28
    var totalCount: Int = 28
    var synthesisProgress: Float = 1.0
    var isSynthesizing: Bool = false
    
    // MARK: - Cache Access
    
    func isReady(_ voiceId: String) -> Bool {
        true
    }
    
    func getPreviewAudio(for voiceId: String) -> Data? {
        // Return minimal valid WAV data
        createMinimalWAVData()
    }
    
    // MARK: - Synthesis
    
    func startBackgroundSynthesis() async {
        // No-op for mock
    }
    
    func synthesizeNow(_ voiceId: String) async throws -> Data {
        // Simulate brief delay
        try? await Task.sleep(for: .milliseconds(100))
        return createMinimalWAVData()
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        // No-op for mock
    }
    
    // MARK: - Private
    
    private func createMinimalWAVData() -> Data {
        // Create a minimal valid WAV header with silence
        var data = Data()
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // Mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(24000).littleEndian) { Array($0) }) // Sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(48000).littleEndian) { Array($0) }) // Byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) }) // Block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // Bits per sample
        
        // data chunk (empty)
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Array($0) })
        
        return data
    }
}
