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
        #if DEBUG
        print("[DEBUG] Restarting session with mode: \(mode)")
        print("[DEBUG] Preserving \(affirmations.count) affirmations")
        #endif
        
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
        let hasCache = dependencies.sessionTTSQueueService.isReady(0)
        
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
        #if DEBUG
        print("[DEBUG] PracticeStore: Exit session initiated")
        #endif
        
        // 1. Cancel all active work immediately
        cancelCurrentActivity()
        flowGeneration += 1  // Ensure any stale async work sees generation mismatch and stops
        
        // 2. Cancel TTS queue and clear preparation state
        dependencies.sessionTTSQueueService.cancelAll()
        clearSessionPreparation()
        
        // 3. Dismiss any alerts
        setShowingTimeoutAlert(false)
        setPermissionAlert(showing: false)
        
        // 4. CRITICAL: Set mode and flow to home FIRST
        //    This makes isSessionActive = false BEFORE we clear session data.
        //    Without this order, there's a brief moment where:
        //    - sessionAffirmations is empty
        //    - flow is still active mode (isSessionActive = true)
        //    - currentAffirmation returns nil
        //    - UI shows inconsistent state (text/buttons disappear)
        sessionMode = .readOnly
        setFlow(.home)
        setSegmentProgress(0)
        
        // 5. Now safe to clear session state (isSessionActive is already false)
        resetLoopConfiguration()
        clearSavedSessionContext()
        clearOriginalSessionAffirmationIds()
        setSessionState(affirmations: [], index: 0)
        setSessionResults([])
        
        // 6. Close any open menus with animation
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
        
        #if DEBUG
        print("[DEBUG] PracticeStore: Exit session completed - now in home mode")
        #endif
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
        #if DEBUG
        print("[DEBUG] PracticeStore: Full reset to home (extended background)")
        #endif
        
        // Cancel any active work
        cancelCurrentActivity()
        
        // Cancel TTS queue and clear preparation state
        dependencies.sessionTTSQueueService.cancelAll()
        clearSessionPreparation()
        
        // Dismiss summary if showing (no animation needed since we're resetting)
        if isShowingSummary {
            setShowingSummary(false)
        }
        
        // Dismiss any alerts
        setShowingTimeoutAlert(false)
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
        
        #if DEBUG
        print("[OK] PracticeStore: Loop count cycled to \(config.loopCount)")
        #endif
    }
    
    /// Toggles shuffle on/off
    func handleToggleShuffle() {
        var config = loopConfiguration
        config.toggleShuffle()
        setLoopConfiguration(config)
        
        HapticFeedback.selection()
        
        #if DEBUG
        print("[OK] PracticeStore: Shuffle toggled to \(config.isShuffleEnabled)")
        #endif
    }
    
    /// Handles completion of a loop iteration
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
        
        #if DEBUG
        print("[OK] PracticeStore: Advanced to loop \(config.currentLoopIteration) of \(config.loopCount)")
        #endif
        
        // Reset session index for new loop
        setSessionState(index: 0)
        setSegmentProgress(0)
        
        // Shuffle if enabled
        if config.isShuffleEnabled {
            shuffleSessionAffirmations()
        }
        
        // Reset to idle state for the mode
        resetToIdle()
        
        // Start the new loop
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(300))
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
            #if DEBUG
            print("[WARN] PracticeStore: Empty transcription received, showing timeout alert")
            #endif
            handleListeningTimedOut()
            return
        }
        
        // Cancel capture and transition to analyzing
        speechCaptureService.cancelCapture()
        transitionToAnalyzing()
        
        // Calculate score
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
            
            #if DEBUG
            print("[LOG] PracticeStore: Score: \(Int(result.accuracy * 100))%")
            #endif
            
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
        
        withAnimation(AppTheme.Animation.standard) {
            setShowingTimeoutAlert(true)
        }
    }
    
    func handleRetryListening() {
        setShowingTimeoutAlert(false)
        listeningStartTime = nil
        startFlowForCurrentAffirmation()
    }
    
    func handleSkipAffirmation() {
        setShowingTimeoutAlert(false)
        listeningStartTime = nil
        
        if let affirmation = currentAffirmation {
            if !sessionResults.contains(where: { $0.affirmationId == affirmation.id }) {
                let skippedResult = SessionAffirmationResult(
                    affirmation: affirmation,
                    isFromScoringMode: sessionMode.producesResonanceScore
                )
                appendSessionResult(skippedResult)
            }
            affirmation.skipCount += 1
        }
        
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
                #if DEBUG
                print("[DEBUG] handleScoreCalculated: affirmation=\(affirmation.id), loop=\(loopConfiguration.currentLoopIteration), index=\(index)")
                #endif
                
                // For loop support: add score to loopScores array if we're on a subsequent loop
                if loopConfiguration.currentLoopIteration > 1 {
                    addLoopScoreToResult(at: index, score: result.percentScore)
                } else {
                    updateSessionResult(at: index, score: result.percentScore)
                }
            } else {
                #if DEBUG
                print("[ERROR] handleScoreCalculated: Could not find result for affirmation \(affirmation.id)")
                #endif
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
        
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: PracticeTiming.scoreDisplayDuration)
            guard !Task.isCancelled else { return }
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
            #if DEBUG
            print("[ERROR] handleToggleFavorite: No current affirmation")
            #endif
            return
        }
        
        // Toggle the in-memory state directly
        // NOTE: Do NOT call repository.toggleFavorite() as it would double-toggle
        let newState = !affirmation.isFavorited
        affirmation.isFavorited = newState
        affirmation.favoritedAt = newState ? Date() : nil
        
        #if DEBUG
        print("[OK] handleToggleFavorite: affirmation=\(affirmation.id.uuidString.prefix(8)) now=\(newState)")
        #endif
        
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
    func handleSegmentTimerCompleted() {
        guard isSessionActive else { return }
        
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
