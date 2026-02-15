//
//  PracticeStore+RepeatSession.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - Repeat Session with Configuration

extension PracticeStore {
    
    /// Repeats the session with user-specified configuration from the summary dock.
    ///
    /// Called via `send(.repeatSessionWithConfig(...))` from `ResultsSummaryView`.
    ///
    /// ## Cache Reuse Strategy
    /// - **No shuffle**: Cache is 100% valid — same affirmations, same order, same voice.
    ///   Flow restarts instantly from index 0.
    /// - **Shuffle enabled**: Cache invalidated (indices no longer match) but voice settings
    ///   preserved. On-demand synthesis handles each affirmation during playback.
    /// - **Mode switch TO TTS mode without cache**: When switching from Speak Only
    ///   (no TTS audio) to Read Aloud or Read & Speak, shows the inline preparation
    ///   loading screen within the existing session cover to synthesize all affirmations
    ///   before starting playback. Uses `prepareAndStartSession(mode:)`.
    /// - **Mode switch WITH cache**: Direct start (instant restart, no loading screen).
    ///
    /// - Parameters:
    ///   - mode: The session mode to use for the repeat
    ///   - loopCount: Number of loops (1, 3, or 5)
    ///   - shuffle: Whether to shuffle affirmations
    ///   - spacedRepetition: Whether to expand with spaced repetition interleaving
    func handleRepeatSessionWithConfig(mode: SessionMode, loopCount: Int, shuffle: Bool, spacedRepetition: Bool) {
        // Close any open menus
        send(.closeSelectors)

        // Set up loop configuration with user's choices
        var config = LoopConfiguration()
        config.loopCount = loopCount
        config.isShuffleEnabled = shuffle
        config.isSpacedRepetitionEnabled = spacedRepetition
        config.resetIteration()
        setLoopConfiguration(config)

        // Reset session-scoped flags so next session uses proper voice
        forceSystemTTSForSession = false

        // Cancel any lingering flow tasks or audio from the previous session.
        cancelCurrentActivity()
        flowGeneration += 1

        // NOTE: Idle timer is already suppressed — showSessionSummary() no longer
        // resumes it. The timer stays suppressed through the summary lifecycle
        // and into the repeat session. It's only resumed when the session fully
        // ends (handleDismissSummary, handleExitSession, or handleResetToHome).

        // Reset session state for new playthrough
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()

        // For favorites sessions, filter out affirmations the user unfavorited
        // during the summary. This ensures the repeat only includes affirmations
        // the user still has favorited. TTS cache is keyed by UUID, so removing
        // entries doesn't require re-synthesis.
        if isFavoritesSession {
            // Deduplicate first (session may have been expanded by spaced rep)
            let uniqueFavorites = sessionAffirmations.uniqueByID()
            let stillFavorited = uniqueFavorites.filter { $0.isFavorited }

            if stillFavorited.isEmpty {
                // User unfavorited everything — cannot repeat.
                // Dismiss the cover; cleanup in onDismiss.
                HapticFeedback.notification(.warning)
                setSessionPresented(false)
                return
            }

            // Replace session affirmations with only the still-favorited ones
            clearOriginalSessionAffirmationIds()
            setSessionState(affirmations: stillFavorited, index: 0)

            // Apply spaced repetition expansion if enabled
            if spacedRepetition && stillFavorited.count > 1 {
                let expanded = SpacedRepetitionBuilder.expand(stillFavorited)
                setSessionAffirmationsForShuffle(expanded)

                let expandedInfos = expanded.enumerated().map { index, affirmation in
                    SessionAffirmationInfo(affirmation: affirmation, index: index)
                }
                dependencies.sessionTTSQueueService.updateAffirmationOrder(expandedInfos)
            } else {
                // Update TTS queue to reflect the filtered list (no expansion)
                let filteredOrder = stillFavorited.enumerated().map { index, affirmation in
                    SessionAffirmationInfo(affirmation: affirmation, index: index)
                }
                dependencies.sessionTTSQueueService.updateAffirmationOrder(filteredOrder)
            }
        } else {
            // Handle spaced repetition expansion/collapse for non-favorites repeat
            if spacedRepetition && !originalSessionAffirmationIds.isEmpty {
                // Collapse to unique base using original IDs, then expand
                let baseAffirmations: [Affirmation]
                if let repo = savedSessionRepository {
                    baseAffirmations = (try? repo.fetchAffirmations(byIds: originalSessionAffirmationIds))
                        ?? sessionAffirmations.uniqueByID()
                } else {
                    baseAffirmations = sessionAffirmations.uniqueByID()
                }

                // Reset to base, then expand with fresh random sequence
                setSessionAffirmationsForShuffle(baseAffirmations)
                setSessionState(index: 0)

                let expanded = SpacedRepetitionBuilder.expand(baseAffirmations)
                setSessionAffirmationsForShuffle(expanded)

                let expandedInfos = expanded.enumerated().map { index, affirmation in
                    SessionAffirmationInfo(affirmation: affirmation, index: index)
                }
                dependencies.sessionTTSQueueService.updateAffirmationOrder(expandedInfos)
            } else if !spacedRepetition
                      && sessionAffirmations.count > originalSessionAffirmationIds.count
                      && !originalSessionAffirmationIds.isEmpty {
                // Was expanded, now turned OFF — collapse to unique base
                let baseAffirmations: [Affirmation]
                if let repo = savedSessionRepository {
                    baseAffirmations = (try? repo.fetchAffirmations(byIds: originalSessionAffirmationIds))
                        ?? sessionAffirmations.uniqueByID()
                } else {
                    baseAffirmations = sessionAffirmations.uniqueByID()
                }

                setSessionAffirmationsForShuffle(baseAffirmations)
                setSessionState(index: 0)

                let collapsedInfos = baseAffirmations.enumerated().map { index, affirmation in
                    SessionAffirmationInfo(affirmation: affirmation, index: index)
                }
                dependencies.sessionTTSQueueService.updateAffirmationOrder(collapsedInfos)
            } else {
                setSessionState(index: 0)
            }
        }

        // Shuffle if enabled — cache remains valid (keyed by UUID, not index)
        if shuffle {
            shuffleSessionAffirmations()

            // Update TTS queue with new affirmation order.
            // Cache is keyed by affirmation UUID, so it remains fully valid
            // after reordering — no invalidation needed.
            let newOrder = sessionAffirmations.enumerated().map { index, affirmation in
                SessionAffirmationInfo(affirmation: affirmation, index: index)
            }
            dependencies.sessionTTSQueueService.updateAffirmationOrder(newOrder)
        }

        // Check if TTS preparation is needed (switching TO a TTS mode without cache).
        // When repeating from Speak Only → Read Aloud, no TTS audio exists yet.
        // The loading screen must appear inline within the session cover.
        let needsTTS = mode == .readAloud || mode == .readThenSpeak
        let hasCache = !sessionAffirmations.isEmpty
            && dependencies.sessionTTSQueueService.isReady(sessionAffirmations[0].id)

        // Update session mode and set flow to idle for the new mode.
        // Done BEFORE preparation so prepareAndStartSession reads the correct mode.
        sessionMode = mode
        switch mode {
        case .readAloud:
            setFlow(.readAloud(.idle))
        case .readThenSpeak:
            setFlow(.readAndSpeak(.idle))
        case .speakOnly:
            setFlow(.speakOnly(.idle))
        default:
            setFlow(.home)
        }

        #if DEBUG
        AppLogger.info("Repeating session with mode=\(mode.displayName), loops=\(loopCount), shuffle=\(shuffle), spacedRep=\(spacedRepetition), voiceId: \(selectedVoiceId ?? "nil"), needsTTS=\(needsTTS), hasCache=\(hasCache)", category: .practice)
        #endif

        if needsTTS && !hasCache {
            // TTS preparation needed — show loading screen inline.
            //
            // Set isPreparingSession = true BEFORE popping the summary so
            // SessionPreparationView (zIndex 25 in session root) is already
            // rendered underneath. The pop reveals it directly instead of
            // briefly showing bare session content.
            //
            // Only set the UI flags here (lightweight property assignments).
            // The actual synthesis work (prepareAndStartSession) is deferred
            // until after the pop animation to avoid blocking the transition.
            let totalCount = sessionAffirmations.count
            setPendingSessionMode(mode)
            setSessionPreparation(isActive: true, progress: 0, preparedCount: 0, target: totalCount)
            setSessionPreparationPhase(.waitingForKokoro)

            // Pop summary — reveals the already-showing loading screen.
            setShowingSummary(false)

            // Start actual TTS synthesis after the pop animation completes.
            let prepGeneration = flowGeneration
            Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
                guard !Task.isCancelled else { return }
                guard self.flowGeneration == prepGeneration else { return }
                self.prepareAndStartSession(mode: mode)
            }
        } else {
            // Pop summary from NavigationStack (cover stays presented).
            // SessionContainerView.onChange(of: store.isShowingSummary) handles the pop.
            setShowingSummary(false)

            // Cache exists or mode doesn't use TTS — direct start (instant restart)
            let repeatGeneration = flowGeneration
            Task { [weak self] in
                guard let self = self else { return }
                // Wait for NavigationStack pop animation to complete
                try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
                guard !Task.isCancelled else { return }
                guard self.flowGeneration == repeatGeneration else { return }

                // Session category is managed centrally by AudioSessionController.
                // No pre-configuration needed — .playback is guaranteed by
                // SpeechCaptureService.stopCapture() after mic use.

                // Signal dock to start segment timer in sync with flow start
                self.incrementSegmentGeneration()
                self.startFlowForCurrentAffirmation()
            }
        }

        HapticFeedback.notification(.success)
    }
}
