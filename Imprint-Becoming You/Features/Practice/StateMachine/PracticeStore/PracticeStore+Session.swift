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
            AppLogger.warning("No repository for session queue generation", category: .practice)
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
            AppLogger.info("Generated session queue with \(queue.count) fresh affirmations", category: .practice)
            #endif

        } catch {
            #if DEBUG
            AppLogger.warning("Session queue generation failed: \(error)", category: .practice)
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
        AppLogger.debug("Starting session preparation for \(totalCount) affirmations", category: .practice)
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
                            AppLogger.debug("Phase changed to \(phase)", category: .practice)
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

                            // Update integer counts (used for canStartEarly logic).
                            // Fractional progress is set by onFractionalProgress below.
                            self.setSessionPreparation(
                                isActive: true,
                                progress: self.sessionPreparationProgress,
                                preparedCount: prepared,
                                target: total
                            )

                            #if DEBUG
                            if prepared % 5 == 0 || prepared == total {
                                AppLogger.debug("Preparation progress \(prepared)/\(total)", category: .practice)
                            }
                            #endif
                        }
                    },
                    onFractionalProgress: { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self = self, self.isPreparingSession else { return }
                            self.setSessionPreparation(isActive: true, progress: fraction)
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
                AppLogger.debug("Preparation task cancelled (user action)", category: .practice)
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
            AppLogger.warning("No pending mode for retry", category: .practice)
            #endif
            return
        }

        #if DEBUG
        AppLogger.debug("Retrying session preparation", category: .practice)
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
            AppLogger.warning("No pending mode for system voice fallback", category: .practice)
            #endif
            return
        }

        #if DEBUG
        AppLogger.debug("Continuing with System TTS", category: .practice)
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
        // Signal MemoryManager that a session is active.
        // This prevents aggressive background release of the audio cache
        // and defers pipeline release with a grace period.
        MemoryManager.shared.sessionDidStart()

        // Reset session-scoped flags
        setHasSessionBeenSaved(false)

        setSessionState(index: 0)
        setSessionResults([])
        sessionMode = mode
        sessionStartTime = Date()

        // Record saved session playback at true session start (not on tap).
        // playingSavedSessionId is set in handleStartSavedSession() and persists
        // through the entire session lifecycle until handleSessionCoverDismissed().
        if let savedSessionId = playingSavedSessionId {
            try? savedSessionRepository?.recordPlayback(sessionId: savedSessionId)
        }

        // Reset loop iteration to 1 when starting fresh
        var config = loopConfiguration
        config.resetIteration()
        setLoopConfiguration(config)

        // Apply spaced repetition expansion BEFORE setting flow.
        // originalSessionAffirmationIds already captured the base unique IDs.
        // TTS prep already synthesized audio for the unique set.
        // Expansion inserts duplicate Affirmation references — UUID-keyed cache serves both.
        if loopConfiguration.isSpacedRepetitionEnabled && sessionAffirmations.count > 1 {
            let expanded = SpacedRepetitionBuilder.expand(sessionAffirmations)
            setSessionAffirmationsForShuffle(expanded)

            // Update TTS queue with expanded order for index-based progress tracking
            let expandedInfos = expanded.enumerated().map { index, affirmation in
                SessionAffirmationInfo(affirmation: affirmation, index: index)
            }
            dependencies.sessionTTSQueueService.updateAffirmationOrder(expandedInfos)
        }

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

        // Cap at 100 to prevent unbounded memory growth from long browse sessions
        let maxBrowseCount = 100
        if updated.count > maxBrowseCount {
            let trimmed = Array(updated.suffix(maxBrowseCount))
            let trimmedIds = Set(trimmed.map { $0.id })
            viewedBrowseAffirmationIds = viewedBrowseAffirmationIds.intersection(trimmedIds)
            updated = trimmed
        }

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
        // Guard against late completion after user cancelled preparation.
        // clearSessionPreparation() sets isPreparingSession = false,
        // so a post-cancel completion event will bail out here.
        guard isPreparingSession else {
            #if DEBUG
            AppLogger.debug("Preparation completed after cancel — ignoring", category: .practice)
            #endif
            return
        }

        guard let mode = pendingSessionMode else {
            #if DEBUG
            AppLogger.warning("Preparation completed but no pending mode", category: .practice)
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
            AppLogger.debug("Early start - starting session with \(preparedCount)/\(totalCount) ready", category: .practice)
        } else {
            AppLogger.debug("TTS preparation complete, starting session in \(mode.rawValue) mode", category: .practice)
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
            AppLogger.debug("Starting background synthesis for remaining \(totalCount - preparedCount) affirmations", category: .practice)
            #endif

            // Release pipeline once background synthesis finishes.
            // All audio will be cached — the pipeline is no longer needed for playback.
            queueService.onBackgroundSynthesisComplete = { [weak self] in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.dependencies.ttsService.releasePipelineMemory()
                    #if DEBUG
                    AppLogger.debug("Released Kokoro pipeline after background synthesis (~1.3GB freed)", category: .practice)
                    #endif
                }
            }

            queueService.startBackgroundSynthesis(startingFrom: preparedCount)
        } else {
            // All audio is pre-synthesized and cached. The Kokoro ML pipeline
            // (~1.3GB) is no longer needed — playback uses cached audio via
            // AudioPlayerService, bypassing TTSService entirely.
            // Soft-release frees CoreML buffers while keeping isKokoroReady=true,
            // so the pipeline transparently reloads on next session preparation.
            Task { [weak self] in
                guard let self else { return }
                await self.dependencies.ttsService.releasePipelineMemory()
                #if DEBUG
                AppLogger.debug("Released Kokoro pipeline after full preparation (~1.3GB freed)", category: .practice)
                #endif
            }
        }
    }

    /// Handles session preparation failure.
    func handleSessionPreparationFailed(_ error: PracticeError) {
        #if DEBUG
        AppLogger.error("TTS preparation failed: \(error)", category: .practice)
        #endif

        // Update phase to error
        setSessionPreparationPhase(.error(message: error.localizedDescription))

        // Don't auto-start - let user choose to retry or cancel
    }

    /// Handles user cancellation of session preparation.
    ///
    /// Performs a full session teardown (modeled after `handleExitSession()`) to ensure
    /// the app returns to a pristine home state. This is critical for the mid-session
    /// mode switch path where `flow` and `sessionMode` are still in active states —
    /// without full cleanup, the session view would remain visible with empty content.
    ///
    /// Also handles the race condition where `.sessionPreparationCompleted` fires
    /// just before cancel: even if `startSession()` already ran, this teardown
    /// fully undoes it by resetting flow to `.home` and clearing all session state.
    /// Cancels session preparation and dismisses the fullScreenCover.
    ///
    /// Performs immediate cleanup of preparation-specific state (cancel tasks,
    /// clear preparation UI, release Kokoro pipeline) then dismisses the cover.
    /// Remaining cleanup deferred to `handleSessionCoverDismissed`.
    func handleCancelSessionPreparation() {
        AppLogger.debug("User cancelled session preparation", category: .practice)

        // 1. Cancel any active work
        cancelCurrentActivity()

        // 2. Cancel TTS queue and clear preparation state.
        clearSessionPreparation()
        dependencies.sessionTTSQueueService.cancelAll()

        // 3. Release Kokoro ML pipeline immediately (~1.3GB).
        // The pipeline was loaded during preparation but is no longer needed.
        // cancelAll() only schedules release via a 30s idle timer — this
        // bypasses the delay for instant memory recovery.
        Task { [weak self] in
            guard let self else { return }
            await self.dependencies.ttsService.releasePipelineMemory()
            #if DEBUG
            AppLogger.debug("Released Kokoro pipeline on cancel preparation (~1.3GB freed)", category: .practice)
            #endif
        }

        // 4. Reset to home mode before dismiss — underlying pager shows clean content
        sessionMode = .readOnly
        setFlow(.home)

        // 5. Dismiss the fullScreenCover — remaining cleanup in onDismiss
        setSessionPresented(false)
    }

    func showSessionSummary() {
        cancelCurrentActivity()

        // NOTE: Loop configuration is NOT reset here. It's deferred to just before
        // the summary animation begins (inside the Task below), so the loop progress
        // chip (🔁 "3 of 3") stays visible during the sessionCompletePause delay.
        // Resetting here would set loopCount=1, hiding the chip before the summary
        // transition covers it — causing a visible "vanish" glitch.

        // NOTE: Idle timer is NOT resumed here. The summary view is part of the
        // active session lifecycle — the user may tap "Repeat" which reuses the
        // cached audio. The idle timer stays suppressed so the Kokoro pipeline
        // remains warm for instant repeat. It's resumed when the session lifecycle
        // fully ends (handleDismissSummary, handleExitSession, or handleResetToHome
        // via cancelAll() which internally resumes the idle timer).

        // NOTE: Audio cache is NOT cleared here. The TTS audio cache (~20-40MB)
        // is preserved for repeat sessions. With UUID-keyed caching, the same
        // audio data works even after shuffle reordering. The cache is freed
        // when the session lifecycle ends (handleDismissSummary → cancelAll()).

        // Release speech capture service to free SFSpeechRecognizer + AVAudioEngine (~7-15MB).
        // Lazily recreated on next Read & Speak or Speak Only session.
        releaseSpeechCaptureService()

        #if DEBUG
        AppLogger.debug("showSessionSummary: \(sessionResults.count) results", category: .practice)
        for (i, result) in sessionResults.enumerated() {
            AppLogger.debug("  [\(i)] affirmation=\(result.affirmationId), loopCompletions=\(result.loopCompletions)", category: .practice)
        }
        #endif

        Task { [weak self] in
            guard let self = self else { return }

            try? await Task.sleep(for: PracticeTiming.sessionCompletePause)
            guard !Task.isCancelled else { return }

            // Reset loop configuration for the summary dock's default values.
            // Done here (not earlier) so the loop chip stays visible until
            // the summary transition covers it. Steps 4→5 in the same run-loop
            // pass makes the chip hide and summary appear simultaneously.
            self.resetLoopConfiguration()

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
    ///    - Sets `flow` to `.home` → `isSessionActive` becomes `false`
    ///    - Clears `sessionAffirmations` → `store.affirmations` returns browse content
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
    /// Handles dismissing the summary by resetting to home mode and dismissing the cover.
    ///
    /// Resets `flow` to `.home` BEFORE the dismiss animation starts so the
    /// underlying PracticePageView (behind the cover) shows clean home content
    /// as the cover slides away. Without this, stale session content is visible
    /// during the ~350ms dismiss animation.
    ///
    /// Full cleanup (TTS queue, session data, NavigationStack pop) is deferred to
    /// `handleSessionCoverDismissed()` via the cover's `onDismiss` callback.
    func handleDismissSummary() {
        // Reset to home mode before dismiss — underlying pager shows clean content
        dependencies.audioPlayerService.immediateStop()
        sessionMode = .readOnly
        setFlow(.home)

        // Dismiss the cover — animation reveals clean home content
        setSessionPresented(false)
    }

    /// Handles cleanup after the fullScreenCover dismiss animation completes.
    ///
    /// Called from the cover's `onDismiss` callback. This is the **single cleanup point**
    /// for all dismiss paths (exit, close summary, save, cancel preparation, reset).
    ///
    /// ## Why Here (Not Inline)
    /// State changes during the dismiss animation cause visible glitches:
    /// - NavigationStack pops are visible as the cover slides down
    /// - Flow state changes cause UI flicker in the cover's content
    /// By deferring ALL cleanup to `onDismiss`, the cover dismisses with its
    /// current content frozen — then we clean up invisibly after it's gone.
    ///
    /// ## Ordering Invariants
    /// 1. `immediateStop()` first — prevent audio bleed
    /// 2. `cancelCurrentActivity()` + `cancelAllManagedTasks()` — stop async work
    /// 3. `releaseSpeechCaptureService()` — deactivate mic hardware
    /// 4. `sessionDidEnd()` — signal memory manager
    /// 5. `audioService.stop()` — stop engine, deactivate session (saves battery)
    /// 6. `sessionTTSQueueService.cancelAll()` — clear TTS cache, resume idle timer
    /// 7. `setFlow(.home)` BEFORE `setSessionState(affirmations: [])` — prevent empty-array crash
    /// 8. `setShowingSummary(false)` — reset NavigationStack path (invisible, cover gone)
    func handleSessionCoverDismissed() {
        AppLogger.debug("handleSessionCoverDismissed: full cleanup", category: .practice)

        // 1. Immediate audio silence (may already be stopped, but idempotent)
        dependencies.audioPlayerService.immediateStop()

        // 2. Cancel all active work
        cancelCurrentActivity()
        cancelAllManagedTasks()
        flowGeneration += 1

        // 3. Release speech capture service — deactivates mic hardware
        // immediately via releaseEngine(), then nils the reference.
        // Audio session stays in .playAndRecord permanently (zero HAL breaks).
        releaseSpeechCaptureService()

        // 4. Signal MemoryManager that session lifecycle is complete
        MemoryManager.shared.sessionDidEnd()

        // 5. Stop audio engine — releases playback AVAudioEngine and
        // deactivates the audio session, saving ~2-5mW of idle battery drain.
        // Launched in a Task because stop() is async (detaches sub-services).
        // The engine restarts automatically on the next session's start() call.
        Task { @MainActor [dependencies] in
            await dependencies.audioService.stop()
        }

        // 6. Cancel TTS queue and clear preparation state.
        // cancelAll() internally resumes the synthesis idle timer.
        dependencies.sessionTTSQueueService.cancelAll()
        clearSessionPreparation()

        // 7. Reset session-scoped flags
        forceSystemTTSForSession = false

        // 8. Dismiss any alerts
        setShowingTimeoutAlert(false)
        timedOutAffirmationId = nil
        setPermissionAlert(showing: false)

        // 9. CRITICAL: Reset mode and flow to home BEFORE clearing data.
        //    setFlow(.home) makes isSessionActive = false immediately.
        //    If we cleared data first, VerticalPager could see empty array mid-render.
        //    NOTE: These are intentionally idempotent — the early dismiss handlers
        //    (handleDismissSummary, handleExitSession, handleCancelSessionPreparation,
        //    handleResetToHome) already set these before the cover begins dismissing,
        //    so the underlying pager shows clean home content during the animation.
        //    This second call is the safety net for any future dismiss path that
        //    might not perform the early reset.
        sessionMode = .readOnly
        setFlow(.home)
        setSegmentProgress(0)

        // 10. Clear all session state
        resetLoopConfiguration()
        clearSavedSessionContext()
        clearOriginalSessionAffirmationIds()
        setSessionState(affirmations: [], index: 0)
        setSessionResults([])

        // 11. Reset summary (invisible — cover is already gone)
        setShowingSummary(false)
        setHasSessionBeenSaved(false)

        // 12. Close any open menus
        isModeSelectorExpanded = false
        isMusicSelectorExpanded = false
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

        // Reset session-scoped voice flag so next session uses proper voice
        forceSystemTTSForSession = false

        // Cancel any lingering flow tasks or audio from the previous session.
        // Without this, stale flow tasks or audio can bleed into the new session.
        cancelCurrentActivity()
        flowGeneration += 1

        // NOTE: Idle timer is already suppressed — showSessionSummary() no longer
        // resumes it. The timer stays suppressed through the summary lifecycle
        // and into the repeat session. It's only resumed when the session fully
        // ends (handleDismissSummary, handleExitSession, or handleResetToHome).

        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()

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

        // Store the generation at launch time to guard against rapid re-tap.
        // If user taps repeat again before delay completes, flowGeneration changes
        // and this Task's delayed callback becomes a no-op.
        let repeatGeneration = flowGeneration
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            guard !Task.isCancelled else { return }
            guard self.flowGeneration == repeatGeneration else { return }

            // Session category is managed centrally by AudioSessionController.
            // No pre-configuration needed — .playAndRecord is permanent.

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
            AppLogger.error("handleToggleFavoriteInSummary: Could not find affirmation \(affirmationId)", category: .practice)
            #endif
            return
        }

        let newState = !affirmation.isFavorited
        affirmation.isFavorited = newState
        affirmation.favoritedAt = newState ? Date() : nil

        #if DEBUG
        AppLogger.info("handleToggleFavoriteInSummary: affirmation=\(affirmationId.uuidString.prefix(8)) now=\(newState)", category: .practice)
        #endif

        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmationId }) {
            updateSessionResult(at: index, isFavorited: newState)
        }

        invalidateProfileStats()
    }
}
