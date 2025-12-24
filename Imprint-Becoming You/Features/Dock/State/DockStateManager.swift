//
//  DockStateManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import SwiftUI

// MARK: - DockStateManager

/// Manages the state of the adaptive bottom dock.
///
/// This observable class serves as the single source of truth for
/// the dock's current state, handling transitions between modes
/// and phases within modes.
///
/// ## Architecture
/// The manager uses a state machine pattern:
/// - `DockState` represents the current mode and phase
/// - `DockConfiguration` is derived from state for UI rendering
/// - State transitions are animated automatically
///
/// ## Usage
/// ```swift
/// @State private var dockManager = DockStateManager()
///
/// // Change to a new mode
/// dockManager.setMode(.speakOnly)
///
/// // Update phase within current mode
/// dockManager.updateSpeakOnlyPhase(.listening)
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
    /// - Parameter phase: The new TTS phase
    func updateReadAloudPhase(_ phase: TTSPhase) {
        guard case .readAloud = state else { return }
        withAnimation(AppTheme.Animation.quick) {
            state = .readAloud(phase: phase)
        }
    }
    
    /// Updates the phase within Read & Speak mode.
    /// - Parameter phase: The new interaction phase
    func updateReadAndSpeakPhase(_ phase: ReadAndSpeakPhase) {
        guard case .readAndSpeak = state else { return }
        withAnimation(AppTheme.Animation.quick) {
            state = .readAndSpeak(phase: phase)
        }
    }
    
    /// Updates the phase within Speak Only mode.
    /// - Parameter phase: The new interaction phase
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
    /// - Parameters:
    ///   - current: Current 0-based index
    ///   - total: Total number of items
    func updateProgress(current: Int, total: Int) {
        currentIndex = current
        totalCount = total
    }
    
    /// Updates real-time score.
    /// - Parameter score: Score value (0.0 - 1.0)
    func updateRealtimeScore(_ score: Double) {
        realtimeScore = score
    }
    
    // MARK: - Binaural Management
    
    /// Updates the binaural preset and closes selectors.
    /// - Parameter preset: The new binaural preset
    func updateBinauralPreset(_ preset: BinauralPreset) {
        withAnimation(AppTheme.Animation.standard) {
            binauralPreset = preset
            isModeSelectorExpanded = false
            isBinauralSelectorExpanded = false
        }
    }
}

// MARK: - Previews

#Preview("Dock State Manager") {
    struct PreviewWrapper: View {
        @State private var manager = DockStateManager()
        
        var body: some View {
            VStack(spacing: 20) {
                Text("State: \(manager.state.description)")
                    .font(.headline)
                
                Text("Mode: \(manager.currentMode.displayName)")
                Text("Height: \(manager.configuration.heightMultiplier, specifier: "%.1f")x")
                
                Divider()
                
                Button("Read Only") { manager.setMode(.readOnly) }
                Button("Read Aloud") { manager.setMode(.readAloud) }
                Button("Read & Speak") { manager.setMode(.readThenSpeak) }
                Button("Speak Only") { manager.setMode(.speakOnly) }
                
                Divider()
                
                if case .speakOnly = manager.state {
                    Button("→ Listening") { manager.updateSpeakOnlyPhase(.listening) }
                    Button("→ Analyzing") { manager.updateSpeakOnlyPhase(.analyzing) }
                    Button("→ Score 85%") { manager.updateSpeakOnlyPhase(.showingScore(score: 0.85)) }
                }
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
