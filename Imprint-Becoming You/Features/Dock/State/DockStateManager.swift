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
    
    /// Updates progress tracking and resets phase to idle.
    ///
    /// When navigating to a new affirmation, the phase must reset to `.idle`
    /// immediately so the progress bar shows 0 for the new segment, not the
    /// previous segment's completion state.
    func updateProgress(current: Int, total: Int) {
        let indexChanged = currentIndex != current
        
        currentIndex = current
        totalCount = total
        
        // Reset phase to idle when index changes
        // This prevents the new segment from briefly showing as complete
        if indexChanged {
            resetPhaseToIdle()
        }
    }
    
    /// Resets the current mode's phase to idle without changing modes.
    ///
    /// Called automatically when `updateProgress` detects an index change,
    /// ensuring the progress bar doesn't briefly flash complete on the new segment.
    private func resetPhaseToIdle() {
        switch state {
        case .home:
            break // Already idle
        case .readAloud:
            state = .readAloud(phase: .idle)
        case .readAndSpeak:
            state = .readAndSpeak(phase: .idle)
        case .speakOnly:
            state = .speakOnly(phase: .idle)
        }
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

#Preview("Dock State Manager - Progress Update") {
    struct PreviewWrapper: View {
        @State private var manager = DockStateManager()
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Index: \(manager.currentIndex) / \(manager.totalCount)")
                Text("State: \(String(describing: manager.state))")
                
                Button("Set Speak Only + Showing Score") {
                    manager.setMode(.speakOnly)
                    manager.updateSpeakOnlyPhase(.showingScore(score: 0.85))
                }
                
                Button("Update Progress (simulates navigation)") {
                    // This should reset phase to idle
                    manager.updateProgress(current: manager.currentIndex + 1, total: 5)
                }
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
