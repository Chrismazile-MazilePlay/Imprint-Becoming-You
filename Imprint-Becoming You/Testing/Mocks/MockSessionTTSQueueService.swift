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
/// Provides configurable behavior:
/// - Instant completion (default)
/// - Simulated delays for testing preparation UI
/// - Kokoro wait simulation
/// - Failure simulation
/// - Large session simulation for "Start Now" button testing
@MainActor
final class MockSessionTTSQueueService: SessionTTSQueueServiceProtocol {
    
    // MARK: - Configuration
    
    /// Delay per affirmation synthesis (default: 0 for instant)
    var synthesisDelay: Duration = .zero
    
    /// Whether to simulate Kokoro warm-up wait
    var simulateKokoroWait: Bool = false
    
    /// Duration to simulate Kokoro warm-up
    var kokoroWaitDuration: Duration = .seconds(2)
    
    /// Whether to simulate Kokoro timeout
    var simulateKokoroTimeout: Bool = false
    
    /// Whether to simulate failures
    var shouldFail = false
    
    /// Failure error message
    var failureMessage = "Mock TTS failure"
    
    // MARK: - State
    
    private(set) var isPreparing = false
    private(set) var preparationPhase: SessionPreparationPhase = .waitingForKokoro
    private(set) var preparedCount = 0
    private(set) var totalCount = 0
    private var audioCache: [UUID: Data] = [:]
    private var sessionAffirmations: [SessionAffirmationInfo] = []
    private var currentVoiceId: String?
    private var forceSystemTTS: Bool = false
    private var isBackgroundSynthesizing = false
    
    // MARK: - Protocol Properties
    
    var preparationProgress: Float {
        guard totalCount > 0 else { return 0 }
        return Float(preparedCount) / Float(totalCount)
    }
    
    var isInitialPreparationComplete: Bool {
        preparedCount >= totalCount
    }
    
    var canStartEarly: Bool {
        guard totalCount > Constants.SessionPreparation.largeSessionThreshold else { return false }
        return preparedCount >= Constants.SessionPreparation.readyToStartThreshold
    }
    
    // MARK: - Protocol Methods
    
    func prepareSession(
        affirmations: [SessionAffirmationInfo],
        voiceId: String?,
        forceSystemTTS: Bool,
        onPhaseChange: @escaping @Sendable (SessionPreparationPhase) -> Void,
        onProgress: @escaping @Sendable (Int, Int) -> Void,
        onFractionalProgress: @escaping @Sendable (Float) -> Void
    ) async throws {
        // Reset state
        cancelAll()

        sessionAffirmations = affirmations
        currentVoiceId = voiceId
        self.forceSystemTTS = forceSystemTTS
        totalCount = affirmations.count
        preparedCount = 0
        isPreparing = true

        guard !affirmations.isEmpty else {
            preparationPhase = .complete
            isPreparing = false
            Task { @MainActor in onPhaseChange(.complete) }
            return
        }

        // Phase 1: Simulate Kokoro wait (unless forcing System TTS)
        if !forceSystemTTS && (simulateKokoroWait || simulateKokoroTimeout) {
            preparationPhase = .waitingForKokoro
            Task { @MainActor in onPhaseChange(.waitingForKokoro) }

            if simulateKokoroTimeout {
                try await Task.sleep(for: .seconds(12))
                preparationPhase = .kokoroTimeout
                isPreparing = false
                Task { @MainActor in onPhaseChange(.kokoroTimeout) }
                return
            }

            try await Task.sleep(for: kokoroWaitDuration)
        }

        // Phase 2: Synthesis
        preparationPhase = .synthesizing
        Task { @MainActor in onPhaseChange(.synthesizing) }

        if shouldFail {
            preparationPhase = .error(message: failureMessage)
            isPreparing = false
            throw TTSError.synthesisFailedError(message: failureMessage)
        }

        // Synthesize ALL affirmations
        let total = Float(affirmations.count)
        for (index, info) in affirmations.enumerated() {
            try Task.checkCancellation()

            if synthesisDelay > .zero {
                try await Task.sleep(for: synthesisDelay)
            }

            try Task.checkCancellation()

            let mockAudio = generateMockAudio(for: info.text)
            audioCache[info.id] = mockAudio
            preparedCount = index + 1

            let fraction = Float(preparedCount) / total
            Task { @MainActor in
                onProgress(self.preparedCount, self.totalCount)
                onFractionalProgress(fraction)
            }
        }

        // Phase 3: Complete
        preparationPhase = .complete
        isPreparing = false
        Task { @MainActor in onPhaseChange(.complete) }
    }
    
    func startBackgroundSynthesis(startingFrom startIndex: Int) {
        isBackgroundSynthesizing = true

        for index in startIndex..<totalCount {
            let info = sessionAffirmations[index]
            if audioCache[info.id] == nil {
                audioCache[info.id] = generateMockAudio(for: info.text)
                preparedCount += 1
            }
        }

        isBackgroundSynthesizing = false

        #if DEBUG
        print("MockSessionTTSQueue: Background synthesis complete")
        #endif
    }
    
    func getAudio(for id: UUID) -> Data? {
        audioCache[id]
    }

    func isReady(_ id: UUID) -> Bool {
        audioCache[id] != nil
    }
    
    func notifyPlaying(index: Int) {
        // No-op in mock
    }
    
    func synthesizeOnDemand(index: Int) async throws -> Data {
        guard index >= 0 && index < sessionAffirmations.count else {
            throw TTSError.synthesisFailedError(message: "Index out of bounds")
        }

        let info = sessionAffirmations[index]

        if let cached = audioCache[info.id] {
            return cached
        }

        if shouldFail {
            throw TTSError.synthesisFailedError(message: failureMessage)
        }

        let audio = generateMockAudio(for: info.text)
        audioCache[info.id] = audio
        return audio
    }
    
    func updateAffirmationOrder(_ newOrder: [SessionAffirmationInfo]) {
        // Update affirmation order — cache remains valid (keyed by UUID)
        sessionAffirmations = newOrder
        totalCount = newOrder.count
        // Preserve: audioCache, currentVoiceId, forceSystemTTS, preparedCount
    }

    func preSynthesizeFromIndex(_ startIndex: Int) {
        // Instant mock: synthesize all immediately
        for index in startIndex..<sessionAffirmations.count {
            let info = sessionAffirmations[index]
            if audioCache[info.id] == nil {
                audioCache[info.id] = generateMockAudio(for: info.text)
                preparedCount += 1
            }
        }
    }

    func synthesizeFirstThenBackground(_ startIndex: Int) async {
        // Instant mock: synthesize first then all remaining
        if startIndex < sessionAffirmations.count {
            let info = sessionAffirmations[startIndex]
            if audioCache[info.id] == nil {
                audioCache[info.id] = generateMockAudio(for: info.text)
                preparedCount += 1
            }
        }
        preSynthesizeFromIndex(startIndex + 1)
    }

    func clearQueue() {
        // Clear audio cache but preserve session metadata
        audioCache.removeAll()
        isBackgroundSynthesizing = false
        // Preserve: sessionAffirmations, currentVoiceId, forceSystemTTS, totalCount
    }

    func cancelAll() {
        isPreparing = false
        isBackgroundSynthesizing = false
        preparationPhase = .waitingForKokoro
        preparedCount = 0
        totalCount = 0
        audioCache.removeAll()
        sessionAffirmations.removeAll()
        currentVoiceId = nil
        forceSystemTTS = false
    }
    
    // MARK: - Mock Helpers
    
    private func generateMockAudio(for text: String) -> Data {
        let sampleRate: UInt32 = 24000
        let duration = max(1.0, Double(text.count) / 20.0)
        let numSamples = Int(Double(sampleRate) * duration)
        
        var data = Data()
        
        let dataSize = UInt32(numSamples * 2)
        let fileSize = dataSize + 36
        
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: (sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        data.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))
        
        return data
    }
    
    // MARK: - Test Helpers
    
    /// Simulates a large session for testing "Start Now" button behavior.
    func simulateLargeSession(count: Int = 50) {
        sessionAffirmations = (0..<count).map { index in
            SessionAffirmationInfo(
                id: UUID(),
                text: "Test affirmation \(index + 1)",
                index: index
            )
        }
        totalCount = count
        preparedCount = 0
        isPreparing = true
        preparationPhase = .synthesizing
    }
    
    /// Simulates progress during preparation for UI testing.
    func simulateProgress(prepared: Int, onProgress: @escaping (Int, Int) -> Void) {
        preparedCount = min(prepared, totalCount)

        for index in 0..<preparedCount where index < sessionAffirmations.count {
            let info = sessionAffirmations[index]
            if audioCache[info.id] == nil {
                audioCache[info.id] = generateMockAudio(for: info.text)
            }
        }

        onProgress(preparedCount, totalCount)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension MockSessionTTSQueueService {
    
    static var instant: MockSessionTTSQueueService {
        MockSessionTTSQueueService()
    }
    
    static var realistic: MockSessionTTSQueueService {
        let mock = MockSessionTTSQueueService()
        mock.synthesisDelay = .milliseconds(333)
        return mock
    }
    
    static var withKokoroWait: MockSessionTTSQueueService {
        let mock = MockSessionTTSQueueService()
        mock.simulateKokoroWait = true
        mock.kokoroWaitDuration = .seconds(3)
        return mock
    }
    
    static var withKokoroTimeout: MockSessionTTSQueueService {
        let mock = MockSessionTTSQueueService()
        mock.simulateKokoroTimeout = true
        return mock
    }
    
    static var failing: MockSessionTTSQueueService {
        let mock = MockSessionTTSQueueService()
        mock.shouldFail = true
        return mock
    }
}
#endif
