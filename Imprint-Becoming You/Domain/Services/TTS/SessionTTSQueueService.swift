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
/// Uses **bounded parallel synthesis** via TaskGroup to maximize ANE throughput
/// while avoiding resource contention. Waits for Kokoro TTS engine readiness
/// before starting synthesis.
///
/// ## Parallelism Strategy
/// Based on WWDC 2023 Core ML guidance and empirical testing:
/// - 3 concurrent tasks provides optimal ANE throughput (~3 affirmations/second)
/// - Higher concurrency causes resource contention and thermal throttling
/// - TaskGroup with bounded window ensures consistent performance
///
/// ## Voice Settings
/// Voice settings (speed, pitch, expressiveness) are loaded from `VoiceSettingsManager`
/// at session start and cached for the duration of the session. This ensures consistent
/// audio even if the user changes settings mid-session.
///
/// ## Thread Safety
/// All state is `@MainActor` isolated. Synthesis happens via TaskGroup
/// which manages concurrency internally. Results are cached on the main actor.
///
/// ## Memory Management
/// Audio data is stored in memory for the session duration (~500KB x N).
/// Cache is cleared when `cancelAll()` or `clearQueue()` is called.
/// `clearQueue()` is specifically for background memory release without
/// fully resetting the service state.
///
/// ## Performance Profiling
/// Session preparation is instrumented with os_signpost for Instruments profiling:
/// - `Session Preparation`: Total preparation time (Kokoro wait + synthesis)
///
/// ## Preparation Phases
/// ```
/// 1. WaitingForKokoro - Wait for TTS engine (uses existing app warm-up)
/// 2. Synthesizing     - Parallel audio synthesis
/// 3. Complete         - All ready
/// 4. KokoroTimeout    - Engine not ready after 12 seconds (fallback UI)
/// ```
@MainActor
final class SessionTTSQueueService: SessionTTSQueueServiceProtocol {
    
    // MARK: - Dependencies
    
    /// TTS service for audio synthesis
    private let ttsService: any TTSServiceProtocol
    
    // MARK: - Configuration
    
    /// Maximum concurrent synthesis tasks (ANE optimal = 3)
    private let maxConcurrency: Int
    
    /// Threshold for early start in large sessions
    private let readyToStartThreshold: Int
    
    /// Session size threshold for showing "Start Now" button
    private let largeSessionThreshold: Int
    
    /// Timeout for Kokoro warm-up (seconds)
    private let kokoroWarmupTimeout: TimeInterval
    
    // MARK: - State
    
    /// Cached audio data keyed by session index
    private var audioCache: [Int: Data] = [:]
    
    /// Affirmation info for the current session
    private var sessionAffirmations: [SessionAffirmationInfo] = []
    
    /// Voice ID for current session
    private var currentVoiceId: String?
    
    /// Voice settings for current session (cached at session start).
    /// Settings remain consistent even if user changes them mid-session.
    private var currentVoiceSettings: VoiceSettings = .default
    
    /// Whether to force System TTS for this session
    private var forceSystemTTS: Bool = false
    
    /// Current queue state
    private var state: SessionTTSQueueState = .idle
    
    /// Current preparation phase
    private var _preparationPhase: SessionPreparationPhase = .waitingForKokoro
    
    /// Active background synthesis task
    private var backgroundTask: Task<Void, Never>?
    
    /// Set of indices currently being synthesized
    private var synthesizingIndices: Set<Int> = []
    
    /// Current playback index (for priority calculation)
    private var currentPlaybackIndex: Int = 0
    
    // MARK: - Protocol Properties
    
    var isPreparing: Bool {
        switch state {
        case .waitingForKokoro, .preparingParallel:
            return true
        default:
            return false
        }
    }
    
    var preparationPhase: SessionPreparationPhase {
        _preparationPhase
    }
    
    var preparedCount: Int {
        audioCache.count
    }
    
    var totalCount: Int {
        sessionAffirmations.count
    }
    
    var preparationProgress: Float {
        guard totalCount > 0 else { return 0 }
        return Float(preparedCount) / Float(totalCount)
    }
    
    var isInitialPreparationComplete: Bool {
        preparedCount >= totalCount || state == .complete
    }
    
    var canStartEarly: Bool {
        guard totalCount > largeSessionThreshold else { return false }
        return preparedCount >= readyToStartThreshold
    }
    
    // MARK: - Initialization
    
    init(
        ttsService: any TTSServiceProtocol,
        maxConcurrency: Int = Constants.SessionPreparation.maxConcurrency,
        readyToStartThreshold: Int = Constants.SessionPreparation.readyToStartThreshold,
        largeSessionThreshold: Int = Constants.SessionPreparation.largeSessionThreshold,
        kokoroWarmupTimeout: TimeInterval = Constants.SessionPreparation.kokoroWarmupTimeout
    ) {
        self.ttsService = ttsService
        self.maxConcurrency = maxConcurrency
        self.readyToStartThreshold = readyToStartThreshold
        self.largeSessionThreshold = largeSessionThreshold
        self.kokoroWarmupTimeout = kokoroWarmupTimeout
    }
    
    // MARK: - Session Lifecycle
    
    func prepareSession(
        affirmations: [SessionAffirmationInfo],
        voiceId: String?,
        forceSystemTTS: Bool,
        onPhaseChange: @escaping @Sendable (SessionPreparationPhase) -> Void,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws {
        // Measure total session preparation time with signpost
        let signpostID = AppLogger.makeSignpostID(for: .tts)
        AppLogger.beginInterval(AppLogger.SignpostName.sessionPreparation, id: signpostID, category: .tts)
        
        defer {
            AppLogger.endInterval(AppLogger.SignpostName.sessionPreparation, id: signpostID, category: .tts)
        }
        
        #if DEBUG
        print("SessionTTSQueue: Preparing session with \(affirmations.count) affirmations, voice: \(voiceId ?? "default"), forceSystemTTS: \(forceSystemTTS)")
        #endif
        
        // Cancel any existing session
        cancelAll()
        
        // Store session info
        sessionAffirmations = affirmations
        currentVoiceId = voiceId
        currentPlaybackIndex = 0
        self.forceSystemTTS = forceSystemTTS
        
        // Cache voice settings at session start
        // Settings are stored by full Voice.id, so this lookup works correctly
        if let voiceId = voiceId {
            currentVoiceSettings = VoiceSettingsManager.shared.settings(for: voiceId)
            #if DEBUG
            print("SessionTTSQueue: Loaded voice settings for \(voiceId): speed=\(currentVoiceSettings.speed), pitch=\(currentVoiceSettings.pitchShiftSemitones)")
            #endif
        } else {
            currentVoiceSettings = .default
        }
        
        guard !affirmations.isEmpty else {
            _preparationPhase = .complete
            state = .complete
            Task { @MainActor in onPhaseChange(.complete) }
            return
        }
        
        // Phase 1: Wait for Kokoro (unless forcing System TTS)
        if !forceSystemTTS {
            _preparationPhase = .waitingForKokoro
            state = .waitingForKokoro
            Task { @MainActor in onPhaseChange(.waitingForKokoro) }
            
            #if DEBUG
            print("SessionTTSQueue: Phase 1 - Waiting for Kokoro TTS engine...")
            #endif
            
            let kokoroReady = await waitForKokoroReady()
            
            if !kokoroReady {
                // Timeout - transition to error state
                _preparationPhase = .kokoroTimeout
                state = .kokoroTimeout
                Task { @MainActor in onPhaseChange(.kokoroTimeout) }
                
                #if DEBUG
                print("SessionTTSQueue: Kokoro warm-up timeout - showing fallback options")
                #endif
                
                // Don't throw - let the UI handle showing fallback options
                // The caller will either retry or call prepareSession again with forceSystemTTS=true
                return
            }
            
            #if DEBUG
            print("SessionTTSQueue: Kokoro ready, starting synthesis")
            #endif
        } else {
            #if DEBUG
            print("SessionTTSQueue: Using System TTS (forced)")
            #endif
        }
        
        // Phase 2: Synthesis
        _preparationPhase = .synthesizing
        state = .preparingParallel(prepared: 0, total: affirmations.count)
        Task { @MainActor in onPhaseChange(.synthesizing) }
        
        #if DEBUG
        print("SessionTTSQueue: Phase 2 - Starting bounded parallel synthesis (total: \(affirmations.count))")
        #endif
        
        // Perform bounded parallel synthesis of ALL affirmations
        try await synthesizeAllWithBoundedConcurrency(
            affirmations: affirmations,
            onProgress: onProgress
        )
        
        // Phase 3: Complete
        _preparationPhase = .complete
        state = .complete
        Task { @MainActor in onPhaseChange(.complete) }
        
        #if DEBUG
        print("SessionTTSQueue: Session preparation complete (\(preparedCount)/\(totalCount))")
        #endif
    }
    
    /// Waits for Kokoro TTS engine to become ready.
    ///
    /// Returns immediately if Kokoro is already ready, otherwise polls
    /// every 100ms until timeout.
    ///
    /// - Returns: `true` if Kokoro became ready, `false` if timeout
    private func waitForKokoroReady() async -> Bool {
        // Check if already ready
        if ttsService.isKokoroReady {
            return true
        }
        
        // Poll for readiness
        let startTime = Date()
        let checkInterval: Duration = .milliseconds(100)
        
        while Date().timeIntervalSince(startTime) < kokoroWarmupTimeout {
            try? await Task.sleep(for: checkInterval)
            
            if ttsService.isKokoroReady {
                return true
            }
            
            // Check if cancelled
            if Task.isCancelled || state == .cancelled {
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Protocol Methods
    
    func getAudio(for index: Int) -> Data? {
        return audioCache[index]
    }
    
    func isReady(_ index: Int) -> Bool {
        return audioCache[index] != nil
    }
    
    func notifyPlaying(index: Int) {
        currentPlaybackIndex = index
        
        // Reprioritize background synthesis if active
        reprioritizeQueue(from: index)
        
        #if DEBUG
        print("SessionTTSQueue: Now playing index \(index)")
        #endif
    }
    
    func synthesizeOnDemand(index: Int) async throws -> Data {
        // Return cached if available
        if let cached = audioCache[index] {
            return cached
        }
        
        // Bounds check
        guard index >= 0 && index < sessionAffirmations.count else {
            throw TTSError.synthesisFailedError(message: "Index out of bounds: \(index)")
        }
        
        // Wait if currently being synthesized by background task
        if synthesizingIndices.contains(index) {
            // Poll for completion (max 5 seconds)
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(50))
                if let cached = audioCache[index] {
                    return cached
                }
            }
            throw TTSError.synthesisFailedError(message: "Timeout waiting for synthesis of index \(index)")
        }
        
        // Synthesize on-demand if not cached and not in progress
        let info = sessionAffirmations[index]
        let audioData = try await synthesizeAffirmation(info)
        audioCache[index] = audioData
        
        #if DEBUG
        print("SessionTTSQueue: On-demand synthesis complete for index \(index)")
        #endif
        
        return audioData
    }
    
    func cancelAll() {
        #if DEBUG
        print("SessionTTSQueue: Cancelling all")
        #endif
        
        state = .cancelled
        _preparationPhase = .complete
        backgroundTask?.cancel()
        backgroundTask = nil
        synthesizingIndices.removeAll()
        audioCache.removeAll()
        sessionAffirmations.removeAll()
        currentVoiceId = nil
        currentVoiceSettings = .default  // Reset voice settings
        forceSystemTTS = false
        currentPlaybackIndex = 0
    }
    
    // MARK: - Memory Management
    
    /// Clears the audio cache to free memory.
    ///
    /// Call this when the app enters background to reduce memory footprint.
    /// Unlike `cancelAll()`, this preserves session metadata so the session
    /// can potentially be resumed (though audio will need to be re-synthesized).
    ///
    /// This can free ~500KB x N bytes where N is the number of cached affirmations.
    func clearQueue() {
        #if DEBUG
        let cacheSize = audioCache.values.reduce(0) { $0 + $1.count }
        print("SessionTTSQueue: Clearing queue (\(audioCache.count) items, ~\(cacheSize / 1024)KB)")
        #endif
        
        // Cancel background synthesis
        backgroundTask?.cancel()
        backgroundTask = nil
        
        // Clear audio cache (main memory savings)
        audioCache.removeAll()
        synthesizingIndices.removeAll()
        
        // Note: We preserve sessionAffirmations, currentVoiceId, currentVoiceSettings, etc.
        // so the session structure is maintained. If playback resumes,
        // audio will be re-synthesized on demand with the same settings.
    }
    
    // MARK: - Background Synthesis
    
    func startBackgroundSynthesis(startingFrom startIndex: Int) {
        backgroundTask?.cancel()
        
        // Update state to background mode
        state = .synthesizingBackground(prepared: preparedCount, total: sessionAffirmations.count)
        
        backgroundTask = Task { [weak self] in
            guard let self = self else { return }
            
            let indices = self.buildPriorityQueue(from: startIndex)
            
            for index in indices {
                guard !Task.isCancelled else { return }
                guard self.state != .cancelled else { return }
                guard self.audioCache[index] == nil else { continue }
                guard !self.synthesizingIndices.contains(index) else { continue }
                
                do {
                    let info = self.sessionAffirmations[index]
                    let audioData = try await self.synthesizeAffirmation(info)
                    
                    guard !Task.isCancelled else { return }
                    guard self.state != .cancelled else { return }
                    
                    self.audioCache[index] = audioData
                    
                    self.state = .synthesizingBackground(
                        prepared: self.preparedCount,
                        total: self.sessionAffirmations.count
                    )
                    
                    #if DEBUG
                    print("SessionTTSQueue: Background synthesized index \(index) (\(self.preparedCount)/\(self.sessionAffirmations.count))")
                    #endif
                    
                } catch {
                    #if DEBUG
                    print("SessionTTSQueue: Background synthesis failed for index \(index): \(error)")
                    #endif
                }
                
                try? await Task.sleep(for: .milliseconds(Constants.SessionPreparation.backgroundThrottleMs))
            }
            
            if !Task.isCancelled && self.state != .cancelled {
                self.state = .complete
                
                #if DEBUG
                print("SessionTTSQueue: Background synthesis complete (\(self.preparedCount)/\(self.sessionAffirmations.count))")
                #endif
            }
        }
    }
    
    // MARK: - Bounded Parallel Synthesis
    
    private func synthesizeAllWithBoundedConcurrency(
        affirmations: [SessionAffirmationInfo],
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws {
        
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var nextIndex = 0
            var completedCount = 0
            let total = affirmations.count
            
            // Seed initial concurrent tasks
            while nextIndex < min(maxConcurrency, total) {
                let info = affirmations[nextIndex]
                let index = nextIndex
                
                group.addTask { [self] in
                    try Task.checkCancellation()
                    let data = try await self.synthesizeAffirmation(info)
                    return (index, data)
                }
                
                synthesizingIndices.insert(nextIndex)
                nextIndex += 1
            }
            
            // Process results as they complete
            for try await (index, audioData) in group {
                try Task.checkCancellation()
                
                guard state != .cancelled else {
                    group.cancelAll()
                    throw CancellationError()
                }
                
                audioCache[index] = audioData
                synthesizingIndices.remove(index)
                completedCount += 1
                
                let currentPrepared = completedCount
                Task { @MainActor in
                    onProgress(currentPrepared, total)
                }
                
                state = .preparingParallel(prepared: completedCount, total: total)
                
                #if DEBUG
                print("SessionTTSQueue: Completed \(completedCount)/\(total) (index \(index))")
                #endif
                
                if completedCount == readyToStartThreshold && total > largeSessionThreshold {
                    #if DEBUG
                    print("SessionTTSQueue: Early start threshold reached (\(completedCount)/\(total))")
                    #endif
                }
                
                if nextIndex < total {
                    let info = affirmations[nextIndex]
                    let idx = nextIndex
                    
                    group.addTask { [self] in
                        try Task.checkCancellation()
                        let data = try await self.synthesizeAffirmation(info)
                        return (idx, data)
                    }
                    
                    synthesizingIndices.insert(nextIndex)
                    nextIndex += 1
                }
            }
            
            #if DEBUG
            print("SessionTTSQueue: All \(total) affirmations synthesized")
            #endif
        }
    }
    
    // MARK: - Private Methods
    
    private func synthesizeAffirmation(_ info: SessionAffirmationInfo) async throws -> Data {
        synthesizingIndices.insert(info.index)
        defer { synthesizingIndices.remove(info.index) }
        
        // Use System TTS if forced, otherwise use Kokoro with voice settings
        if forceSystemTTS {
            return try await ttsService.synthesizeWithSystemTTS(text: info.text)
        } else {
            return try await ttsService.synthesize(
                text: info.text,
                voiceId: currentVoiceId,
                speed: currentVoiceSettings.speed,
                pitchShiftSemitones: currentVoiceSettings.pitchShiftFloat,
                pitchRangeScale: currentVoiceSettings.pitchRangeScale
            )
        }
    }
    
    private func buildPriorityQueue(from startIndex: Int) -> [Int] {
        var queue: [Int] = []
        let total = sessionAffirmations.count
        
        for i in max(startIndex, currentPlaybackIndex)..<total {
            if audioCache[i] == nil {
                queue.append(i)
            }
        }
        
        for i in stride(from: currentPlaybackIndex - 1, through: 0, by: -1) {
            if audioCache[i] == nil && !queue.contains(i) {
                queue.append(i)
            }
        }
        
        return queue
    }
    
    private func reprioritizeQueue(from newIndex: Int) {
        guard case .synthesizingBackground = state else { return }
        
        let nextNeededIndex = newIndex + 1
        if nextNeededIndex < sessionAffirmations.count && audioCache[nextNeededIndex] == nil {
            startBackgroundSynthesis(startingFrom: nextNeededIndex)
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension SessionTTSQueueService {
    
    static var preview: SessionTTSQueueService {
        SessionTTSQueueService(ttsService: MockTTSService())
    }
}
#endif
