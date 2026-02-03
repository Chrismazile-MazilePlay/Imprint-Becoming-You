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
        print("Ã°Å¸Å½Âµ PracticeStore: Starting session preparation for \(totalCount) affirmations")
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
                            print("Ã°Å¸Å½Âµ PracticeStore: Phase changed to \(phase)")
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
                                print("Ã°Å¸Å½Âµ PracticeStore: Preparation progress \(prepared)/\(total) (\(Int(progress * 100))%)")
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
                print("Ã°Å¸Å½Âµ PracticeStore: Preparation task cancelled (user action)")
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
            print("Ã¢Å¡Â Ã¯Â¸Â PracticeStore: No pending mode for retry")
            #endif
            return
        }
        
        #if DEBUG
        print("Ã°Å¸Å½Âµ PracticeStore: Retrying session preparation")
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
            print("Ã¢Å¡Â Ã¯Â¸Â PracticeStore: No pending mode for system voice fallback")
            #endif
            return
        }
        
        #if DEBUG
        print("Ã°Å¸Å½Âµ PracticeStore: Continuing with System TTS")
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
            print("Ã¢Å¡Â Ã¯Â¸Â PracticeStore: Preparation completed but no pending mode")
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
            print("Ã¢Å“â€¦ PracticeStore: Early start - starting session with \(preparedCount)/\(totalCount) ready")
        } else {
            print("Ã¢Å“â€¦ PracticeStore: TTS preparation complete, starting session in \(mode.rawValue) mode")
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
            print("Ã°Å¸Å½Âµ PracticeStore: Starting background synthesis for remaining \(totalCount - preparedCount) affirmations")
            #endif
            queueService.startBackgroundSynthesis(startingFrom: preparedCount)
        }
    }
    
    /// Handles session preparation failure.
    func handleSessionPreparationFailed(_ error: PracticeError) {
        #if DEBUG
        print("Ã¢ÂÅ’ PracticeStore: TTS preparation failed: \(error)")
        #endif
        
        // Update phase to error
        setSessionPreparationPhase(.error(message: error.localizedDescription))
        
        // Don't auto-start - let user choose to retry or cancel
    }
    
    /// Handles user cancellation of session preparation.
    func handleCancelSessionPreparation() {
        #if DEBUG
        print("Ã°Å¸â€ºâ€˜ PracticeStore: User cancelled session preparation")
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
    ///
    /// ## State Reset Order
    /// The order of operations is critical to prevent visual glitches:
    ///
    /// 1. **Reset display state FIRST** (immediate, no animation)
    ///    - Sets `flow` to `.home` â†’ `isSessionActive` becomes `false`
    ///    - Clears `sessionAffirmations` â†’ `store.affirmations` returns browse content
    ///    - PracticePageView now shows browse content (hidden behind summary)
    ///
    /// 2. **Animate summary dismiss**
    ///    - Summary slides down, revealing the already-prepared browse content
    ///    - `sessionResults` kept intact during animation (summary still needs it)
    ///
    /// 3. **Clean up remaining state** (after animation)
    ///    - Clear `sessionResults` and session-scoped flags
    ///
    /// This prevents the bug where the completed session was briefly visible
    /// as the summary dismissed, because the underlying PracticePageView
    /// was still showing session content.
    func handleDismissSummary() {
        // 1. Reset display-relevant state FIRST (immediate, no animation)
        //    This makes PracticePageView show browse content BEFORE the summary slides away.
        //    The summary overlay still covers this, so user sees no change yet.
        sessionMode = .readOnly
        setFlow(.home)
        setSegmentProgress(0)
        resetLoopConfiguration()
        clearSavedSessionContext()
        clearOriginalSessionAffirmationIds()
        setSessionState(affirmations: [], index: 0)
        // NOTE: Keep sessionResults - ResultsSummaryView still references store.sessionSummary
        
        // Clear TTS audio cache to free memory (~7-15MB per session)
        // This was previously missing, causing memory to accumulate across sessions
        dependencies.sessionTTSQueueService.cancelAll()
        
        // Close any open menus immediately
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
        
        // 2. THEN animate the summary dismiss
        //    PracticePageView is already showing browse content (hidden behind summary)
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        // 3. Clean up remaining state AFTER animation completes
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            
            // Now safe to clear results and session-scoped flags
            self.setSessionResults([])
            self.forceSystemTTSForSession = false
            self.setHasSessionBeenSaved(false)
        }
    }
    
    /// Handles repeat session with current loop/shuffle configuration.
    ///
    /// ## Timing Design
    /// Summary dismissal requires an animation delay before starting playback.
    /// After the delay, uses `incrementSegmentGeneration()` + `startFlowForCurrentAffirmation()`
    /// to ensure the dock timer and TTS start with identical timing to within-loop transitions.
    func handleRepeatSession() {
        var config = loopConfiguration
        config.resetIteration()
        setLoopConfiguration(config)
        
        // Invalidate stale completion handlers before state reset
        flowGeneration += 1
        
        // Reset session-scoped voice flag so next session uses proper voice
        forceSystemTTSForSession = false
        
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()
        
        if config.isShuffleEnabled {
            shuffleSessionAffirmations()
            
            // Update TTS queue with new affirmation order.
            // Clears cached audio (indices no longer match) but preserves
            // voice settings. On-demand synthesis handles each affirmation
            // during playback via speakText's fallback chain.
            let newOrder = sessionAffirmations.enumerated().map { index, affirmation in
                SessionAffirmationInfo(affirmation: affirmation, index: index)
            }
            dependencies.sessionTTSQueueService.invalidateCacheForShuffle(newOrder: newOrder)
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
            guard !Task.isCancelled else { return }
            
            // Signal dock to start segment timer in sync with flow start
            self.incrementSegmentGeneration()
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
