//
//  PracticeStore+Session.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import SwiftUI

// MARK: - Session Queue Generation

extension PracticeStore {
    
    func generateSessionQueue(forMode mode: SessionMode) {
        guard let repo = repository else {
            #if DEBUG
            print("[WARN] PracticeStore: No repository for session queue generation")
            #endif
            clearOriginalSessionAffirmationIds()
            setSessionState(affirmations: Array(browseAffirmations.prefix(Constants.Session.sessionSize)))
            prepareAndStartSession(mode: mode)
            return
        }
        
        let recentlyBrowsedIds = Set(browseAffirmations.prefix(20).map { $0.id })
        
        do {
            let freshQueue = try repo.fetchSessionQueue(
                forCategories: loadedCategories,
                excluding: recentlyBrowsedIds,
                limit: Constants.Session.sessionSize
            )
            
            let queue = freshQueue.isEmpty
                ? Array(browseAffirmations.prefix(Constants.Session.sessionSize))
                : freshQueue
            
            clearOriginalSessionAffirmationIds()
            setSessionState(affirmations: queue)
            
            #if DEBUG
            print("[OK] PracticeStore: Generated session queue with \(queue.count) fresh affirmations")
            #endif
            
        } catch {
            #if DEBUG
            print("[WARN] PracticeStore: Session queue generation failed: \(error)")
            #endif
            clearOriginalSessionAffirmationIds()
            setSessionState(affirmations: Array(browseAffirmations.prefix(Constants.Session.sessionSize)))
        }
        
        prepareAndStartSession(mode: mode)
    }
    
    /// Prepares TTS for session affirmations before starting.
    ///
    /// For modes that use TTS (Read Aloud, Read & Speak), this:
    /// 1. Shows preparation loading screen
    /// 2. Waits for Kokoro TTS engine to be ready
    /// 3. Pre-synthesizes ALL affirmations using bounded parallel execution
    /// 4. Reports progress and phase changes for smooth UI
    /// 5. Starts session when ALL affirmations are ready (or user taps "Start Now")
    ///
    /// For Speak Only mode, skips preparation and starts immediately.
    ///
    /// ## Phases
    /// - `waitingForKokoro`: Waiting for TTS engine warm-up
    /// - `synthesizing`: Parallel audio synthesis in progress
    /// - `complete`: All ready, starting session
    /// - `kokoroTimeout`: Engine timeout, showing fallback options
    ///
    /// ## Fallback Handling
    /// If Kokoro times out (12 seconds), user can:
    /// - "Continue with System Voice" - Uses System TTS for entire session
    /// - "Retry" - Attempts Kokoro initialization again
    func prepareAndStartSession(mode: SessionMode) {
        // Speak Only doesn't use TTS, start immediately
        guard mode == .readAloud || mode == .readThenSpeak else {
            startSession(mode: mode)
            return
        }
        
        // Cancel any existing preparation
        sessionPreparationTask?.cancel()
        
        // Set pending mode and show preparation UI
        setPendingSessionMode(mode)
        let totalCount = sessionAffirmations.count
        setSessionPreparation(
            isActive: true,
            progress: 0,
            preparedCount: 0,
            target: totalCount
        )
        setSessionPreparationPhase(.waitingForKokoro)
        
        #if DEBUG
        print("🎵 PracticeStore: Starting session preparation for \(totalCount) affirmations")
        #endif
        
        // Build lightweight affirmation info for queue
        let affirmationInfos = sessionAffirmations.enumerated().map { index, affirmation in
            SessionAffirmationInfo(affirmation: affirmation, index: index)
        }
        
        let voiceId = selectedVoiceId
        let queueService = dependencies.sessionTTSQueueService
        let forceSystem = forceSystemTTSForSession
        
        sessionPreparationTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                try await queueService.prepareSession(
                    affirmations: affirmationInfos,
                    voiceId: voiceId,
                    forceSystemTTS: forceSystem,
                    onPhaseChange: { [weak self] phase in
                        Task { @MainActor [weak self] in
                            guard let self = self, self.isPreparingSession else { return }
                            self.setSessionPreparationPhase(phase)
                            
                            #if DEBUG
                            print("🎵 PracticeStore: Phase changed to \(phase)")
                            #endif
                            
                            // Handle timeout phase (don't auto-complete)
                            if phase == .kokoroTimeout {
                                // UI will show fallback options
                                return
                            }
                        }
                    },
                    onProgress: { [weak self] prepared, total in
                        Task { @MainActor [weak self] in
                            guard let self = self, self.isPreparingSession else { return }
                            
                            let progress = total > 0 ? Float(prepared) / Float(total) : 0
                            self.setSessionPreparation(
                                isActive: true,
                                progress: progress,
                                preparedCount: prepared,
                                target: total
                            )
                            
                            #if DEBUG
                            if prepared % 5 == 0 || prepared == total {
                                print("🎵 PracticeStore: Preparation progress \(prepared)/\(total) (\(Int(progress * 100))%)")
                            }
                            #endif
                        }
                    }
                )
                
                // If we get here, all affirmations were synthesized (or we're in timeout state)
                guard !Task.isCancelled else { return }
                
                // Check if we completed successfully (not timeout)
                if queueService.preparationPhase == .complete {
                    self.send(.sessionPreparationCompleted)
                }
                // If timeout, the UI handles showing fallback options
                
            } catch is CancellationError {
                #if DEBUG
                print("🎵 PracticeStore: Preparation task cancelled (user action)")
                #endif
                
            } catch {
                guard !Task.isCancelled else { return }
                self.send(.sessionPreparationFailed(.ttsError(error.localizedDescription)))
            }
        }
    }
    
    /// Retries session preparation after a Kokoro timeout.
    ///
    /// Called when user taps "Retry" in the fallback UI.
    /// Attempts to re-initialize Kokoro and restart preparation.
    func retrySessionPreparation() {
        guard let mode = pendingSessionMode else {
            #if DEBUG
            print("⚠️ PracticeStore: No pending mode for retry")
            #endif
            return
        }
        
        #if DEBUG
        print("🎵 PracticeStore: Retrying session preparation")
        #endif
        
        // Reset the force system flag (we're trying Kokoro again)
        forceSystemTTSForSession = false
        
        // Cancel current preparation
        sessionPreparationTask?.cancel()
        dependencies.sessionTTSQueueService.cancelAll()
        
        // Retry Kokoro initialization
        Task { [weak self] in
            guard let self = self else { return }
            
            await self.dependencies.ttsService.retryKokoroInitialization()
            
            // Restart preparation
            self.prepareAndStartSession(mode: mode)
        }
    }
    
    /// Continues session preparation using System TTS.
    ///
    /// Called when user taps "Continue with System Voice" in the fallback UI.
    /// Sets session-scoped flag to use System TTS and restarts preparation.
    func continueWithSystemVoice() {
        guard let mode = pendingSessionMode else {
            #if DEBUG
            print("⚠️ PracticeStore: No pending mode for system voice fallback")
            #endif
            return
        }
        
        #if DEBUG
        print("🎵 PracticeStore: Continuing with System TTS")
        #endif
        
        // Set session-scoped flag to force System TTS
        forceSystemTTSForSession = true
        
        // Cancel current preparation
        sessionPreparationTask?.cancel()
        dependencies.sessionTTSQueueService.cancelAll()
        
        // Restart preparation with System TTS
        prepareAndStartSession(mode: mode)
    }
    
    func startSession(mode: SessionMode) {
        // Reset session-scoped flags
        setHasSessionBeenSaved(false)
        
        setSessionState(index: 0)
        setSessionResults([])
        sessionMode = mode
        sessionStartTime = Date()
        
        // Reset loop iteration to 1 when starting fresh
        var config = loopConfiguration
        config.resetIteration()
        setLoopConfiguration(config)
        
        withAnimation(AppTheme.Animation.standard) {
            switch mode {
            case .readOnly:
                setFlow(.home)
            case .readAloud:
                setFlow(.readAloud(.idle))
            case .readThenSpeak:
                setFlow(.readAndSpeak(.idle))
            case .speakOnly:
                setFlow(.speakOnly(.idle))
            }
        }
        
        startFlowForCurrentAffirmation()
    }
}

// MARK: - Browse Batch Tracking

extension PracticeStore {
    
    func trackUniqueBrowseView() {
        guard let affirmation = currentAffirmation else { return }
        
        if !viewedBrowseAffirmationIds.contains(affirmation.id) {
            viewedBrowseAffirmationIds.insert(affirmation.id)
            setBrowseState(consumed: browseBatchConsumed + 1)
            checkBrowseBatchRefresh()
        }
    }
    
    func recordAffirmationForSession() {
        guard let affirmation = currentAffirmation else { return }
        guard !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) else { return }
        
        let isFromScoringMode = (sessionMode == .readThenSpeak || sessionMode == .speakOnly)
        let result = SessionAffirmationResult(affirmation: affirmation, isFromScoringMode: isFromScoringMode)
        appendSessionResult(result)
    }
    
    func checkBrowseBatchRefresh() {
        guard browseBatchConsumed >= Constants.Session.regenerationTriggerIndex else { return }
        guard !isBrowseBatchRefreshInProgress else { return }
        guard let repo = repository else { return }
        guard !loadedCategories.isEmpty else { return }
        
        isBrowseBatchRefreshInProgress = true
        let categories = loadedCategories
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            do {
                let newAffirmations = try repo.fetchQueue(
                    forCategories: categories,
                    limit: Constants.Session.batchSize
                )
                
                self.appendToBrowseQueue(newAffirmations)
                self.isBrowseBatchRefreshInProgress = false
            } catch {
                self.isBrowseBatchRefreshInProgress = false
            }
        }
    }
    
    func appendToBrowseQueue(_ newAffirmations: [Affirmation]) {
        let existingIds = Set(browseAffirmations.map { $0.id })
        let uniqueNew = newAffirmations.filter { !existingIds.contains($0.id) }
        
        var updated = browseAffirmations
        updated.append(contentsOf: uniqueNew)
        setBrowseState(affirmations: updated, consumed: 0)
    }
}

// MARK: - Session Summary

extension PracticeStore {
    
    // MARK: - Session Preparation Handlers
    
    /// Handles successful session preparation completion.
    ///
    /// If user tapped "Start Now" early for a large session, this will:
    /// 1. Cancel the preparation task
    /// 2. Start the session
    /// 3. Begin background synthesis for remaining affirmations
    func handleSessionPreparationCompleted() {
        guard let mode = pendingSessionMode else {
            #if DEBUG
            print("⚠️ PracticeStore: Preparation completed but no pending mode")
            #endif
            clearSessionPreparation()
            return
        }
        
        let queueService = dependencies.sessionTTSQueueService
        let preparedCount = queueService.preparedCount
        let totalCount = queueService.totalCount
        let hasRemaining = preparedCount < totalCount
        
        #if DEBUG
        if hasRemaining {
            print("✅ PracticeStore: Early start - starting session with \(preparedCount)/\(totalCount) ready")
        } else {
            print("✅ PracticeStore: TTS preparation complete, starting session in \(mode.rawValue) mode")
        }
        #endif
        
        // Cancel the preparation task (if still running)
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
        
        // Clear preparation UI state
        clearSessionPreparation()
        
        // Start the session
        startSession(mode: mode)
        
        // If there are remaining affirmations, continue synthesis in background
        if hasRemaining {
            #if DEBUG
            print("🎵 PracticeStore: Starting background synthesis for remaining \(totalCount - preparedCount) affirmations")
            #endif
            queueService.startBackgroundSynthesis(startingFrom: preparedCount)
        }
    }
    
    /// Handles session preparation failure.
    func handleSessionPreparationFailed(_ error: PracticeError) {
        #if DEBUG
        print("❌ PracticeStore: TTS preparation failed: \(error)")
        #endif
        
        // Update phase to error
        setSessionPreparationPhase(.error(message: error.localizedDescription))
        
        // Don't auto-start - let user choose to retry or cancel
    }
    
    /// Handles user cancellation of session preparation.
    func handleCancelSessionPreparation() {
        #if DEBUG
        print("🛑 PracticeStore: User cancelled session preparation")
        #endif
        
        clearSessionPreparation()
        dependencies.sessionTTSQueueService.cancelAll()
        
        // Reset session-scoped System TTS flag
        forceSystemTTSForSession = false
        
        // Clear session state since we're not starting
        setSessionState(affirmations: [], index: 0)
        clearOriginalSessionAffirmationIds()
    }
    
    func showSessionSummary() {
        cancelCurrentActivity()
        
        #if DEBUG
        print("[DEBUG] showSessionSummary: \(sessionResults.count) results")
        for (i, result) in sessionResults.enumerated() {
            print("  [\(i)] affirmation=\(result.affirmationId), loopScores=\(result.loopScores)")
        }
        #endif
        
        Task { [weak self] in
            guard let self = self else { return }
            
            try? await Task.sleep(for: PracticeTiming.sessionCompletePause)
            guard !Task.isCancelled else { return }
            
            self.setNavigationLocked(true)
            
            withAnimation(.easeInOut(duration: PracticeTiming.summaryTransitionDuration)) {
                self.setShowingSummary(true)
            }
            
            Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryTransitionDuration * 1000)))
                self.setNavigationLocked(false)
            }
            
            HapticFeedback.notification(.success)
        }
    }
    
    /// Handles dismissing the summary and returning to home.
    func handleDismissSummary() {
        // Start the dismiss animation FIRST (before any state changes)
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        // Reset state AFTER animation completes (view is no longer visible)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            
            // Now safe to reset state - view is gone
            self.resetLoopConfiguration()
            self.clearSavedSessionContext()
            self.clearOriginalSessionAffirmationIds()
            self.forceSystemTTSForSession = false
            self.setSessionResults([])
            self.setSessionState(affirmations: [], index: 0)
            self.sessionMode = .readOnly
            self.setFlow(.home)
            self.isModeSelectorExpanded = false
            self.isBinauralSelectorExpanded = false
        }
    }
    
    /// Handles repeat session with current loop/shuffle configuration.
    func handleRepeatSession() {
        var config = loopConfiguration
        config.resetIteration()
        setLoopConfiguration(config)
        
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()
        
        if config.isShuffleEnabled {
            shuffleSessionAffirmations()
        }
        
        switch sessionMode {
        case .readAloud:
            setFlow(.readAloud(.idle))
        case .readThenSpeak:
            setFlow(.readAndSpeak(.idle))
        case .speakOnly:
            setFlow(.speakOnly(.idle))
        default:
            setFlow(.home)
        }
        
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            self.startFlowForCurrentAffirmation()
        }
    }
    
    func handleToggleFavoriteInSummary(affirmationId: UUID) {
        let affirmation = sessionAffirmations.first { $0.id == affirmationId }
            ?? browseAffirmations.first { $0.id == affirmationId }
        
        guard let affirmation = affirmation else {
            #if DEBUG
            print("[ERROR] handleToggleFavoriteInSummary: Could not find affirmation \(affirmationId)")
            #endif
            return
        }
        
        let newState = !affirmation.isFavorited
        affirmation.isFavorited = newState
        affirmation.favoritedAt = newState ? Date() : nil
        
        #if DEBUG
        print("[OK] handleToggleFavoriteInSummary: affirmation=\(affirmationId.uuidString.prefix(8)) now=\(newState)")
        #endif
        
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmationId }) {
            updateSessionResult(at: index, isFavorited: newState)
        }
    }
}
