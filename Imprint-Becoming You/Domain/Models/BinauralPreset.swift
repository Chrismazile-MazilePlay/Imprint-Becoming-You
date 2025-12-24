//
//  BinauralPreset.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Binaural Preset

/// Binaural beat presets for background audio.
///
/// Binaural beats are created by playing slightly different frequencies
/// in each ear, causing the brain to perceive a third "beat" frequency
/// that can influence mental states.
///
/// ## Frequency Ranges
/// - **Beta (14+ Hz)**: Focus, alertness, concentration
/// - **Alpha (8-14 Hz)**: Relaxation, calm, creativity
/// - **Theta (4-8 Hz)**: Deep relaxation, meditation, sleep onset
///
/// ## Usage
/// ```swift
/// let preset: BinauralPreset = .focus
/// print(preset.frequencyDifference) // 14.0 Hz
/// print(preset.leftFrequency)       // 200.0 Hz (carrier)
/// print(preset.rightFrequency)      // 214.0 Hz (carrier + difference)
/// ```
enum BinauralPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "off"
    case focus = "focus"
    case relax = "relax"
    case sleep = "sleep"
    
    var id: String { rawValue }
    
    // MARK: - Display Properties
    
    /// Human-readable name for UI display
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .focus: return "Focus"
        case .relax: return "Relax"
        case .sleep: return "Sleep"
        }
    }
    
    /// SF Symbol icon name for this preset
    var iconName: String {
        switch self {
        case .off: return "speaker.slash.fill"
        case .focus: return "brain.head.profile"
        case .relax: return "leaf.fill"
        case .sleep: return "moon.stars.fill"
        }
    }
    
    /// Detailed description for selector UI
    var description: String {
        switch self {
        case .off: return "No binaural beats"
        case .focus: return "Beta waves (14 Hz) for concentration"
        case .relax: return "Alpha waves (10 Hz) for calm"
        case .sleep: return "Theta waves (6 Hz) for rest"
        }
    }
    
    // MARK: - Audio Properties
    
    /// Frequency difference between left and right channels (Hz)
    ///
    /// This value is added to the carrier frequency for the right channel
    /// to create the binaural beat effect.
    var frequencyDifference: Float {
        switch self {
        case .off: return 0
        case .focus: return Constants.BinauralFrequencies.focus
        case .relax: return Constants.BinauralFrequencies.relax
        case .sleep: return Constants.BinauralFrequencies.sleep
        }
    }
    
    /// Left channel frequency (Hz) - the carrier frequency
    var leftFrequency: Float {
        Constants.Audio.binauralCarrierFrequency
    }
    
    /// Right channel frequency (Hz) - carrier + difference
    var rightFrequency: Float {
        Constants.Audio.binauralCarrierFrequency + frequencyDifference
    }
    
    /// Whether this preset produces audio
    var isActive: Bool {
        self != .off
    }
    
    /// Brain wave category for this preset
    var brainWaveType: String {
        switch self {
        case .off: return "None"
        case .focus: return "Beta"
        case .relax: return "Alpha"
        case .sleep: return "Theta"
        }
    }
}
