//
//  DockConfiguration.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - DockConfiguration

/// Configuration for what the dock should display in its current state.
///
/// This is computed from the `DockState` and tells the UI exactly
/// what components to render. Acts as a "view state" derived from
/// the underlying state machine.
///
/// ## Usage
/// ```swift
/// let config = DockConfiguration.readAndSpeak(phase: .listening)
/// if config.showMicIndicator {
///     MicrophoneIndicator(isListening: config.isListening)
/// }
/// ```
struct DockConfiguration: Equatable, Sendable {
    
    // MARK: - Visibility Flags
    
    /// Show the mode selector button
    let showModeSelector: Bool
    
    /// Show the binaural selector button
    let showBinauralSelector: Bool
    
    /// Show progress indicator (dots or fraction)
    let showProgress: Bool
    
    /// Show navigation arrows (prev/next)
    let showNavigation: Bool
    
    /// Show the microphone indicator
    let showMicIndicator: Bool
    
    /// Show the real-time/final score display
    let showScoreDisplay: Bool
    
    /// Show TTS/speaking status indicator
    let showTTSIndicator: Bool
    
    /// Show current mode label
    let showModeLabel: Bool
    
    // MARK: - State Values
    
    /// Whether mic is actively listening
    let isListening: Bool
    
    /// Whether TTS is currently playing
    let isTTSSpeaking: Bool
    
    /// Current score to display (if showing)
    let currentScore: Double?
    
    /// Current mode label text
    let modeLabel: String?
    
    // MARK: - Layout
    
    /// Height multiplier for dock (1.0 = compact, 2.0 = expanded)
    let heightMultiplier: CGFloat
    
    // MARK: - Factory Methods
    
    /// Configuration for home/browse state
    static var home: DockConfiguration {
        DockConfiguration(
            showModeSelector: true,
            showBinauralSelector: true,
            showProgress: false,
            showNavigation: false,
            showMicIndicator: false,
            showScoreDisplay: false,
            showTTSIndicator: false,
            showModeLabel: false,
            isListening: false,
            isTTSSpeaking: false,
            currentScore: nil,
            modeLabel: nil,
            heightMultiplier: 1.0
        )
    }
    
    /// Configuration for Read Aloud mode
    /// - Parameter phase: Current TTS phase
    /// - Returns: Dock configuration for this phase
    static func readAloud(phase: TTSPhase) -> DockConfiguration {
        DockConfiguration(
            showModeSelector: true,
            showBinauralSelector: true,
            showProgress: true,
            showNavigation: true,
            showMicIndicator: false,
            showScoreDisplay: false,
            showTTSIndicator: true,
            showModeLabel: true,
            isListening: false,
            isTTSSpeaking: phase == .speaking,
            currentScore: nil,
            modeLabel: "Read Aloud",
            heightMultiplier: 1.5
        )
    }
    
    /// Configuration for Read & Speak mode
    /// - Parameter phase: Current interaction phase
    /// - Returns: Dock configuration for this phase
    static func readAndSpeak(phase: ReadAndSpeakPhase) -> DockConfiguration {
        let isListening = phase == .listening
        let isSpeaking = phase == .ttsPlaying
        let score: Double? = {
            if case .showingScore(let s) = phase { return s }
            return nil
        }()
        
        return DockConfiguration(
            showModeSelector: true,
            showBinauralSelector: true,
            showProgress: true,
            showNavigation: true,
            showMicIndicator: isListening || phase == .waitingForUser,
            showScoreDisplay: score != nil,
            showTTSIndicator: isSpeaking,
            showModeLabel: true,
            isListening: isListening,
            isTTSSpeaking: isSpeaking,
            currentScore: score,
            modeLabel: "Read & Speak",
            heightMultiplier: 1.8
        )
    }
    
    /// Configuration for Speak Only mode
    /// - Parameter phase: Current interaction phase
    /// - Returns: Dock configuration for this phase
    static func speakOnly(phase: SpeakPhase) -> DockConfiguration {
        let isListening = phase == .listening
        let score: Double? = {
            if case .showingScore(let s) = phase { return s }
            return nil
        }()
        
        return DockConfiguration(
            showModeSelector: true,
            showBinauralSelector: true,
            showProgress: true,
            showNavigation: true,
            showMicIndicator: true,
            showScoreDisplay: score != nil || isListening,
            showTTSIndicator: false,
            showModeLabel: true,
            isListening: isListening,
            isTTSSpeaking: false,
            currentScore: score,
            modeLabel: "Speak Only",
            heightMultiplier: 1.8
        )
    }
}
