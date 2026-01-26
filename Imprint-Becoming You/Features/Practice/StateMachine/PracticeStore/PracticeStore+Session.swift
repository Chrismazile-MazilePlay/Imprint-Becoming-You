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
    /// 2. Pre-synthesizes first 5 affirmations
    /// 3. Starts session when preparation completes
    /// 4. Continues background synthesis for remaining
    ///
    /// For Speak Only mode, skips preparation and starts immediately.
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
        let target = min(SessionTTSQueueService.defaultInitialCount, sessionAffirmations.count)
        setSessionPreparation(isActive: true, progress: 0, preparedCount: 0, target: target)
        
        #if DEBUG
        print("🎵 PracticeStore: Starting TTS preparation for \(sessionAffirmations.count) affirmations")
        #endif
        
        // Build lightweight affirmation info for queue
        let affirmationInfos = sessionAffirmations.enumerated().map { index, affirmation in
            SessionAffirmationInfo(affirmation: affirmation, index: index)
        }
        
        let voiceId = selectedVoiceId
        let queueService = dependencies.sessionTTSQueueService
        
        sessionPreparationTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Start preparation with progress updates
                let progressTask = Task { [weak self] in
                    guard let self = self else { return }
                    
                    while !Task.isCancelled && self.isPreparingSession {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        
                        let progress = queueService.preparationProgress
                        let prepared = queueService.preparedCount
                        
                        self.setSessionPreparation(
                            isActive: true,
                            progress: progress,
                            preparedCount: prepared
                        )
                    }
                }
                
                try await queueService.prepareSession(
                    affirmations: affirmationInfos,
                    voiceId: voiceId,
                    initialCount: SessionTTSQueueService.defaultInitialCount
                )
                
                progressTask.cancel()
                
                guard !Task.isCancelled else { return }
                
                self.send(.sessionPreparationCompleted)
                
            } catch {
                guard !Task.isCancelled else { return }
                self.send(.sessionPreparationFailed(.ttsError(error.localizedDescription)))
            }
        }
    }
    
    func startSession(mode: SessionMode) {
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
    func handleSessionPreparationCompleted() {
        guard let mode = pendingSessionMode else {
            #if DEBUG
            print("⚠️ PracticeStore: Preparation completed but no pending mode")
            #endif
            clearSessionPreparation()
            return
        }
        
        #if DEBUG
        print("✅ PracticeStore: TTS preparation complete, starting session in \(mode.rawValue) mode")
        #endif
        
        clearSessionPreparation()
        startSession(mode: mode)
    }
    
    /// Handles session preparation failure.
    func handleSessionPreparationFailed(_ error: PracticeError) {
        #if DEBUG
        print("❌ PracticeStore: TTS preparation failed: \(error)")
        #endif
        
        // Clear preparation state
        let mode = pendingSessionMode
        clearSessionPreparation()
        dependencies.sessionTTSQueueService.cancelAll()
        
        // Still start session - TTS will synthesize on-demand (with delay)
        if let mode = mode {
            #if DEBUG
            print("⚠️ PracticeStore: Starting session anyway, TTS will be on-demand")
            #endif
            startSession(mode: mode)
        } else {
            setError(error)
        }
    }
    
    /// Handles user cancellation of session preparation.
    func handleCancelSessionPreparation() {
        #if DEBUG
        print("🛑 PracticeStore: User cancelled session preparation")
        #endif
        
        clearSessionPreparation()
        dependencies.sessionTTSQueueService.cancelAll()
        
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
    /// Resets loop configuration and session mode when closing via this method.
    func handleDismissSummary() {
        // Reset loop configuration when dismissing (Close button)
        resetLoopConfiguration()
        clearSavedSessionContext()
        clearOriginalSessionAffirmationIds()
        
        setSessionResults([])
        setSessionState(affirmations: [], index: 0)
        
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        // CRITICAL: Reset session mode to default browse mode
        // Without this, the dock's mode selector retains the previous session mode
        // when returning to home (e.g., showing "Read & Speak" instead of "Read Only")
        sessionMode = .readOnly
        
        setFlow(.home)
        isModeSelectorExpanded = false
        isBinauralSelectorExpanded = false
    }
    
    /// Handles repeat session with current loop/shuffle configuration.
    ///
    /// Called when user taps "Repeat Session" button. Preserves loop count
    /// and shuffle settings from the summary controls.
    func handleRepeatSession() {
        // Reset loop iteration counter for new repeat
        var config = loopConfiguration
        config.resetIteration()
        setLoopConfiguration(config)
        
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()
        
        // Shuffle if enabled for the repeat
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
        
        // Toggle the in-memory state directly
        // NOTE: Do NOT call repository.toggleFavorite() as it would double-toggle
        let newState = !affirmation.isFavorited
        affirmation.isFavorited = newState
        affirmation.favoritedAt = newState ? Date() : nil
        
        #if DEBUG
        print("[OK] handleToggleFavoriteInSummary: affirmation=\(affirmationId.uuidString.prefix(8)) now=\(newState)")
        #endif
        
        // Update session result
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmationId }) {
            updateSessionResult(at: index, isFavorited: newState)
        }
        
        // SwiftData will auto-save the change - no need to call repository
    }
}
