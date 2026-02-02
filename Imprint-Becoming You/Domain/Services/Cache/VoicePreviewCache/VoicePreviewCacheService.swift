//
//  VoicePreviewCacheService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/25/26.
//

import Foundation

// MARK: - Voice Preview Service

/// Production implementation of on-demand voice preview synthesis.
///
/// Synthesizes voice preview audio clips on-demand for the voice selection UI.
/// No caching is performed - each tap triggers a fresh synthesis.
///
/// ## Features
/// - **On-demand synthesis:** Fresh audio generated for each request
/// - **Cancellation support:** In-flight synthesis can be cancelled
/// - **Auto-retry:** Automatically retries once on failure
/// - **Task management:** Only one synthesis runs at a time
@MainActor
final class VoicePreviewCacheService: VoicePreviewCacheServiceProtocol {
    
    // MARK: - Properties
    
    /// TTS service for synthesis
    private let ttsService: any TTSServiceProtocol
    
    /// Current synthesis task (for cancellation)
    private var currentSynthesisTask: Task<Data, Error>?
    
    // MARK: - State
    
    private(set) var isSynthesizing: Bool = false
    
    // MARK: - Initialization
    
    init(ttsService: any TTSServiceProtocol) {
        self.ttsService = ttsService
        
        #if DEBUG
        print("🎤 VoicePreviewService: Initialized (on-demand synthesis)")
        #endif
    }
    
    // MARK: - Synthesis
    
    func synthesizePreview(voiceId: String) async throws -> Data {
        isSynthesizing = true
        
        #if DEBUG
        print("🎤 VoicePreviewService: Synthesizing \(voiceId)...")
        let startTime = Date()
        #endif
        
        // Create the synthesis task
        let task = Task<Data, Error> {
            try await synthesizeWithRetry(voiceId: voiceId)
        }
        
        currentSynthesisTask = task
        
        do {
            let audioData = try await task.value
            
            #if DEBUG
            let elapsed = Date().timeIntervalSince(startTime)
            print("🎤 VoicePreviewService: Synthesized \(voiceId) (\(audioData.count) bytes) in \(String(format: "%.2f", elapsed))s")
            #endif
            
            isSynthesizing = false
            currentSynthesisTask = nil
            return audioData
            
        } catch {
            isSynthesizing = false
            currentSynthesisTask = nil
            
            // Don't log cancellation as error
            if Task.isCancelled || error is CancellationError {
                #if DEBUG
                print("🎤 VoicePreviewService: Synthesis cancelled for \(voiceId)")
                #endif
                throw CancellationError()
            }
            
            #if DEBUG
            print("⚠️ VoicePreviewService: Synthesis failed for \(voiceId): \(error)")
            #endif
            throw error
        }
    }
    
    // MARK: - Cancellation
    
    func cancelSynthesis() {
        guard let task = currentSynthesisTask else { return }
        
        #if DEBUG
        print("🎤 VoicePreviewService: Cancelling in-flight synthesis")
        #endif
        
        task.cancel()
        currentSynthesisTask = nil
        isSynthesizing = false
    }
    
    // MARK: - Private Methods
    
    /// Synthesize with automatic retry on failure.
    ///
    /// Attempts synthesis once, and if it fails, retries one more time.
    /// - Parameter voiceId: The raw voice ID (e.g., "af_heart")
    /// - Returns: Audio data (WAV format)
    /// - Throws: Error if both attempts fail
    private func synthesizeWithRetry(voiceId: String) async throws -> Data {
        // Check for cancellation before starting
        try Task.checkCancellation()
        
        do {
            // First attempt
            return try await ttsService.synthesize(text: Voice.previewPhrase, voiceId: voiceId)
            
        } catch {
            // Check if cancelled before retry
            try Task.checkCancellation()
            
            // Don't retry cancellation errors
            if error is CancellationError {
                throw error
            }
            
            #if DEBUG
            print("🎤 VoicePreviewService: First attempt failed, retrying...")
            #endif
            
            // Brief delay before retry
            try await Task.sleep(for: .milliseconds(100))
            
            // Check for cancellation after delay
            try Task.checkCancellation()
            
            // Retry once
            return try await ttsService.synthesize(text: Voice.previewPhrase, voiceId: voiceId)
        }
    }
}
