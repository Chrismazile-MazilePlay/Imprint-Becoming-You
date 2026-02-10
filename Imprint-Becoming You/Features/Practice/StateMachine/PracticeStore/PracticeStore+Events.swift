//
//  PracticeStore+Events.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/11/26.
//

import SwiftUI

// MARK: - Event Handling

extension PracticeStore {
    
    /// Single entry point for all state changes.
    ///
    /// All user interactions and system events come through here.
    /// This makes state changes predictable and traceable.
    ///
    /// - Parameter event: The event to process
    func send(_ event: PracticeEvent) {
        AppLogger.debug("Event: \(event)", category: .practice)
        
        if event.isUserInteraction {
            lastInteractionTime = Date()
        }
        
        switch event {
            
        // MARK: Mode Selection
        case .selectMode(let mode):
            handleSelectMode(mode)
            
        case .selectBinaural(let preset):
            handleSelectBinaural(preset)
            
        case .toggleModeSelector:
            withAnimation(AppTheme.Animation.standard) {
                isModeSelectorExpanded.toggle()
                if isModeSelectorExpanded {
                    isBinauralSelectorExpanded = false
                }
            }
            
        case .toggleBinauralSelector:
            withAnimation(AppTheme.Animation.standard) {
                isBinauralSelectorExpanded.toggle()
                if isBinauralSelectorExpanded {
                    isModeSelectorExpanded = false
                }
            }
            
        case .closeSelectors:
            withAnimation(AppTheme.Animation.standard) {
                isModeSelectorExpanded = false
                isBinauralSelectorExpanded = false
            }
            
        // MARK: Navigation
        case .userNavigated(let direction):
            handleUserNavigated(direction)
            
        case .navigateViaButton(let direction):
            handleNavigateViaButton(direction)
            
        case .autoAdvanceCompleted:
            handleAutoAdvanceCompleted()
            
        case .goToIndex(let index):
            handleGoToIndex(index)
            
        // MARK: Session Control
        case .exitSession:
            handleExitSession()
            
        case .resetToHome:
            handleResetToHome()
            
        case .startFlow:
            startFlowForCurrentAffirmation()
            
        case .pauseFlow:
            cancelCurrentActivity()
            
        case .resumeFlow:
            if isSessionActive {
                startFlowForCurrentAffirmation()
            }
            
        case .pauseSession:
            // Pause when app enters background — cancel active work and set to idle.
            // Uses non-animated idle reset instead of resetToIdle() because:
            // 1. No user is watching during backgrounding — animation is wasted
            // 2. Animated flow changes can be "in flight" when the view hierarchy
            //    re-renders on foreground return, causing visible layout shifts
            cancelCurrentActivity()
            flowGeneration += 1  // Invalidate any in-flight flow tasks so they cannot progress
            setSegmentProgress(0)
            var pauseTransaction = Transaction()
            pauseTransaction.disablesAnimations = true
            withTransaction(pauseTransaction) {
                switch flow {
                case .home:
                    break
                case .readAloud:
                    setFlow(.readAloud(.idle))
                case .readAndSpeak:
                    setFlow(.readAndSpeak(.idle))
                case .speakOnly:
                    setFlow(.speakOnly(.idle))
                }
            }
            releaseSpeechCaptureService()  // Free audio engine buffers (~7-15MB)
            AppLogger.debug("Session paused (app backgrounded)", category: .practice)
            
        case .resumeSession:
            // Resume when app returns from background - restart flow from beginning of current segment
            if isSessionActive {
                // Block resume while a modal or summary is presented.
                // The modal's action buttons (Try Again / Skip / Exit) handle
                // resumption — starting TTS behind a modal is disorienting.
                // Summary: TTS should not auto-play when viewing results.
                guard !isShowingTimeoutAlert && !isShowingPermissionAlert && !isShowingSummary else {
                    AppLogger.debug("Session resume blocked — modal or summary is showing", category: .practice)
                    return
                }

                AppLogger.debug("Session resumed (app foregrounded)", category: .practice)

                // Re-suppress idle timer as a safety measure. The timer should
                // already be suppressed (it's suppressed at session start and
                // never resumed until the session lifecycle ends), but this
                // guards against edge cases.
                dependencies.ttsService.suppressSynthesisIdleTimer()

                // Increment generation to signal dock to reset its timer
                incrementSegmentGeneration()

                // Restart flow from beginning of current affirmation.
                // Audio cache is preserved — playAffirmation() will hit the
                // UUID-keyed cache for instant playback. If the pipeline was
                // soft-released (>45s background), on-demand synthesis
                // transparently reloads it.
                startFlowForCurrentAffirmation()
            }
            
        // MARK: Session Preparation Events
        case .sessionPreparationCompleted:
            handleSessionPreparationCompleted()
            
        case .sessionPreparationFailed(let error):
            handleSessionPreparationFailed(error)
            
        case .cancelSessionPreparation:
            handleCancelSessionPreparation()
            
        // MARK: Session Summary Events
        case .dismissSummary:
            handleDismissSummary()
            
        case .repeatSession:
            handleRepeatSession()
            
        case .repeatSessionWithConfig(let mode, let loopCount, let shuffle, let spacedRepetition):
            handleRepeatSessionWithConfig(mode: mode, loopCount: loopCount, shuffle: shuffle, spacedRepetition: spacedRepetition)
            
        case .toggleFavoriteInSummary(let affirmationId):
            handleToggleFavoriteInSummary(affirmationId: affirmationId)
            
        // MARK: Loop & Shuffle Events
        case .cycleLoopCount:
            handleCycleLoopCount()
            
        case .toggleShuffle:
            handleToggleShuffle()
            
        case .loopIterationCompleted:
            handleLoopIterationCompleted()
            
        // MARK: Saved Session Events
        case .startSavedSession(let savedSession):
            handleStartSavedSession(savedSession)
            
        case .clearSavedSessionContext:
            clearSavedSessionContext()
            
        case .saveSession(let name):
            handleSaveSession(name: name)
            
        // MARK: Favorites Session Events
        case .startFavoritesSession(let affirmations, let mode, let shuffle):
            handleStartFavoritesSession(affirmations: affirmations, mode: mode, shuffle: shuffle)

        // MARK: Remote Session Start Events
        case .startRemoteSession(let source, let loopConfiguration):
            handleStartRemoteSession(source: source, loopConfiguration: loopConfiguration)

        // MARK: Session Cover Lifecycle
        case .sessionCoverDismissed:
            handleSessionCoverDismissed()
            
        // MARK: TTS Events
        case .ttsStarted:
            break
            
        case .ttsProgress(let progress):
            handleTTSProgress(Double(progress))
            
        case .ttsCompleted:
            handleTTSCompleted()
            
        case .ttsFailed(let error):
            setError(error)
            resetToIdle()
            
        case .ttsCancelled:
            resetToIdle()
            
        // MARK: Listening Events
        case .listeningStarted:
            break
            
        case .listeningUpdate(let context):
            handleListeningUpdate(context)
            
        case .listeningCompleted(let text, let duration):
            handleListeningCompleted(text: text, duration: duration)
            
        case .listeningFailed(let error):
            AppLogger.error("Listening failed: \(error)", category: .speech)
            setError(error)
            resetToIdle()
            
        case .listeningCancelled:
            resetToIdle()
            
        // MARK: Timeout Events
        case .listeningTimedOut:
            handleListeningTimedOut()
            
        case .retryListening:
            handleRetryListening()
            
        case .skipAffirmation:
            handleSkipAffirmation()
            
        // MARK: Permission Events
        case .permissionDenied(let type):
            handlePermissionDenied(type)
            
        case .openSettings:
            handleOpenSettings()
            
        case .continueWithoutPermission:
            handleContinueWithoutPermission()
            
        // MARK: Score Events
        case .analysisStarted:
            transitionToAnalyzing()
            
        case .scoreCalculated(let result):
            handleScoreCalculated(result)
            
        case .scoreFailed(let error):
            setError(error)
            resetToIdle()
            
        case .scoreDisplayCompleted:
            handleScoreDisplayCompleted()
            
        // MARK: Segment Timer Events
        case .segmentTimerCompleted:
            handleSegmentTimerCompleted()
            
        // MARK: Affirmation Events
        case .toggleFavorite:
            handleToggleFavorite()
            
        case .shareAffirmation:
            handleShareAffirmation()
            
        case .recordView:
            recordAffirmationView()
            
        // MARK: UI Events
        case .dismissError:
            setError(nil)
            
        case .viewAppeared:
            break
            
        case .viewDisappeared:
            cancelCurrentActivity()
            
        // MARK: Data Events
        case .affirmationsLoaded(let newAffirmations):
            handleAffirmationsLoaded(newAffirmations)
            
        case .affirmationsLoadFailed(let error):
            handleAffirmationsLoadFailed(error)
        }
    }
}
