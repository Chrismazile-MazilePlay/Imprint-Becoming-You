//
//  SessionTTSQueueService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/26/26.
//

import Foundation

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
/// Audio data is stored in memory for the session duration.
/// Kokoro outputs Float32 PCM at 24kHz — a 30s affirmation uses ~2.88MB,
/// a 60s affirmation ~5.76MB. For a typical 7-affirmation session: ~20-40MB.
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

    /// Synthesis engine for audio generation and Kokoro lifecycle
    private let synthesisEngine: any TTSSynthesisEngineProtocol
    
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

    /// Cached audio data keyed by affirmation UUID
    private let cache = TTSAudioCache()

    /// Affirmation info for the current session
    private var sessionAffirmations: [SessionAffirmationInfo] = []

    /// Immutable voice configuration for the current session.
    /// Loaded once at session start via `SessionVoiceConfiguration.load()`.
    private var voiceConfig: SessionVoiceConfiguration = .default
    
    /// Current queue state
    private var state: SessionTTSQueueState = .idle
    
    /// Current preparation phase
    private var _preparationPhase: SessionPreparationPhase = .waitingForKokoro
    
    /// Active background synthesis task
    private var backgroundTask: Task<Void, Never>?
    
    /// Set of affirmation UUIDs currently being synthesized
    private var synthesizingIDs: Set<UUID> = []
    
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
        cache.count
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
        synthesisEngine: any TTSSynthesisEngineProtocol,
        maxConcurrency: Int = Constants.SessionPreparation.maxConcurrency,
        readyToStartThreshold: Int = Constants.SessionPreparation.readyToStartThreshold,
        largeSessionThreshold: Int = Constants.SessionPreparation.largeSessionThreshold,
        kokoroWarmupTimeout: TimeInterval = Constants.SessionPreparation.kokoroWarmupTimeout
    ) {
        self.synthesisEngine = synthesisEngine
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
        
        // Suppress idle timer for the duration of the session.
        // During playback, audio comes from cache via AudioPlayerService,
        // bypassing TTSService — so the idle timer would fire mid-session
        // and release ~800MB–1.5GB of CoreML buffers.
        synthesisEngine.suppressIdleTimer()
        
        // Store session info
        sessionAffirmations = affirmations
        currentPlaybackIndex = 0

        // Snapshot voice configuration at session start.
        // Settings are immutable for the session duration.
        voiceConfig = .load(voiceId: voiceId, forceSystemTTS: forceSystemTTS)

        #if DEBUG
        print("SessionTTSQueue: Voice config — id: \(voiceId ?? "default"), speed: \(voiceConfig.voiceSettings.speed), pitch: \(voiceConfig.voiceSettings.pitchShiftSemitones), systemTTS: \(forceSystemTTS)")
        #endif
        
        guard !affirmations.isEmpty else {
            _preparationPhase = .complete
            state = .complete
            Task { @MainActor in onPhaseChange(.complete) }
            return
        }
        
        // Phase 1: Wait for Kokoro (unless forcing System TTS)
        if !voiceConfig.forceSystemTTS {
            _preparationPhase = .waitingForKokoro
            state = .waitingForKokoro
            Task { @MainActor in onPhaseChange(.waitingForKokoro) }
            
            #if DEBUG
            print("SessionTTSQueue: Phase 1 - Waiting for Kokoro TTS engine...")
            #endif
            
            let kokoroReady = await synthesisEngine.waitForKokoroReady(timeout: kokoroWarmupTimeout)
            
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
    
    // MARK: - Protocol Methods
    
    func getAudio(for id: UUID) -> Data? {
        cache.get(id)
    }

    func isReady(_ id: UUID) -> Bool {
        cache.contains(id)
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
        // Bounds check
        guard index >= 0 && index < sessionAffirmations.count else {
            throw TTSError.synthesisFailedError(message: "Index out of bounds: \(index)")
        }

        let info = sessionAffirmations[index]

        // Return cached if available (keyed by affirmation UUID)
        if let cached = cache.get(info.id) {
            return cached
        }

        // Wait if currently being synthesized by background task
        if synthesizingIDs.contains(info.id) {
            // Poll for completion (max 5 seconds)
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(50))
                if let cached = cache.get(info.id) {
                    return cached
                }
            }
            throw TTSError.synthesisFailedError(message: "Timeout waiting for synthesis of index \(index)")
        }

        // Synthesize on-demand if not cached and not in progress
        let audioData = try await synthesizeAffirmation(info)
        cache.set(info.id, data: audioData)

        #if DEBUG
        print("SessionTTSQueue: On-demand synthesis complete for index \(index)")
        #endif

        return audioData
    }
    
    func updateAffirmationOrder(_ newOrder: [SessionAffirmationInfo]) {
        #if DEBUG
        print("SessionTTSQueue: Updating affirmation order (\(cache.count) cached items preserved, \(newOrder.count) affirmations)")
        #endif

        // Update affirmation order — cache remains valid because
        // audio is keyed by UUID, not positional index.
        sessionAffirmations = newOrder
        currentPlaybackIndex = 0
    }

    func preSynthesizeFromIndex(_ startIndex: Int) {
        // Cancel any existing background task
        backgroundTask?.cancel()

        let total = sessionAffirmations.count
        guard startIndex < total else { return }

        // Set state to .synthesizingBackground so reprioritizeQueue() can detect
        // active background work and restart synthesis from the user's current
        // position on rapid skip. Without this, notifyPlaying() → reprioritizeQueue()
        // would see a non-.synthesizingBackground state and skip reprioritization,
        // causing desync between TTS audio and the displayed affirmation.
        state = .synthesizingBackground(prepared: preparedCount, total: total)

        #if DEBUG
        print("SessionTTSQueue: Pre-synthesizing from index \(startIndex) (\(total) total, concurrency: \(Constants.SessionPreparation.backgroundConcurrency))")
        #endif

        backgroundTask = Task { [weak self] in
            guard let self else { return }

            // Collect uncached indices (using UUID for cache lookup)
            let indicesToSynthesize = (startIndex..<total).filter { index in
                let info = self.sessionAffirmations[index]
                return !self.cache.contains(info.id) && !self.synthesizingIDs.contains(info.id)
            }

            guard !indicesToSynthesize.isEmpty else {
                #if DEBUG
                print("SessionTTSQueue: Pre-synthesis skipped — all indices cached")
                #endif
                return
            }

            // Use bounded TaskGroup for parallel synthesis.
            // Uses backgroundConcurrency (default: 2) instead of the full
            // maxConcurrency (3) used during initial preparation, leaving
            // headroom for on-demand synthesis from active playback.
            await withTaskGroup(of: (Int, Data?).self) { group in
                var nextSlot = 0
                let concurrency = Constants.SessionPreparation.backgroundConcurrency

                // Seed initial concurrent tasks
                while nextSlot < min(concurrency, indicesToSynthesize.count) {
                    let index = indicesToSynthesize[nextSlot]
                    let info = self.sessionAffirmations[index]
                    self.synthesizingIDs.insert(info.id)

                    group.addTask { [self] in
                        do {
                            try Task.checkCancellation()
                            let data = try await self.synthesizeAffirmation(info)
                            return (index, data)
                        } catch {
                            return (index, nil)
                        }
                    }
                    nextSlot += 1
                }

                // Process results and add next task as each completes
                for await (index, audioData) in group {
                    let info = self.sessionAffirmations[index]
                    self.synthesizingIDs.remove(info.id)

                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }

                    if let audioData {
                        self.cache.set(info.id, data: audioData)

                        // Update state so reprioritizeQueue() continues to detect
                        // active background work during rapid skipping.
                        self.state = .synthesizingBackground(
                            prepared: self.preparedCount,
                            total: self.sessionAffirmations.count
                        )
                    } else {
                        #if DEBUG
                        print("SessionTTSQueue: Pre-synthesis failed for index \(index)")
                        #endif
                    }

                    // Add next task if available
                    if nextSlot < indicesToSynthesize.count {
                        let nextIndex = indicesToSynthesize[nextSlot]
                        let nextInfo = self.sessionAffirmations[nextIndex]
                        self.synthesizingIDs.insert(nextInfo.id)

                        group.addTask { [self] in
                            do {
                                try Task.checkCancellation()
                                let data = try await self.synthesizeAffirmation(nextInfo)
                                return (nextIndex, data)
                            } catch {
                                return (nextIndex, nil)
                            }
                        }
                        nextSlot += 1
                    }
                }
            }

            if !Task.isCancelled && self.state != .cancelled {
                self.state = .complete

                #if DEBUG
                print("SessionTTSQueue: Pre-synthesis complete (\(self.cache.count) cached)")
                #endif
            }
        }
    }

    func synthesizeFirstThenBackground(_ startIndex: Int) async {
        guard startIndex >= 0 && startIndex < sessionAffirmations.count else { return }

        let info = sessionAffirmations[startIndex]
        guard !cache.contains(info.id) else {
            // Already cached, just kick off background for the rest
            preSynthesizeFromIndex(startIndex + 1)
            return
        }

        #if DEBUG
        print("SessionTTSQueue: Awaiting synthesis of index \(startIndex) before flow start")
        #endif

        // Synchronously synthesize the first affirmation so it's cached
        // before startFlowForCurrentAffirmation() calls speakText()
        do {
            let audioData = try await synthesizeAffirmation(info)
            cache.set(info.id, data: audioData)

            #if DEBUG
            print("SessionTTSQueue: Index \(startIndex) ready, starting background for rest")
            #endif
        } catch {
            #if DEBUG
            print("SessionTTSQueue: First affirmation synthesis failed: \(error.localizedDescription)")
            #endif
            // Non-fatal: speakText() will fall through to synthesizeOnDemand()
        }

        // Background-synthesize remaining indices
        if startIndex + 1 < sessionAffirmations.count {
            preSynthesizeFromIndex(startIndex + 1)
        }
    }

    func cancelAll() {
        #if DEBUG
        print("SessionTTSQueue: Cancelling all")
        cache.logMemoryUsage()
        #endif

        state = .cancelled
        _preparationPhase = .complete
        backgroundTask?.cancel()
        backgroundTask = nil
        synthesizingIDs.removeAll()
        cache.clear()
        sessionAffirmations.removeAll()
        voiceConfig = .default
        currentPlaybackIndex = 0

        // Resume idle timer now that session is over.
        // This allows the timer to auto-release pipelines after the
        // standard 30s timeout if no further synthesis occurs.
        synthesisEngine.resumeIdleTimer()
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
        print("SessionTTSQueue: Clearing queue (\(cache.count) items, ~\(cache.memorySizeBytes / 1024)KB)")
        #endif

        // Cancel background synthesis
        backgroundTask?.cancel()
        backgroundTask = nil

        // Clear audio cache (main memory savings)
        cache.clear()
        synthesizingIDs.removeAll()

        // Note: We preserve sessionAffirmations and voiceConfig
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

                let info = self.sessionAffirmations[index]
                guard !self.cache.contains(info.id) else { continue }
                guard !self.synthesizingIDs.contains(info.id) else { continue }

                do {
                    let audioData = try await self.synthesizeAffirmation(info)

                    guard !Task.isCancelled else { return }
                    guard self.state != .cancelled else { return }

                    self.cache.set(info.id, data: audioData)

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

                synthesizingIDs.insert(info.id)
                nextIndex += 1
            }

            // Process results as they complete
            for try await (index, audioData) in group {
                try Task.checkCancellation()

                guard state != .cancelled else {
                    group.cancelAll()
                    throw CancellationError()
                }

                let completedInfo = affirmations[index]
                cache.set(completedInfo.id, data: audioData)
                synthesizingIDs.remove(completedInfo.id)
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

                    synthesizingIDs.insert(info.id)
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
        synthesizingIDs.insert(info.id)
        defer { synthesizingIDs.remove(info.id) }

        return try await synthesisEngine.synthesize(text: info.text, config: voiceConfig)
    }
    
    private func buildPriorityQueue(from startIndex: Int) -> [Int] {
        var queue: [Int] = []
        let total = sessionAffirmations.count

        for i in max(startIndex, currentPlaybackIndex)..<total {
            if !cache.contains(sessionAffirmations[i].id) {
                queue.append(i)
            }
        }

        for i in stride(from: currentPlaybackIndex - 1, through: 0, by: -1) {
            if !cache.contains(sessionAffirmations[i].id) && !queue.contains(i) {
                queue.append(i)
            }
        }

        return queue
    }

    private func reprioritizeQueue(from newIndex: Int) {
        guard case .synthesizingBackground = state else { return }

        let nextNeededIndex = newIndex + 1
        if nextNeededIndex < sessionAffirmations.count && !cache.contains(sessionAffirmations[nextNeededIndex].id) {
            startBackgroundSynthesis(startingFrom: nextNeededIndex)
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension SessionTTSQueueService {
    
    static var preview: SessionTTSQueueService {
        SessionTTSQueueService(synthesisEngine: MockTTSSynthesisEngine())
    }
}
#endif
