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
        #if DEBUG
        print("[LOG] PracticeStore.send: \(event)")
        #endif
        
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
            // Pause when app enters background - cancel active work and set to idle
            // Setting to idle makes isAnimating=false, which the dock observes
            cancelCurrentActivity()
            resetToIdle()  // Critical: sets isAnimating=false so resume triggers fresh start
            #if DEBUG
            print("[DEBUG] PracticeStore: Session paused (app backgrounded)")
            #endif
            
        case .resumeSession:
            // Resume when app returns from background - restart flow from beginning of current segment
            if isSessionActive {
                #if DEBUG
                print("[DEBUG] PracticeStore: Session resumed (app foregrounded)")
                #endif
                // Increment generation to signal dock to reset its timer
                incrementSegmentGeneration()
                // Restart flow from beginning of current affirmation
                startFlowForCurrentAffirmation()
            }
            
        // MARK: Session Summary Events
        case .dismissSummary:
            handleDismissSummary()
            
        case .repeatSession:
            handleRepeatSession()
            
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
            
        // MARK: TTS Events
        case .ttsStarted:
            break
            
        case .ttsProgress(let progress):
            handleTTSProgress(progress)
            
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
            #if DEBUG
            print("[ERROR] PracticeStore: Listening failed - \(error)")
            #endif
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
