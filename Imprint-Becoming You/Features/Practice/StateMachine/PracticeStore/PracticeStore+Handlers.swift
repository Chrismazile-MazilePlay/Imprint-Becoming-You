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
            isMusicSelectorExpanded = false
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
            setSessionPresented(true) // Cover presents immediately
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

        // Release speech capture service memory when switching to Read Aloud.
        // Read Aloud uses TTS playback only — no microphone needed (~7-15MB freed).
        // Service is lazily recreated if user switches back to a listening mode.
        // Note: Do NOT release for readThenSpeak — it uses listening after TTS playback.
        if mode == .readAloud {
            releaseSpeechCaptureService()
            // NOTE: Audio session stays in .playAndRecord permanently.
            // Read Aloud uses TTS playback only — no mic needed (~7-15MB freed
            // by releasing SpeechCaptureService). Session category is unchanged
            // to avoid HAL reconfiguration breaks.
        }

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
            // Transition current mode to idle BEFORE starting preparation.
            // This stops visible activity (auto-scroll, dock animation) while
            // the loading screen shows. Without this, the old mode's flow state
            // (e.g., .speakOnly(.listening)) keeps isScrollActive=true and
            // the auto-scroll continues behind the preparation overlay.
            withAnimation(AppTheme.Animation.standard) {
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
            }

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
    
    func handleSelectBackgroundMusic(_ category: MusicCategory?) {
        withAnimation(AppTheme.Animation.standard) {
            setBackgroundMusicCategory(category)
            isModeSelectorExpanded = false
            isMusicSelectorExpanded = false
        }

        // Fire-and-forget: engine start is async, playback follows immediately
        if let category = category {
            Task { [weak self] in
                await self?.dependencies.audioService.playBackgroundMusic(category: category)
            }
        } else {
            dependencies.audioService.stopBackgroundMusic()
        }
    }

    /// Handles background music volume changes from the dock.
    ///
    /// Clamps the value to `0.0...1.0`, updates the stored property,
    /// and forwards to `AudioService` for real-time volume adjustment.
    func handleSetBackgroundMusicVolume(_ volume: Float) {
        let clamped = max(0, min(1, volume))
        setBackgroundMusicVolume(clamped)
        dependencies.audioService.setBackgroundMusicVolume(clamped)
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
    
    /// Exits the current session by silencing audio and dismissing the cover.
    ///
    /// Only performs the minimum work needed before the dismiss animation:
    /// - Immediate audio silence (zero audible bleed)
    /// - Cancel active work (prevent stale async closures)
    /// - Dismiss the fullScreenCover
    ///
    /// All remaining cleanup (memory, TTS cache, state reset) is deferred to
    /// `handleSessionCoverDismissed()` which fires from the cover's `onDismiss`.
    func handleExitSession() {
        AppLogger.debug("Exit session initiated", category: .practice)

        // 1. IMMEDIATE SILENCE: Zero volume and stop player synchronously.
        // This bypasses actor isolation to guarantee zero audible bleed,
        // even if the cooperative thread pool is under load.
        dependencies.audioPlayerService.immediateStop()

        // 2. Cancel all active work (tasks, TTS, speech capture, continuations)
        cancelCurrentActivity()

        // 3. Reset to home mode before dismiss — underlying pager shows clean content
        sessionMode = .readOnly
        setFlow(.home)

        // 4. Dismiss the fullScreenCover — full cleanup in onDismiss
        setSessionPresented(false)

        AppLogger.debug("Exit session: cover dismiss initiated", category: .practice)
    }
    
    /// Full app-level reset after extended background (>10 min).
    ///
    /// Resets from ANY state back to home:
    /// - If cover is presented: silence audio, cancel work, dismiss cover
    ///   (cleanup deferred to `handleSessionCoverDismissed` via `onDismiss`)
    /// - If no cover: direct cleanup of any lingering state
    ///
    /// Called by MainPracticeView when returning from background after 10+ minutes.
    func handleResetToHome() {
        AppLogger.debug("Full reset to home (extended background)", category: .practice)

        if isSessionPresented {
            // MINIMAL CLEANUP + DISMISS: When the cover is showing, we only need
            // to stop audio and cancel active work here. All comprehensive state
            // cleanup (MemoryManager, TTS queue, session data, summary, menus)
            // is handled by handleSessionCoverDismissed() via the cover's onDismiss.
            // Do NOT duplicate that cleanup here — it would execute twice.
            dependencies.audioPlayerService.immediateStop()
            cancelAllManagedTasks()
            cancelCurrentActivity()

            // Reset to home mode before dismiss — underlying pager shows clean content
            sessionMode = .readOnly
            setFlow(.home)

            setSessionPresented(false)
        } else {
            // FULL INLINE CLEANUP: No cover is showing, so handleSessionCoverDismissed()
            // will NOT be called. We must perform all cleanup that it would have done.
            // This mirrors handleSessionCoverDismissed()'s steps 1–11 for completeness.
            cancelAllManagedTasks()
            cancelCurrentActivity()

            // Release speech capture service — deactivates mic hardware immediately.
            releaseSpeechCaptureService()

            MemoryManager.shared.sessionDidEnd()

            dependencies.sessionTTSQueueService.cancelAll()
            clearSessionPreparation()

            forceSystemTTSForSession = false

            if isShowingSummary {
                setShowingSummary(false)
            }

            setShowingTimeoutAlert(false)
            timedOutAffirmationId = nil
            setPermissionAlert(showing: false)

            resetLoopConfiguration()
            clearSavedSessionContext()
            clearOriginalSessionAffirmationIds()

            setSessionState(affirmations: [], index: 0)
            setSessionResults([])

            sessionMode = .readOnly
            setFlow(.home)
            isModeSelectorExpanded = false
            isMusicSelectorExpanded = false
        }
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
        // Session category is managed centrally by AudioSessionController.
        // Audio session is permanently .playAndRecord — no pre-configuration needed.
        let loopGeneration = flowGeneration
        Task { [weak self] in
            guard let self = self else { return }
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
        // Update separated observable property for word highlighting.
        // Views read this directly instead of store.flow, so AutoScrollingAffirmationText
        // only re-renders when matchedWordCount changes — not on every audio level tick (~43Hz).
        let wordCountChanged = context.matchedWordCount != listeningMatchedWordCount
        if wordCountChanged {
            AppLogger.debug(
                "Word match progress",
                category: .speech,
                context: [
                    "matched": context.matchedWordCount,
                    "total": context.totalExpectedWords,
                    "isListeningPhase": isInListeningPhase
                ]
            )
            setListeningMatchedWordCount(context.matchedWordCount)
        }

        // Flow state update still needed for dock waveform animation and segment progress.
        // The dock reads flow.listeningContext for audioLevel, which changes at high frequency.
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

        // NOTE: Do NOT call resetListeningPhaseState() here.
        // Keep isInListeningPhase=true and listeningMatchedWordCount at its
        // high-water mark through the celebrating phase so the view continues
        // showing all words highlighted. The state resets in:
        // - handleCelebrationCompleted() — just before auto-advance
        // - cancelCurrentActivity() — on navigation, exit, or interruption

        // Cancel capture and transition to celebrating
        speechCaptureService.cancelCapture()

        AppLogger.debug(
            "Listening completed — starting celebration",
            category: .practice,
            context: [
                "recognizedWords": trimmedText.split(separator: " ").count,
                "duration": String(format: "%.1f", duration)
            ]
        )

        // Record session result as completed
        if let affirmation = currentAffirmation {
            affirmation.speakCount += 1

            if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
                // Mark as completed for this loop
                if loopConfiguration.currentLoopIteration > 1 {
                    addLoopCompletionToResult(at: index, completed: true)
                } else {
                    updateSessionResult(at: index, wasCompleted: true)
                }
            }
        }

        recordEngagement(.speak)

        // Brief pause with all words highlighted before celebration starts.
        // Gives the user a moment to see the completed highlight state
        // before the sparkle burst animation plays.
        let generation = flowGeneration
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.preCelebrationPause)
            guard self.shouldContinueFlow(generation: generation) else { return }
            self.send(.celebrationStarted)
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

// MARK: - Celebration Handlers

extension PracticeStore {

    /// Transitions to celebrating phase and schedules auto-advance after celebration duration.
    ///
    /// The flow change uses a disabled-animation transaction so SwiftUI applies
    /// the `.celebrating` state immediately without interpolating view properties.
    /// This prevents the `withAnimation` spring from triggering a cross-fade on
    /// `AutoScrollingAffirmationText`'s `foregroundStyle`, which would momentarily
    /// flash highlighted text back to the default white color before celebration.
    /// Segment progress animates separately since it's a continuous 0→1.0 value.
    func handleCelebrationStarted() {
        // Set flow to celebrating WITHOUT animation to prevent text color flash.
        // When wrapped in withAnimation, SwiftUI's spring interpolation can cause
        // the AttributedString foregroundColor (accent) to briefly blend with the
        // parent .foregroundStyle (white), producing a visible un-highlight flash
        // before the celebration sparkle burst appears.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch flow {
            case .readAndSpeak:
                setFlow(.readAndSpeak(.celebrating))
            case .speakOnly:
                setFlow(.speakOnly(.celebrating))
            default:
                break
            }
        }

        // Animate segment progress separately — this is a continuous value (0→1.0)
        // that benefits from smooth animation in the dock's segment bar.
        withAnimation(AppTheme.Animation.standard) {
            setSegmentProgress(1.0)
        }

        lockNavigation()

        // Capture generation BEFORE Task to detect if user navigates during celebration
        let generation = flowGeneration

        // Schedule celebration completion after the sparkle burst animation finishes
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.celebrationDuration)

            // If user navigated away during celebration, flowGeneration will have changed
            guard self.shouldContinueFlow(generation: generation) else {
                #if DEBUG
                AppLogger.debug("Celebration: User navigated away, skipping auto-advance", category: .practice)
                #endif
                return
            }

            self.send(.celebrationCompleted)
        }
    }

    /// Handles completion of the celebration animation — auto-advances or completes the loop.
    ///
    /// Resets listening phase state (highlights) just before the pager transition,
    /// so the unhighlight is masked by the page slide animation. A brief post-celebration
    /// delay prevents the transition from feeling abrupt after the sparkle burst.
    func handleCelebrationCompleted() {
        // Check if we've completed the current loop
        if isSessionActive && sessionIndex >= sessionAffirmations.count - 1 {
            // Reset listening phase state before loop completion.
            // handleLoopIterationCompleted() also resets via cancelCurrentActivity(),
            // but explicit reset here makes the intent clear.
            resetListeningPhaseState()
            send(.loopIterationCompleted)
            return
        }

        // Brief delay after celebration before auto-advancing.
        // Prevents the transition from feeling abrupt after the sparkle burst.
        let generation = flowGeneration
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.postCelebrationDelay)
            guard self.shouldContinueFlow(generation: generation) else { return }

            // Reset listening phase state just before pager transition.
            // Words unhighlight as the pager starts sliding to the next
            // affirmation — masked by the pager's page transition animation.
            self.resetListeningPhaseState()

            if self.canGoNext {
                self.pendingAutoAdvance = .next
            }
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
        invalidateProfileStats()
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
