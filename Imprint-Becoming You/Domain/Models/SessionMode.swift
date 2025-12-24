//
//  SessionMode.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Session Mode

/// Available practice session modes.
///
/// Each mode provides a different interaction pattern for affirmation practice:
/// - **Read Only**: Silent browsing without audio or speech
/// - **Read Aloud**: TTS reads affirmations, user listens
/// - **Read & Speak**: TTS reads, then user repeats aloud
/// - **Speak Only**: User speaks affirmations without TTS prompt
///
/// ## Usage
/// ```swift
/// let mode: SessionMode = .readThenSpeak
/// print(mode.displayName)       // "Read & Speak"
/// print(mode.usesAudioOutput)   // true (uses TTS)
/// print(mode.usesAudioInput)    // true (uses microphone)
/// ```
enum SessionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case readOnly = "readOnly"
    case readAloud = "readAloud"
    case readThenSpeak = "readThenSpeak"
    case speakOnly = "speakOnly"
    
    var id: String { rawValue }
    
    // MARK: - Display Properties
    
    /// Human-readable name for UI display
    var displayName: String {
        switch self {
        case .readOnly: return "Read Only"
        case .readAloud: return "Read Aloud"
        case .readThenSpeak: return "Read & Speak"
        case .speakOnly: return "Speak Only"
        }
    }
    
    /// SF Symbol icon name for this mode
    var iconName: String {
        switch self {
        case .readOnly: return "book.fill"
        case .readAloud: return "speaker.wave.2.fill"
        case .readThenSpeak: return "mic.and.signal.meter.fill"
        case .speakOnly: return "mic.fill"
        }
    }
    
    /// Detailed description for mode selector
    var description: String {
        switch self {
        case .readOnly:
            return "Swipe through affirmations at your own pace"
        case .readAloud:
            return "Listen as affirmations are spoken to you"
        case .readThenSpeak:
            return "Hear the affirmation, then repeat it aloud"
        case .speakOnly:
            return "Read each affirmation aloud yourself"
        }
    }
    
    // MARK: - Capability Flags
    
    /// Whether this mode uses audio output (TTS)
    var usesAudioOutput: Bool {
        switch self {
        case .readOnly, .speakOnly:
            return false
        case .readAloud, .readThenSpeak:
            return true
        }
    }
    
    /// Whether this mode uses audio input (microphone)
    var usesAudioInput: Bool {
        switch self {
        case .readOnly, .readAloud:
            return false
        case .readThenSpeak, .speakOnly:
            return true
        }
    }
    
    /// Whether this mode uses text-to-speech
    /// Alias for usesAudioOutput for semantic clarity
    var usesTTS: Bool {
        usesAudioOutput
    }
    
    /// Whether this mode uses speech recognition
    /// Alias for usesAudioInput for semantic clarity
    var usesSpeechRecognition: Bool {
        usesAudioInput
    }
    
    /// Whether this mode auto-advances to next affirmation
    var autoAdvances: Bool {
        switch self {
        case .readOnly:
            return false
        case .readAloud, .readThenSpeak, .speakOnly:
            return true
        }
    }
    
    /// Whether this mode produces resonance scores
    var producesResonanceScore: Bool {
        usesAudioInput
    }
}
