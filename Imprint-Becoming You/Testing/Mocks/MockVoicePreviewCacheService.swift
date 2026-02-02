//
//  MockVoicePreviewCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Mock Voice Preview Service

/// Mock implementation of voice preview service for previews and testing.
///
/// Simulates on-demand synthesis with a brief delay and returns minimal WAV data.
@MainActor
final class MockVoicePreviewCacheService: VoicePreviewCacheServiceProtocol {
    
    // MARK: - State
    
    private(set) var isSynthesizing: Bool = false
    
    /// Tracks if cancellation was requested
    private var isCancelled: Bool = false
    
    // MARK: - Synthesis
    
    func synthesizePreview(voiceId: String) async throws -> Data {
        isSynthesizing = true
        isCancelled = false
        
        // Simulate synthesis delay
        try await Task.sleep(for: .milliseconds(200))
        
        // Check for cancellation
        if isCancelled {
            isSynthesizing = false
            throw CancellationError()
        }
        
        isSynthesizing = false
        return createMinimalWAVData()
    }
    
    // MARK: - Cancellation
    
    func cancelSynthesis() {
        isCancelled = true
        isSynthesizing = false
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
