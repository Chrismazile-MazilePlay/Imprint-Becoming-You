//
//  DockState.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/21/25.
//

import SwiftUI

// MARK: - DockState

/// Represents the current state of the adaptive bottom dock.
///
/// The dock morphs its appearance and controls based on the current
/// practice mode and phase within that mode.
enum DockState: Equatable {
    /// Home state - user is browsing in Read Only mode
    case home
    
    /// Read Aloud mode - TTS is playing
    case readAloud(phase: TTSPhase)
    
    /// Read & Speak mode - TTS then user speaks
    case readAndSpeak(phase: ReadAndSpeakPhase)
    
    /// Speak Only mode - user speaks without TTS
    case speakOnly(phase: SpeakPhase)
    
    /// Whether this is the home/browse state
    var isHome: Bool {
        if case .home = self { return true }
        return false
    }
    
    /// Whether this is an active session mode (not home)
    var isActiveMode: Bool {
        !isHome
    }
    
    /// The session mode this state represents
    var sessionMode: SessionMode {
        switch self {
        case .home:
            return .readOnly
        case .readAloud:
            return .readAloud
        case .readAndSpeak:
            return .readThenSpeak
        case .speakOnly:
            return .speakOnly
        }
    }
}

// MARK: - Phase Enums

/// Phases within Read Aloud mode
enum TTSPhase: Equatable {
    case idle
    case speaking
    case complete
}

/// Phases within Read & Speak mode
enum ReadAndSpeakPhase: Equatable {
    case idle
    case ttsPlaying
    case waitingForUser
    case listening
    case analyzing
    case showingScore(score: Double)
}

/// Phases within Speak Only mode
enum SpeakPhase: Equatable {
    case idle
    case listening
    case analyzing
    case showingScore(score: Double)
}

// MARK: - DockConfiguration

/// Configuration for what the dock should display in its current state.
///
/// This is computed from the DockState and tells the UI exactly
/// what components to render.
struct DockConfiguration: Equatable {
    
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

// MARK: - DockStateManager

/// Manages the state of the adaptive bottom dock.
///
/// This observable class serves as the single source of truth for
/// the dock's current state, handling transitions between modes
/// and phases within modes.
///
/// ## Usage
/// ```swift
/// @State private var dockManager = DockStateManager()
///
/// // Change to a new mode
/// dockManager.setMode(.speakOnly)
///
/// // Update phase within current mode
/// dockManager.updatePhase(.listening)
///
/// // Return to home
/// dockManager.returnToHome()
/// ```
@Observable
final class DockStateManager {
    
    // MARK: - Published State
    
    /// Current dock state
    private(set) var state: DockState = .home
    
    /// Current configuration derived from state
    var configuration: DockConfiguration {
        switch state {
        case .home:
            return .home
        case .readAloud(let phase):
            return .readAloud(phase: phase)
        case .readAndSpeak(let phase):
            return .readAndSpeak(phase: phase)
        case .speakOnly(let phase):
            return .speakOnly(phase: phase)
        }
    }
    
    /// Whether mode selector is expanded
    var isModeSelectorExpanded: Bool = false
    
    /// Whether binaural selector is expanded
    var isBinauralSelectorExpanded: Bool = false
    
    /// Current progress (0-based index)
    var currentIndex: Int = 0
    
    /// Total count for progress
    var totalCount: Int = 0
    
    /// Current real-time score (0.0 - 1.0)
    var realtimeScore: Double = 0.0
    
    /// Current binaural preset
    var binauralPreset: BinauralPreset = .off
    
    // MARK: - Computed Properties
    
    /// Progress as a fraction string (e.g., "3 / 10")
    var progressText: String {
        "\(currentIndex + 1) / \(totalCount)"
    }
    
    /// Progress as a percentage (0.0 - 1.0)
    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(currentIndex + 1) / Double(totalCount)
    }
    
    /// Whether we're in an active (non-home) mode
    var isInActiveMode: Bool {
        state.isActiveMode
    }
    
    /// Current session mode
    var currentMode: SessionMode {
        state.sessionMode
    }
    
    // MARK: - Mode Transitions
    
    /// Sets a new session mode, transitioning the dock state.
    ///
    /// - Parameter mode: The session mode to switch to
    func setMode(_ mode: SessionMode) {
        withAnimation(AppTheme.Animation.standard) {
            switch mode {
            case .readOnly:
                state = .home
            case .readAloud:
                state = .readAloud(phase: .idle)
            case .readThenSpeak:
                state = .readAndSpeak(phase: .idle)
            case .speakOnly:
                state = .speakOnly(phase: .idle)
            }
            
            // Close any open selectors
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
    
    /// Returns to home state (Read Only mode).
    func returnToHome() {
        withAnimation(AppTheme.Animation.standard) {
            state = .home
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
    
    // MARK: - Phase Updates
    
    /// Updates the phase within Read Aloud mode.
    func updateReadAloudPhase(_ phase: TTSPhase) {
        guard case .readAloud = state else { return }
        withAnimation(AppTheme.Animation.quick) {
            state = .readAloud(phase: phase)
        }
    }
    
    /// Updates the phase within Read & Speak mode.
    func updateReadAndSpeakPhase(_ phase: ReadAndSpeakPhase) {
        guard case .readAndSpeak = state else { return }
        withAnimation(AppTheme.Animation.quick) {
            state = .readAndSpeak(phase: phase)
        }
    }
    
    /// Updates the phase within Speak Only mode.
    func updateSpeakOnlyPhase(_ phase: SpeakPhase) {
        guard case .speakOnly = state else { return }
        withAnimation(AppTheme.Animation.quick) {
            state = .speakOnly(phase: phase)
        }
    }
    
    // MARK: - Selector Management
    
    /// Toggles the mode selector expansion.
    func toggleModeSelector() {
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded.toggle()
            if isModeSelectorExpanded {
                isBinauralSelectorExpanded = false
            }
        }
    }
    
    /// Toggles the binaural selector expansion.
    func toggleBinauralSelector() {
        withAnimation(AppTheme.Animation.standard) {
            isBinauralSelectorExpanded.toggle()
            if isBinauralSelectorExpanded {
                isModeSelectorExpanded = false
            }
        }
    }
    
    /// Closes all selectors.
    func closeSelectors() {
        withAnimation(AppTheme.Animation.standard) {
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
    
    // MARK: - Progress Management
    
    /// Updates progress tracking.
    func updateProgress(current: Int, total: Int) {
        currentIndex = current
        totalCount = total
    }
    
    /// Updates real-time score.
    func updateRealtimeScore(_ score: Double) {
        realtimeScore = score
    }
    
    // MARK: - Binaural Management
    
    /// Updates the binaural preset and closes selectors.
    func updateBinauralPreset(_ preset: BinauralPreset) {
        withAnimation(AppTheme.Animation.standard) {
            binauralPreset = preset
            // Close any open selectors
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
}

// MARK: - Previews

#Preview("Dock State Manager - Home") {
    struct PreviewWrapper: View {
        @State private var manager = DockStateManager()
        
        var body: some View {
            VStack(spacing: 20) {
                Text("State: \(String(describing: manager.state))")
                Text("Config height: \(manager.configuration.heightMultiplier)")
                
                Button("Switch to Read Aloud") {
                    manager.setMode(.readAloud)
                }
                
                Button("Switch to Speak Only") {
                    manager.setMode(.speakOnly)
                }
                
                Button("Return Home") {
                    manager.returnToHome()
                }
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
