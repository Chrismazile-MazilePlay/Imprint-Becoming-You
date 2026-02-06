//
//  PracticeStore+Handlers.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import SwiftUI

// MARK: - Mode Selection Handlers

extension PracticeStore {
    
    func handleSelectMode(_ mode: SessionMode) {
        cancelCurrentActivity()
        flowGeneration += 1
        setSegmentProgress(0)
        
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        if mode == .readOnly {
            // Exiting to home - clear session
            resetLoopConfiguration()
            clearSavedSessionContext()
            clearOriginalSessionAffirmationIds()
            
            // CRITICAL: Reset session mode to default browse mode
            sessionMode = .readOnly
            
            withAnimation(AppTheme.Animation.standard) {
                setFlow(.home)
            }
            setSessionState(affirmations: [], index: 0)
            setSessionResults([])
        } else if isSessionActive {
            // Mid-session mode switch: restart same session with new mode
            // Preserves current affirmations (favorites, saved session, or random)
            restartSessionWithMode(mode)
        } else {
            // From home screen: start fresh session
            resetLoopConfiguration()
            clearSavedSessionContext()
            clearOriginalSessionAffirmationIds()
            generateSessionQueue(forMode: mode)
        }
    }
    
    /// Restarts the current session with a new mode.
    ///
    /// This preserves the current affirmations array (whether from favorites,
    /// a saved session, or a random session) and simply restarts from index 0
    /// with the new mode. All segment progress is reset.
    ///
    /// Use case: User is mid-session and wants to switch from Read & Speak
    /// to Read Aloud without losing their current session context.
    private func restartSessionWithMode(_ mode: SessionMode) {
        AppLogger.debug(
            "Restarting session with mode",
            category: .practice,
            context: ["mode": String(describing: mode), "affirmationCount": affirmations.count]
        )
        
        // Reset position and progress, but keep same affirmations
        setSessionState(index: 0)
        setSessionResults([])
        sessionStartTime = Date()
        
        // Reset loop iteration for fresh restart
        var config = loopConfiguration
        config.resetIteration()
        setLoopConfiguration(config)
        
        // Check if we need TTS preparation
        let needsTTS = mode == .readAloud || mode == .readThenSpeak
        let currentModeUsesTTS = sessionMode == .readAloud || sessionMode == .readThenSpeak
        let hasCache = !sessionAffirmations.isEmpty
            && dependencies.sessionTTSQueueService.isReady(sessionAffirmations[0].id)
        
        // Prepare TTS if switching TO a TTS mode FROM a non-TTS mode (or no cache exists)
        if needsTTS && (!currentModeUsesTTS || !hasCache) {
            // Need to prepare TTS - use preparation flow
            prepareAndStartSession(mode: mode)
        } else {
            // Can skip preparation - use direct start
            sessionMode = mode
            
            // Transition to new mode's initial state
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
            
            // Start the flow for the first affirmation
            startFlowForCurrentAffirmation()
        }
    }
    
    func handleSelectBinaural(_ preset: BinauralPreset) {
        withAnimation(AppTheme.Animation.standard) {
            setBinauralPreset(preset)
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        // Fire-and-forget: instant operation, no tracking needed
        Task { [weak self] in
            guard let self = self else { return }
            do {
                if preset == .off {
                    await self.dependencies.audioService.stopBinauralBeats()
                } else {
                    try await self.dependencies.audioService.startBinauralBeats(preset: preset)
                }
            } catch {
                self.setError(.audioSessionError(error.localizedDescription))
            }
        }
    }
}

// MARK: - Navigation Handlers

extension PracticeStore {
    
    func handleUserNavigated(_ direction: NavigationDirection) {
        cancelCurrentActivity()
        
        // Dismiss timeout alert if showing - user has navigated away
        if isShowingTimeoutAlert {
            setShowingTimeoutAlert(false)
            timedOutAffirmationId = nil
        }
        
        if isSessionActive {
            recordEngagement(.view)
            startFlowForCurrentAffirmation()
        } else {
            trackUniqueBrowseView()
            recordEngagement(.view)
        }
    }
    
    func handleNavigateViaButton(_ direction: NavigationDirection) {
        switch direction {
        case .next:
            guard canGoNext else { return }
        case .previous:
            guard canGoPrevious else { return }
        }
        
        // Cancel current activity (stops TTS, listening, etc.)
        cancelCurrentActivity()
        
        // Handle segment progress based on direction:
        // - Forward: Fill current segment to 100% - segment we're leaving appears complete
        // - Backward: Reset current segment to 0% - segment we're leaving appears incomplete
        switch direction {
        case .next:
            setSegmentProgress(1.0)
            // Signal dock to show current segment as complete during transition animation.
            // This prevents visual glitch where segment resets to 0% before filling.
            setForwardNavigationPending(true)
        case .previous:
            setSegmentProgress(0)
        }
        
        // NOTE: We intentionally do NOT change the flow to .idle here.
        // Changing to .idle would make isAnimating=false, which causes the dock
        // to visually reset the segment, ignoring our segmentProgress value.
        // The flow will naturally transition when startFlowForCurrentAffirmation()
        // is called after the pager animation completes.
        
        setNavigationLocked(false)
        
        // Trigger pager animation to new index
        pendingAutoAdvance = direction
    }
    
    func handleAutoAdvanceCompleted() {
        pendingAutoAdvance = nil
        
        // Clear forward navigation flag - transition is complete
        setForwardNavigationPending(false)
        
        // Reset segment progress for the new segment (starts at 0%)
        setSegmentProgress(0)
        
        // Increment segment generation to signal dock to restart its timer
        incrementSegmentGeneration()
        
        if isSessionActive {
            recordEngagement(.view)
            startFlowForCurrentAffirmation()
        } else {
            trackUniqueBrowseView()
            recordEngagement(.view)
        }
    }
    
    func handleGoToIndex(_ index: Int) {
        guard affirmations.indices.contains(index) else { return }
        guard !shouldBlockNavigation else { return }
        
        cancelCurrentActivity()
        
        if isSessionActive {
            setSessionState(index: index)
        } else {
            setBrowseState(index: index)
        }
        
        resetToIdle()
        recordEngagement(.view)
        
        if isSessionActive {
            startFlowForCurrentAffirmation()
        } else {
            trackUniqueBrowseView()
        }
    }
    
    func handleExitSession() {
        AppLogger.debug("Exit session initiated", category: .practice)

        // 1. IMMEDIATE SILENCE: Zero volume and stop player synchronously.
        // This bypasses actor isolation to guarantee zero audible bleed,
        // even if the cooperative thread pool is under load.
        dependencies.audioPlayerService.immediateStop()

        // 2. Cancel all active work (tasks, TTS, speech capture, continuations)
        cancelCurrentActivity()
        flowGeneration += 1  // Ensure any stale async work sees generation mismatch and stops

        // 3. Signal MemoryManager that session lifecycle is complete
        MemoryManager.shared.sessionDidEnd()

        // 4. Cancel TTS queue and clear preparation state.
        // cancelAll() internally resumes the synthesis idle timer.
        dependencies.sessionTTSQueueService.cancelAll()
        clearSessionPreparation()

        // 4b. Reset session-scoped voice flag so next session uses proper voice
        forceSystemTTSForSession = false

        // 5. Dismiss any alerts and clear timeout tracking
        setShowingTimeoutAlert(false)
        timedOutAffirmationId = nil
        setPermissionAlert(showing: false)

        // 6. CRITICAL: Set mode and flow to home FIRST
        //    This makes isSessionActive = false BEFORE we clear session data.
        //    Without this order, there's a brief moment where:
        //    - sessionAffirmations is empty
        //    - flow is still active mode (isSessionActive = true)
        //    - currentAffirmation returns nil
        //    - UI shows inconsistent state (text/buttons disappear)
        sessionMode = .readOnly
        setFlow(.home)
        setSegmentProgress(0)

        // 7. Now safe to clear session state (isSessionActive is already false)
        resetLoopConfiguration()
        clearSavedSessionContext()
        clearOriginalSessionAffirmationIds()
        setSessionState(affirmations: [], index: 0)
        setSessionResults([])

        // 8. Close any open menus with animation
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        AppLogger.debug("Exit session completed - now in home mode", category: .practice)
    }
    
    /// Full app-level reset after extended background (>10 min).
    ///
    /// Resets from ANY state back to home:
    /// - Dismisses summary if showing
    /// - Exits active session
    /// - Clears all session state
    /// - Returns to Read Only home mode
    ///
    /// Called by MainPracticeView when returning from background after 10+ minutes.
    func handleResetToHome() {
        AppLogger.debug("Full reset to home (extended background)", category: .practice)
        
        // Cancel any active work - use centralized management
        cancelAllManagedTasks()
        cancelCurrentActivity()

        // Signal MemoryManager that session lifecycle is complete
        MemoryManager.shared.sessionDidEnd()

        // Cancel TTS queue and clear preparation state.
        // cancelAll() internally resumes the synthesis idle timer.
        dependencies.sessionTTSQueueService.cancelAll()
        clearSessionPreparation()
        
        // Reset session-scoped voice flag so next session uses proper voice
        forceSystemTTSForSession = false
        
        // Dismiss summary if showing (no animation needed since we're resetting)
        if isShowingSummary {
            setShowingSummary(false)
        }
        
        // Dismiss any alerts and clear timeout tracking
        setShowingTimeoutAlert(false)
        timedOutAffirmationId = nil
        setPermissionAlert(showing: false)
        
        // Reset loop configuration
        resetLoopConfiguration()
        clearSavedSessionContext()
        clearOriginalSessionAffirmationIds()
        
        // Clear session state
        setSessionState(affirmations: [], index: 0)
        setSessionResults([])
        
        // Reset session mode to default
        sessionMode = .readOnly
        
        // Reset flow to home
        setFlow(.home)
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
    }
}

// MARK: - Loop & Shuffle Handlers

extension PracticeStore {
    
    /// Cycles loop count: 1 -> 3 -> 5 -> 1
    func handleCycleLoopCount() {
        var config = loopConfiguration
        config.cycleLoopCount()
        setLoopConfiguration(config)
        
        HapticFeedback.selection()
        
        AppLogger.debug(
            "Loop count cycled",
            category: .practice,
            context: ["loopCount": config.loopCount]
        )
    }
    
    /// Toggles shuffle on/off
    func handleToggleShuffle() {
        var config = loopConfiguration
        config.toggleShuffle()
        setLoopConfiguration(config)
        
        HapticFeedback.selection()
        
        AppLogger.debug(
            "Shuffle toggled",
            category: .practice,
            context: ["isShuffleEnabled": config.isShuffleEnabled]
        )
    }
    
    /// Handles completion of a loop iteration.
    ///
    /// ## Rapid-Skip Resilience
    ///
    /// Each swipe/skip fires a fire-and-forget `cancelAndStop()` Task
    /// via `cancelCurrentActivity()`. The system handles this through
    /// two layers of defense:
    ///
    /// ### Defense-in-Depth (2 layers):
    ///
    /// 1. **`cancelCurrentActivity()`** - Best-effort teardown. Cancels the active
    ///    flow task, stops TTS via `cancelAndStop()` on the audio actor.
    ///
    /// 2. **`isAnimating` toggle** - Sets flow to `.idle` (isAnimating=false) BEFORE
    ///    resetting the index, so the dock timer cannot start prematurely.
    ///    `handleAnimatingChanged` restarts it when flow sets `.playing`.
    ///
    /// `playRawPCMData()` atomically handles cleanup via `cancelAndStop()` as its
    /// first operation, eliminating the need for an explicit actor drain.
    ///
    /// ### State Change Order (Critical)
    /// ```
    /// 1. cancelCurrentActivity()  -> cancelAndStop() Tasks queued
    /// 2. Set flow to .idle        -> isAnimating=false -> dock timer STOPS
    /// 3. Reset index to 0         -> no timer start (isAnimating=false)
    /// 4. startFlowForCurrentAffirmation() -> new Task:
    ///    a. setFlow(.playing)           -> isAnimating=true -> dock timer STARTS
    ///    b. speakText() -> playRawPCMData() -> cancelAndStop() + play
    /// ```
    func handleLoopIterationCompleted() {
        guard loopConfiguration.hasMoreLoops else {
            // All loops complete, show summary
            showSessionSummary()
            return
        }
        
        // Advance to next loop
        var config = loopConfiguration
        config.advanceLoop()
        setLoopConfiguration(config)
        
        AppLogger.debug(
            "Advanced to next loop",
            category: .practice,
            context: ["currentLoop": config.currentLoopIteration, "totalLoops": config.loopCount]
        )
        
        // LAYER 1: Best-effort teardown of all current activity.
        // Cancels flow task, stops TTS via cancelAndStop() on the audio actor.
        // Rapid skipping may have left fire-and-forget Tasks in-flight --
        // playRawPCMData() handles residual cleanup atomically.
        cancelCurrentActivity()
        
        // Invalidate stale completion handlers BEFORE state reset.
        // Prevents race conditions where old timers fire during the
        // transition and trigger premature auto-advance.
        flowGeneration += 1
        
        // LAYER 2: Set flow to idle to stop the dock timer.
        // The flow was .readAloud(.complete) which keeps isAnimating=true.
        // If we reset the index while isAnimating is still true,
        // handleSegmentChanged would immediately start a new timer —
        // creating a head start over TTS.
        switch sessionMode {
        case .readAloud:
            setFlow(.readAloud(.idle))
        case .readThenSpeak:
            setFlow(.readAndSpeak(.idle))
        case .speakOnly:
            setFlow(.speakOnly(.idle))
        default:
            break
        }
        
        // Now safe to reset index — isAnimating is false, timer won't start
        setSessionState(index: 0)
        setSegmentProgress(0)
        
        // Shuffle if enabled — cache remains valid (keyed by UUID, not index)
        if config.isShuffleEnabled {
            shuffleSessionAffirmations()

            // Update TTS queue with new affirmation order.
            // Cache is keyed by affirmation UUID, so it remains fully valid
            // after reordering — no invalidation needed.
            let newOrder = sessionAffirmations.enumerated().map { index, affirmation in
                SessionAffirmationInfo(affirmation: affirmation, index: index)
            }
            dependencies.sessionTTSQueueService.updateAffirmationOrder(newOrder)
        }

        // Pre-configure the audio session to eliminate the 50-200ms HAL
        // reconfiguration delay in ensurePlaybackCategory().
        // After cancelCurrentActivity() above, the category may be .playAndRecord
        // (from speech capture in Read & Speak / Speak Only modes). Pre-configuring
        // switches to .playback on a background queue so playRawPCMData() finds it
        // already set (~1-5ms instead of 50-200ms).
        let loopGeneration = flowGeneration
        Task { [weak self] in
            guard let self = self else { return }

            // Pre-configure audio session BEFORE starting flow
            await self.playbackCoordinator.preConfigureAudioSession()
            guard self.flowGeneration == loopGeneration else { return }

            self.incrementSegmentGeneration()
            self.startFlowForCurrentAffirmation()
        }

        HapticFeedback.notification(.success)
    }
}

// MARK: - TTS Handlers

extension PracticeStore {
    
    func handleTTSProgress(_ progress: Double) {
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .readAloud:
                setFlow(.readAloud(.playing(progress: progress)))
                setSegmentProgress(CGFloat(progress))
            case .readAndSpeak:
                setFlow(.readAndSpeak(.ttsPlaying(progress: progress)))
                setSegmentProgress(CGFloat(progress) * 0.25)
            default:
                break
            }
        }
    }
    
    func handleTTSCompleted() {
        switch flow {
        case .readAloud:
            withAnimation(AppTheme.Animation.quick) {
                setFlow(.readAloud(.complete))
                setSegmentProgress(1.0)
            }
            // FIX: Removed scheduleAutoAdvance() - dock segment timer handles auto-advance
            
        default:
            break
        }
    }
}

// MARK: - Listening Handlers

extension PracticeStore {
    
    func handleListeningUpdate(_ context: ListeningContext) {
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .readAndSpeak:
                setFlow(.readAndSpeak(.listening(context)))
                setSegmentProgress(0.65)
            case .speakOnly:
                setFlow(.speakOnly(.listening(context)))
                setSegmentProgress(0.5)
            default:
                break
            }
        }
    }
    
    func handleListeningCompleted(text: String, duration: TimeInterval) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            AppLogger.warning("Empty transcription received, showing timeout alert", category: .speech)
            handleListeningTimedOut()
            return
        }
        
        // Cancel capture and transition to analyzing
        speechCaptureService.cancelCapture()
        transitionToAnalyzing()
        
        // Calculate score
        // Fire-and-forget: score calculation is quick, result sent via event
        Task { [weak self] in
            guard let self = self else { return }
            
            var score: Double = 0.0
            var components = ScoreComponents(textAccuracy: 0, vocalEnergy: 0, pitchStability: 0)
            
            guard let rawExpectedText = self.currentAffirmation?.text else {
                self.send(.scoreFailed(.scoreCalculationError("No affirmation text")))
                return
            }
            
            // Strip citation (e.g., "(Philippians 4:13)") from expected text
            // so verse references don't need to be spoken
            let expectedText = rawExpectedText.strippingTrailingCitation
            
            let result = TextAccuracyCalculator.evaluateCompletion(
                expected: expectedText,
                recognized: trimmedText
            )
            
            AppLogger.debug(
                "Score calculated",
                category: .practice,
                context: ["accuracy": Int(result.accuracy * 100)]
            )
            
            score = Double(result.accuracy)
            components = ScoreComponents(
                textAccuracy: Double(result.accuracy),
                vocalEnergy: Double(result.accuracy),
                pitchStability: Double(result.accuracy)
            )
            
            let scoreResult = ScoreResult(
                score: score,
                components: components,
                duration: duration,
                mode: self.currentMode,
                recognizedText: trimmedText
            )
            
            self.send(.scoreCalculated(scoreResult))
        }
    }
    
    func transitionToAnalyzing() {
        withAnimation(AppTheme.Animation.quick) {
            switch flow {
            case .readAndSpeak:
                setFlow(.readAndSpeak(.analyzing))
                setSegmentProgress(0.85)
            case .speakOnly:
                setFlow(.speakOnly(.analyzing))
                setSegmentProgress(0.8)
            default:
                break
            }
        }
    }
}

// MARK: - Timeout & Permission Handlers

extension PracticeStore {
    
    func handleListeningTimedOut() {
        cancelCurrentActivity()
        
        // Track which affirmation timed out to prevent double-skip
        timedOutAffirmationId = currentAffirmation?.id
        
        withAnimation(AppTheme.Animation.standard) {
            setShowingTimeoutAlert(true)
        }
    }
    
    func handleRetryListening() {
        setShowingTimeoutAlert(false)
        timedOutAffirmationId = nil
        listeningStartTime = nil
        startFlowForCurrentAffirmation()
    }
    
    func handleSkipAffirmation() {
        setShowingTimeoutAlert(false)
        listeningStartTime = nil
        
        // Guard against double-skip: if user navigated away before tapping Skip,
        // the current affirmation won't match the one that timed out
        guard let affirmation = currentAffirmation else {
            timedOutAffirmationId = nil
            return
        }
        
        // If we have a tracked timed-out affirmation, verify we're still on it
        if let timedOutId = timedOutAffirmationId, timedOutId != affirmation.id {
            // User already navigated away via swipe - don't double-skip
            timedOutAffirmationId = nil
            return
        }
        
        timedOutAffirmationId = nil
        
        if !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) {
            let skippedResult = SessionAffirmationResult(
                affirmation: affirmation,
                isFromScoringMode: sessionMode.producesResonanceScore
            )
            appendSessionResult(skippedResult)
        }
        affirmation.skipCount += 1
        
        if canGoNext {
            if isSessionActive {
                setSessionState(index: sessionIndex + 1)
            } else {
                setBrowseState(index: browseIndex + 1)
            }
            setSegmentProgress(0)
            startFlowForCurrentAffirmation()
        } else if isSessionActive && sessionIndex >= sessionAffirmations.count - 1 {
            // Check for more loops before showing summary
            send(.loopIterationCompleted)
        } else {
            resetToIdle()
        }
    }
    
    func handlePermissionDenied(_ type: PermissionType) {
        cancelCurrentActivity()
        
        withAnimation(AppTheme.Animation.standard) {
            setPermissionAlert(showing: true, type: type)
        }
    }
    
    func handleOpenSettings() {
        setPermissionAlert(showing: false)
        
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    func handleContinueWithoutPermission() {
        setPermissionAlert(showing: false)
        
        withAnimation(AppTheme.Animation.standard) {
            setFlow(.home)
            sessionMode = .readOnly
        }
    }
}

// MARK: - Score Handlers

extension PracticeStore {
    
    func handleScoreCalculated(_ result: ScoreResult) {
        setLastResonanceRecord(result.toRecord())
        
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1
            affirmation.resonanceScores.append(result.toRecord())
            
            // Update session result with score (supports loop scores)
            if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
                AppLogger.debug(
                    "Score calculated for affirmation",
                    category: .practice,
                    context: [
                        "affirmationId": affirmation.id.uuidString.prefix(8),
                        "loop": loopConfiguration.currentLoopIteration,
                        "index": index
                    ]
                )
                
                // For loop support: add score to loopScores array if we're on a subsequent loop
                if loopConfiguration.currentLoopIteration > 1 {
                    addLoopScoreToResult(at: index, score: result.percentScore)
                } else {
                    updateSessionResult(at: index, score: result.percentScore)
                }
            } else {
                AppLogger.error(
                    "Could not find result for affirmation",
                    category: .practice,
                    context: ["affirmationId": affirmation.id.uuidString.prefix(8)]
                )
            }
        }
        
        recordEngagement(.speak)
        recordResonance(result.toRecord())
        
        withAnimation(AppTheme.Animation.standard) {
            switch flow {
            case .readAndSpeak:
                setFlow(.readAndSpeak(.showingScore(result)))
            case .speakOnly:
                setFlow(.speakOnly(.showingScore(result)))
            default:
                break
            }
            setSegmentProgress(1.0)
        }
        
        lockNavigation()
        
        // Capture generation BEFORE Task to detect if user navigates during score display
        let generation = flowGeneration
        
        // Fire-and-forget: short delay before score display completes
        // Uses flowGeneration pattern to prevent double-skip when user manually navigates
        // while score is showing (similar to how timeout modal uses timedOutAffirmationId)
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.scoreDisplayDuration)
            
            // If user navigated away during score display, flowGeneration will have changed
            // This prevents the auto-advance from firing after manual navigation
            guard self.shouldContinueFlow(generation: generation) else {
                #if DEBUG
                AppLogger.debug("Score display: User navigated away, skipping auto-advance", category: .practice)
                #endif
                return
            }
            
            self.send(.scoreDisplayCompleted)
        }
    }
    
    func handleScoreDisplayCompleted() {
        // Check if we've completed the current loop
        if isSessionActive && sessionIndex >= sessionAffirmations.count - 1 {
            send(.loopIterationCompleted)
            return
        }
        
        if canGoNext {
            pendingAutoAdvance = .next
        }
    }
}

// MARK: - Affirmation Handlers

extension PracticeStore {
    
    func handleToggleFavorite() {
        guard let affirmation = currentAffirmation else {
            AppLogger.error("No current affirmation for favorite toggle", category: .practice)
            return
        }
        
        // Toggle the in-memory state directly
        // NOTE: Do NOT call repository.toggleFavorite() as it would double-toggle
        let newState = !affirmation.isFavorited
        affirmation.isFavorited = newState
        affirmation.favoritedAt = newState ? Date() : nil
        
        AppLogger.debug(
            "Favorite toggled",
            category: .practice,
            context: ["affirmationId": affirmation.id.uuidString.prefix(8), "isFavorited": newState]
        )
        
        // Update session result if in session
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
            updateSessionResult(at: index, isFavorited: newState)
        }
        
        // SwiftData will auto-save the change - no need to call repository
        // The repository.toggleFavorite() was causing a double-toggle bug
        
        HapticFeedback.selection()
    }
    
    func handleShareAffirmation() {
        recordEngagement(.share)
    }
    
    func recordAffirmationView() {
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.hasBeenSeen = true
        affirmation.viewCount += 1
        affirmation.lastInteractedAt = Date()
    }
}

// MARK: - Data Event Handlers

extension PracticeStore {
    
    func handleAffirmationsLoaded(_ newAffirmations: [Affirmation]) {
        setBrowseState(affirmations: newAffirmations, index: 0, consumed: 0)
        viewedBrowseAffirmationIds = []
        if let firstAffirmation = newAffirmations.first {
            viewedBrowseAffirmationIds.insert(firstAffirmation.id)
            setBrowseState(consumed: 1)
        }
    }
    
    func handleAffirmationsLoadFailed(_ error: PracticeError) {
        setError(error)
        setBrowseState(affirmations: Affirmation.samples, index: 0)
        viewedBrowseAffirmationIds = []
        if let firstSample = Affirmation.samples.first {
            viewedBrowseAffirmationIds.insert(firstSample.id)
            setBrowseState(consumed: 1)
        }
    }
}

// MARK: - Segment Timer Handler

extension PracticeStore {
    
    /// Handles the dock's segment timer completion.
    ///
    /// Called when the DockModule's segment animation reaches 100%.
    /// This replaces the old scheduleAutoAdvance() mechanism.
    ///
    /// ## Background Pause Protection
    ///
    /// The segment timer runs in the SwiftUI View layer (DockSegmentsView) and
    /// continues firing even when the app is backgrounded. When the app backgrounds:
    ///
    /// 1. MainPracticeView sends `.pauseSession`
    /// 2. `pauseSession` handler calls `resetToIdle()` which sets flow to `.idle`
    /// 3. This handler checks `flow.isIdle` and ignores the timer if true
    ///
    /// Without the idle guard, the session would auto-advance through affirmations
    /// while backgrounded, causing:
    /// - TTS playback failures ("Session activation failed")
    /// - User returns to find they're on a different affirmation
    /// - Unexpected state when resuming
    func handleSegmentTimerCompleted() {
        guard isSessionActive else { return }
        
        // CRITICAL: Don't auto-advance when session is paused (idle state).
        //
        // When the app enters background:
        // 1. MainPracticeView sends .pauseSession
        // 2. pauseSession handler calls resetToIdle() -> flow becomes .readAloud(.idle)
        // 3. This guard catches the segment timer and ignores it
        //
        // Without this guard, the segment timer (running in SwiftUI View layer)
        // would trigger auto-advance while backgrounded, causing audio failures
        // and unexpected state when the user returns.
        guard !flow.isIdle else {
            AppLogger.debug("Segment timer ignored (session paused/idle)", category: .practice)
            return
        }
        
        // Check if we've completed the current loop
        if sessionIndex >= sessionAffirmations.count - 1 {
            send(.loopIterationCompleted)
            return
        }
        
        // Trigger auto-advance to next affirmation
        if canGoNext {
            pendingAutoAdvance = .next
        }
    }
}
