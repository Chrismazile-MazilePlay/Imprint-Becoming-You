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
            withAnimation(AppTheme.Animation.standard) {
                setFlow(.home)
            }
            setSessionState(affirmations: [], index: 0)
            setSessionResults([])
        } else {
            generateSessionQueue(forMode: mode)
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
        
        cancelCurrentActivity()
        resetToIdle()
        setNavigationLocked(false)
        
        pendingAutoAdvance = direction
    }
    
    func handleAutoAdvanceCompleted() {
        pendingAutoAdvance = nil
        
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
        cancelCurrentActivity()
        resetToIdle()
        
        setShowingTimeoutAlert(false)
        setPermissionAlert(showing: false)
        
        setSessionState(affirmations: [], index: 0)
        setSessionResults([])
        
        withAnimation(AppTheme.Animation.standard) {
            setFlow(.home)
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
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
            scheduleAutoAdvance()
            
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
        
        transitionToAnalyzing()
        
        Task { [weak self] in
            guard let self = self else { return }
            
            try? await Task.sleep(for: PracticeTiming.analysisDuration)
            guard !Task.isCancelled else { return }
            
            let score: Double
            let components: ScoreComponents
            
            if let record = self.lastResonanceRecord {
                score = Double(record.overallScore)
                components = ScoreComponents(
                    textAccuracy: Double(record.textAccuracy),
                    vocalEnergy: Double(record.vocalEnergy),
                    pitchStability: Double(record.pitchStability)
                )
            } else {
                guard let expectedText = self.currentAffirmation?.text, !expectedText.isEmpty else {
                    #if DEBUG
                    print("[ERROR] PracticeStore: No affirmation text for score calculation")
                    #endif
                    self.handleListeningTimedOut()
                    return
                }
                
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
            }
            
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
        } else if isSessionActive && sessionIndex >= Constants.Session.sessionSize - 1 {
            showSessionSummary()
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
            
            if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
                updateSessionResult(at: index, score: result.percentScore)
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
        if isSessionActive && sessionIndex >= Constants.Session.sessionSize - 1 {
            showSessionSummary()
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
        guard let affirmation = currentAffirmation else { return }
        
        affirmation.isFavorited.toggle()
        affirmation.favoritedAt = affirmation.isFavorited ? Date() : nil
        
        if let index = sessionResults.firstIndex(where: { $0.affirmationId == affirmation.id }) {
            updateSessionResult(at: index, isFavorited: affirmation.isFavorited)
        }
        
        if let repository = repository {
            _ = try? repository.toggleFavorite(affirmationId: affirmation.id)
        }
        
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
