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
    /// Follows the same instant-restart pattern as `handleRepeatSession()` —
    /// reuses the existing TTS cache (no loading screen, no re-synthesis).
    ///
    /// ## Cache Reuse Strategy
    /// - **No shuffle**: Cache is 100% valid — same affirmations, same order, same voice.
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
        
        // Invalidate stale completion handlers before state reset
        cancelCurrentActivity()
        flowGeneration += 1
        
        // Reset session state for new playthrough
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()
        
        // Handle shuffle — invalidate cache but preserve voice settings
        if shuffle {
            shuffleSessionAffirmations()
            
            // Update TTS queue with new affirmation order.
            // Clears cached audio (indices no longer match) but preserves
            // voice settings. On-demand synthesis handles each affirmation
            // during playback via speakText's fallback chain.
            let newOrder = sessionAffirmations.enumerated().map { index, affirmation in
                SessionAffirmationInfo(affirmation: affirmation, index: index)
            }
            dependencies.sessionTTSQueueService.invalidateCacheForShuffle(newOrder: newOrder)
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
        
        // After summary dismissal, start flow directly (no preparation needed).
        // TTS cache is reused — no loading screen.
        // incrementSegmentGeneration ensures dock timer starts in sync with flow.
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            guard !Task.isCancelled else { return }
            
            // Signal dock to start segment timer in sync with flow start
            self.incrementSegmentGeneration()
            self.startFlowForCurrentAffirmation()
        }
        
        HapticFeedback.notification(.success)
    }
}
