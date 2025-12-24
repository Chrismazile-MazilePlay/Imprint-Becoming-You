//
//  AffirmationPhase.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import Foundation

// MARK: - AffirmationPhase

/// Represents the current phase of an affirmation during practice.
///
/// Used by AffirmationCardView to determine what UI to display.
enum AffirmationPhase: Equatable, Sendable {
    /// Affirmation is being displayed (idle state)
    case displaying
    
    /// TTS is playing the affirmation
    case playing
    
    /// Waiting for user to begin speaking
    case waitingToSpeak
    
    /// Listening to user speech
    case listening
    
    /// Analyzing the speech for resonance score
    case analyzing
    
    /// Showing the resonance score result
    case showingScore
}

// MARK: - Legacy Alias

/// Alias for backward compatibility with existing code
/// Some files may use `.speaking` instead of `.playing`
extension AffirmationPhase {
    /// Alias for `.playing` - TTS is speaking
    static var speaking: AffirmationPhase { .playing }
}
