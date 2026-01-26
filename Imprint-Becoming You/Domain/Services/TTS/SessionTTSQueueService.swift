//
//  SessionTTSQueueService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import Foundation
import AVFoundation

// MARK: - Session TTS Queue Service

/// Production implementation of the session TTS pre-synthesis queue.
///
/// Manages background synthesis of affirmations to eliminate TTS loading delays.
/// Uses a priority-based queue system that adapts to user navigation patterns.
///
/// ## Thread Safety
/// All state is `@MainActor` isolated. Synthesis happens on background threads
/// via the TTS service, but results are cached on the main actor.
///
/// ## Memory Management
/// Audio data is stored in memory for the session duration (~500KB × 10 = ~5MB).
/// Cache is cleared when `cancelAll()` is called at session end.
///
/// ## Queue Priority
/// The queue prioritizes synthesis based on likely playback order:
/// 1. Current index (if not cached)
/// 2. Next indices (currentIndex + 1, + 2, ...)
/// 3. Previous indices (for back navigation)
@MainActor
final class SessionTTSQueueService: SessionTTSQueueServiceProtocol {
    
    // MARK: - Dependencies
    
    /// TTS service for audio synthesis
    private let ttsService: any TTSServiceProtocol
    
    // MARK: - State
    
    /// Cached audio data keyed by session index
    private var audioCache: [Int: Data] = [:]
    
    /// Affirmation info for the current session
    private var sessionAffirmations: [SessionAffirmationInfo] = []
    
    /// Voice ID for current session
    private var currentVoiceId: String?
    
    /// Current queue state
    private var state: SessionTTSQueueState = .idle
    
    /// Active background synthesis task
    private var backgroundTask: Task<Void, Never>?
    
    /// Set of indices currently being synthesized
    private var synthesizingIndices: Set<Int> = []
    
    /// Current playback index (for priority calculation)
    private var currentPlaybackIndex: Int = 0
    
    /// Target for initial preparation
    private var _preparationTarget: Int = 0
    
    // MARK: - Protocol Properties
    
    var isPreparing: Bool {
        if case .preparingInitial = state { return true }
        return false
    }
    
    var preparedCount: Int {
        audioCache.count
    }
    
    var preparationTarget: Int {
        _preparationTarget
    }
    
    var preparationProgress: Float {
        guard _preparationTarget > 0 else { return 0 }
        return Float(min(preparedCount, _preparationTarget)) / Float(_preparationTarget)
    }
    
    var isInitialPreparationComplete: Bool {
        preparedCount >= _preparationTarget || state == .complete
    }
    
    // MARK: - Initialization
    
    /// Creates a queue service with the given TTS service.
    ///
    /// - Parameter ttsService: The TTS service to use for synthesis
    init(ttsService: any TTSServiceProtocol) {
        self.ttsService = ttsService
    }
    
    // MARK: - Session Lifecycle
    
    func prepareSession(
        affirmations: [SessionAffirmationInfo],
        voiceId: String?,
        initialCount: Int
    ) async throws {
        #if DEBUG
        print("🎵 SessionTTSQueue: Preparing session with \(affirmations.count) affirmations, voice: \(voiceId ?? "default")")
        #endif
        
        // Cancel any existing session
        cancelAll()
        
        // Store session info
        sessionAffirmations = affirmations
        currentVoiceId = voiceId
        currentPlaybackIndex = 0
        
        guard !affirmations.isEmpty else {
            state = .complete
            _preparationTarget = 0
            return
        }
        
        // Calculate how many to prepare initially
        let initialTarget = min(initialCount, affirmations.count)
        _preparationTarget = initialTarget
        state = .preparingInitial(prepared: 0, total: initialTarget)
        
        // Synthesize initial affirmations sequentially
        for index in 0..<initialTarget {
            // Check for cancellation
            guard state != .cancelled else {
                #if DEBUG
                print("🎵 SessionTTSQueue: Preparation cancelled")
                #endif
                return
            }
            
            do {
                let info = affirmations[index]
                let audioData = try await synthesizeAffirmation(info)
                audioCache[index] = audioData
                
                state = .preparingInitial(prepared: index + 1, total: initialTarget)
                
                #if DEBUG
                print("🎵 SessionTTSQueue: Prepared \(index + 1)/\(initialTarget)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ SessionTTSQueue: Failed to synthesize index \(index): \(error)")
                #endif
                // Continue with next - don't fail entire preparation
            }
        }
        
        #if DEBUG
        print("✅ SessionTTSQueue: Initial preparation complete (\(preparedCount)/\(initialTarget))")
        #endif
        
        // Start background synthesis for remaining affirmations
        if affirmations.count > initialTarget {
            state = .synthesizingBackground(prepared: preparedCount, total: affirmations.count)
            startBackgroundSynthesis(startingFrom: initialTarget)
        } else {
            state = .complete
        }
    }
    
    func getAudio(for index: Int) -> Data? {
        audioCache[index]
    }
    
    func isReady(_ index: Int) -> Bool {
        audioCache[index] != nil
    }
    
    func notifyPlaying(index: Int) {
        #if DEBUG
        print("🎵 SessionTTSQueue: Now playing index \(index)")
        #endif
        
        currentPlaybackIndex = index
        
        // Reprioritize background synthesis if needed
        reprioritizeQueue(from: index)
    }
    
    func synthesizeOnDemand(index: Int) async throws -> Data {
        // Return cached if available
        if let cached = audioCache[index] {
            return cached
        }
        
        guard sessionAffirmations.indices.contains(index) else {
            throw AppError.ttsError("Invalid affirmation index: \(index)")
        }
        
        #if DEBUG
        print("🎵 SessionTTSQueue: On-demand synthesis for index \(index)")
        #endif
        
        let info = sessionAffirmations[index]
        let audioData = try await synthesizeAffirmation(info)
        audioCache[index] = audioData
        
        return audioData
    }
    
    func cancelAll() {
        #if DEBUG
        print("🎵 SessionTTSQueue: Cancelling all")
        #endif
        
        // Mark as cancelled first to stop any in-progress work
        state = .cancelled
        
        // Cancel background task
        backgroundTask?.cancel()
        backgroundTask = nil
        
        // Clear all state
        audioCache.removeAll()
        sessionAffirmations.removeAll()
        synthesizingIndices.removeAll()
        currentVoiceId = nil
        currentPlaybackIndex = 0
        _preparationTarget = 0
        
        // Reset to idle
        state = .idle
    }
    
    // MARK: - Private Methods
    
    /// Synthesizes a single affirmation using the TTS service.
    private func synthesizeAffirmation(_ info: SessionAffirmationInfo) async throws -> Data {
        synthesizingIndices.insert(info.index)
        defer { synthesizingIndices.remove(info.index) }
        
        return try await ttsService.synthesize(text: info.text, voiceId: currentVoiceId)
    }
    
    /// Starts background synthesis of remaining affirmations.
    private func startBackgroundSynthesis(startingFrom startIndex: Int) {
        backgroundTask?.cancel()
        
        backgroundTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Build priority queue based on current playback position
            let indices = self.buildPriorityQueue(from: startIndex)
            
            for index in indices {
                // Check for cancellation
                guard !Task.isCancelled else { return }
                guard self.state != .cancelled else { return }
                
                // Skip if already cached
                guard self.audioCache[index] == nil else { continue }
                
                // Skip if already being synthesized
                guard !self.synthesizingIndices.contains(index) else { continue }
                
                do {
                    let info = self.sessionAffirmations[index]
                    let audioData = try await self.synthesizeAffirmation(info)
                    
                    // Check cancellation again before caching
                    guard !Task.isCancelled else { return }
                    guard self.state != .cancelled else { return }
                    
                    self.audioCache[index] = audioData
                    
                    // Update state
                    self.state = .synthesizingBackground(
                        prepared: self.preparedCount,
                        total: self.sessionAffirmations.count
                    )
                    
                    #if DEBUG
                    print("🎵 SessionTTSQueue: Background synthesized index \(index) (\(self.preparedCount)/\(self.sessionAffirmations.count))")
                    #endif
                    
                } catch {
                    #if DEBUG
                    print("⚠️ SessionTTSQueue: Background synthesis failed for index \(index): \(error)")
                    #endif
                    // Continue with next
                }
                
                // Small delay to avoid overwhelming the system
                try? await Task.sleep(for: .milliseconds(50))
            }
            
            // All done
            if !Task.isCancelled && self.state != .cancelled {
                self.state = .complete
                
                #if DEBUG
                print("✅ SessionTTSQueue: Background synthesis complete (\(self.preparedCount)/\(self.sessionAffirmations.count))")
                #endif
            }
        }
    }
    
    /// Builds a priority-ordered list of indices to synthesize.
    ///
    /// Priority order:
    /// 1. Indices after current playback (most likely to be needed)
    /// 2. Indices before current playback (for back navigation)
    private func buildPriorityQueue(from startIndex: Int) -> [Int] {
        var queue: [Int] = []
        let total = sessionAffirmations.count
        
        // Forward indices first (most likely needed)
        for i in max(startIndex, currentPlaybackIndex)..<total {
            if audioCache[i] == nil {
                queue.append(i)
            }
        }
        
        // Then backward indices (less likely but possible)
        for i in stride(from: currentPlaybackIndex - 1, through: 0, by: -1) {
            if audioCache[i] == nil && !queue.contains(i) {
                queue.append(i)
            }
        }
        
        return queue
    }
    
    /// Reprioritizes the background queue when playback position changes.
    private func reprioritizeQueue(from newIndex: Int) {
        // Only restart if we're still doing background synthesis
        guard case .synthesizingBackground = state else { return }
        
        // If user jumped forward past synthesized content, restart from new position
        let nextNeededIndex = newIndex + 1
        if nextNeededIndex < sessionAffirmations.count && audioCache[nextNeededIndex] == nil {
            startBackgroundSynthesis(startingFrom: nextNeededIndex)
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension SessionTTSQueueService {
    
    /// Creates a preview queue service with mock TTS.
    static var preview: SessionTTSQueueService {
        SessionTTSQueueService(ttsService: MockTTSService())
    }
}
#endif
