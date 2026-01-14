//
//  PracticeStore+RepeatSession.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/14/26.
//

import SwiftUI

// MARK: - Repeat Session with Configuration

extension PracticeStore {
    
    /// Repeats the session with user-specified configuration.
    ///
    /// Called from ResultsSummaryView when user taps "Repeat Session" with
    /// custom mode, loop count, and shuffle settings from the configuration bar.
    ///
    /// - Parameters:
    ///   - mode: The session mode to use for the repeat
    ///   - loopCount: Number of loops (1, 3, or 5)
    ///   - shuffle: Whether to shuffle affirmations
    func repeatSessionWithConfig(mode: SessionMode, loopCount: Int, shuffle: Bool) {
        // Set up loop configuration with user's choices
        var config = LoopConfiguration()
        config.loopCount = loopCount
        config.isShuffleEnabled = shuffle
        config.resetIteration()
        setLoopConfiguration(config)
        
        // Update session mode to user's selection
        sessionMode = mode
        
        // Reset session state for new playthrough
        setSessionState(index: 0)
        setSessionResults([])
        setSegmentProgress(0)
        sessionStartTime = Date()
        
        // Shuffle if enabled for the repeat
        if shuffle {
            shuffleSessionAffirmations()
        }
        
        // Set flow state based on new mode
        switch mode {
        case .readOnly:
            // Read Only shouldn't be selected in practice contexts, but handle gracefully
            setFlow(.home)
            return
        case .readAloud:
            setFlow(.readAloud(.idle))
        case .readThenSpeak:
            setFlow(.readAndSpeak(.idle))
        case .speakOnly:
            setFlow(.speakOnly(.idle))
        }
        
        // Dismiss summary and start
        withAnimation(.easeInOut(duration: PracticeTiming.summaryDismissDuration)) {
            setShowingSummary(false)
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: .milliseconds(Int(PracticeTiming.summaryDismissDuration * 1000) + 50))
            self.startFlowForCurrentAffirmation()
        }
        
        #if DEBUG
        print("[OK] PracticeStore: Repeating session with mode=\(mode.displayName), loops=\(loopCount), shuffle=\(shuffle)")
        #endif
    }
}
