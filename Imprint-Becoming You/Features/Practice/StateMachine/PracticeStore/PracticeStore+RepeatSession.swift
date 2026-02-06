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
    /// Follows the same instant-restart pattern as `handleRepeatSession()` â€”
    /// reuses the existing TTS cache (no loading screen, no re-synthesis).
    ///
    /// ## Cache Reuse Strategy
    /// - **No shuffle**: Cache is 100% valid â€” same affirmations, same order, same voice.
    ///   Flow restarts instantly from index 0.
    /// - **Shuffle enabled**: Cache invalidated (indices no longer match) but voice settings
    ///   preserved. On-demand synthesis handles each affirmation during playback.
    /// - **Mode change**: Does not affect TTS cache. The flow logic determines whether
    ///   to play audio based on mode (Read Aloud plays TTS, Speak Only doesn't).
    ///
    /// - Parameters:
    ///   - mode: The session mode to use for the repeat
    ///   - loopCount: Number of loops (1, 3, or 5)
    ///   - shuffle: Whether to shuffle affirmations
    func handleRepeatSessionWithConfig(mode: SessionMode, loopCount: Int, shuffle: Bool) {
        // Close any open menus
        send(.closeSelectors)

        // Set up loop configuration with user's choices
        var config = LoopConfiguration()
        config.loopCount = loopCount
        config.isShuffleEnabled = shuffle
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
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()

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

        // Update session mode and set flow to idle for the new mode
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
        print("[OK] PracticeStore: Repeating session with mode=\(mode.displayName), loops=\(loopCount), shuffle=\(shuffle), voiceId: \(selectedVoiceId ?? "nil")")
        #endif

        // Dismiss summary first, then restart flow after animation completes
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }

        // Guard against rapid re-tap: capture flowGeneration so the delayed
        // callback becomes a no-op if the user taps repeat again before delay.
        let repeatGeneration = flowGeneration
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            guard !Task.isCancelled else { return }
            guard self.flowGeneration == repeatGeneration else { return }

            // Pre-configure audio session to .playback to eliminate
            // the 50-200ms HAL reconfiguration delay on first playback.
            await self.playbackCoordinator.preConfigureAudioSession()
            guard self.flowGeneration == repeatGeneration else { return }

            // Signal dock to start segment timer in sync with flow start
            self.incrementSegmentGeneration()
            self.startFlowForCurrentAffirmation()
        }

        HapticFeedback.notification(.success)
    }
}
