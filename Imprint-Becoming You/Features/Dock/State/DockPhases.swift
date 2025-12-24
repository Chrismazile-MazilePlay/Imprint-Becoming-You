//
//  DockPhases.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - TTS Phase

/// Phases within Read Aloud mode.
///
/// Tracks the lifecycle of TTS playback:
/// 1. `idle` - Waiting to start
/// 2. `speaking` - TTS is actively playing
/// 3. `complete` - TTS finished, ready for next
enum TTSPhase: Equatable, Sendable {
    /// Waiting to start TTS playback
    case idle
    
    /// TTS is actively speaking
    case speaking
    
    /// TTS playback completed
    case complete
}

// MARK: - Read And Speak Phase

/// Phases within Read & Speak mode.
///
/// Tracks the full interaction cycle:
/// 1. `idle` - Waiting to start
/// 2. `ttsPlaying` - AI voice reading the affirmation
/// 3. `waitingForUser` - Prompt for user to speak
/// 4. `listening` - Capturing user's speech
/// 5. `analyzing` - Computing resonance score
/// 6. `showingScore` - Displaying final score
enum ReadAndSpeakPhase: Equatable, Sendable {
    /// Waiting to start the cycle
    case idle
    
    /// TTS is reading the affirmation aloud
    case ttsPlaying
    
    /// Waiting for user to begin speaking
    case waitingForUser
    
    /// Actively listening to user's speech
    case listening
    
    /// Processing speech and computing score
    case analyzing
    
    /// Displaying the final resonance score
    case showingScore(score: Double)
}

// MARK: - Speak Phase

/// Phases within Speak Only mode.
///
/// Simplified cycle without TTS:
/// 1. `idle` - Waiting to start
/// 2. `listening` - Capturing user's speech
/// 3. `analyzing` - Computing resonance score
/// 4. `showingScore` - Displaying final score
enum SpeakPhase: Equatable, Sendable {
    /// Waiting to start listening
    case idle
    
    /// Actively listening to user's speech
    case listening
    
    /// Processing speech and computing score
    case analyzing
    
    /// Displaying the final resonance score
    case showingScore(score: Double)
}
