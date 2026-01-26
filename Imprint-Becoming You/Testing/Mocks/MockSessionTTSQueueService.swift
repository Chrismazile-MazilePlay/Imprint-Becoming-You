//
//  MockSessionTTSQueueService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import Foundation

// MARK: - Mock Session TTS Queue Service

/// Mock implementation of SessionTTSQueueServiceProtocol for testing and previews.
///
/// Simulates TTS synthesis with configurable delays and behaviors.
/// Tracks all method calls for verification in tests.
@MainActor
final class MockSessionTTSQueueService: SessionTTSQueueServiceProtocol {
    
    // MARK: - Call Tracking
    
    /// Number of times `prepareSession` was called
    var prepareSessionCallCount = 0
    
    /// Number of times `getAudio` was called
    var getAudioCallCount = 0
    
    /// Number of times `notifyPlaying` was called
    var notifyPlayingCallCount = 0
    
    /// Number of times `synthesizeOnDemand` was called
    var synthesizeOnDemandCallCount = 0
    
    /// Number of times `cancelAll` was called
    var cancelAllCallCount = 0
    
    /// Last index passed to `notifyPlaying`
    var lastNotifyPlayingIndex: Int?
    
    /// Last index passed to `synthesizeOnDemand`
    var lastSynthesizeOnDemandIndex: Int?
    
    // MARK: - Mock Configuration
    
    /// Simulated delay per affirmation synthesis (seconds)
    var mockSynthesisDelay: TimeInterval = 0.1
    
    /// Whether synthesis should fail
    var shouldFail = false
    
    /// Error to throw when shouldFail is true
    var mockError: Error = AppError.ttsError("Mock synthesis error")
    
    /// Mock audio data to return
    var mockAudioData = Data(repeating: 0, count: 1000)
    
    // MARK: - State
    
    private var _isPreparing = false
    private var _preparedCount = 0
    private var _preparationTarget = 0
    private var audioCache: [Int: Data] = [:]
    private var sessionAffirmations: [SessionAffirmationInfo] = []
    
    // MARK: - Protocol Properties
    
    var isPreparing: Bool { _isPreparing }
    
    var preparedCount: Int { _preparedCount }
    
    var preparationTarget: Int { _preparationTarget }
    
    var preparationProgress: Float {
        guard _preparationTarget > 0 else { return 0 }
        return Float(min(_preparedCount, _preparationTarget)) / Float(_preparationTarget)
    }
    
    var isInitialPreparationComplete: Bool {
        _preparedCount >= _preparationTarget
    }
    
    // MARK: - Protocol Methods
    
    func prepareSession(
        affirmations: [SessionAffirmationInfo],
        voiceId: String?,
        initialCount: Int
    ) async throws {
        prepareSessionCallCount += 1
        
        if shouldFail {
            throw mockError
        }
        
        _isPreparing = true
        sessionAffirmations = affirmations
        _preparationTarget = min(initialCount, affirmations.count)
        _preparedCount = 0
        audioCache.removeAll()
        
        // Simulate synthesis for initial affirmations
        for i in 0..<_preparationTarget {
            try? await Task.sleep(for: .milliseconds(Int(mockSynthesisDelay * 1000)))
            audioCache[i] = mockAudioData
            _preparedCount += 1
        }
        
        _isPreparing = false
        
        // Simulate background synthesis completion (instant for mock)
        for i in _preparationTarget..<affirmations.count {
            audioCache[i] = mockAudioData
            _preparedCount += 1
        }
    }
    
    func getAudio(for index: Int) -> Data? {
        getAudioCallCount += 1
        return audioCache[index]
    }
    
    func isReady(_ index: Int) -> Bool {
        audioCache[index] != nil
    }
    
    func notifyPlaying(index: Int) {
        notifyPlayingCallCount += 1
        lastNotifyPlayingIndex = index
    }
    
    func synthesizeOnDemand(index: Int) async throws -> Data {
        synthesizeOnDemandCallCount += 1
        lastSynthesizeOnDemandIndex = index
        
        if shouldFail {
            throw mockError
        }
        
        try? await Task.sleep(for: .milliseconds(Int(mockSynthesisDelay * 1000)))
        audioCache[index] = mockAudioData
        _preparedCount += 1
        
        return mockAudioData
    }
    
    func cancelAll() {
        cancelAllCallCount += 1
        _isPreparing = false
        _preparedCount = 0
        _preparationTarget = 0
        audioCache.removeAll()
        sessionAffirmations.removeAll()
    }
    
    // MARK: - Test Helpers
    
    /// Resets all tracking state
    func reset() {
        prepareSessionCallCount = 0
        getAudioCallCount = 0
        notifyPlayingCallCount = 0
        synthesizeOnDemandCallCount = 0
        cancelAllCallCount = 0
        lastNotifyPlayingIndex = nil
        lastSynthesizeOnDemandIndex = nil
        
        shouldFail = false
        mockSynthesisDelay = 0.1
        
        cancelAll()
    }
    
    /// Pre-populates the cache for testing
    func preloadCache(indices: [Int]) {
        for index in indices {
            audioCache[index] = mockAudioData
        }
        _preparedCount = indices.count
    }
}
