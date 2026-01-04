//
//  PracticeState.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/3/26.
//

import Foundation

// MARK: - Practice Flow

/// The complete state of the practice experience.
///
/// This is a hierarchical state machine where the top-level state determines
/// which mode we're in, and each mode has its own phase sub-states.
///
/// ## State Hierarchy
/// ```
/// PracticeFlow
/// ├── home (browsing, no active session)
/// ├── readAloud
/// │   ├── idle
/// │   ├── playing(progress)
/// │   └── complete
/// ├── readAndSpeak
/// │   ├── idle
/// │   ├── ttsPlaying(progress)
/// │   ├── waitingForUser
/// │   ├── listening(context)
/// │   ├── analyzing
/// │   └── showingScore(result)
/// └── speakOnly
///     ├── idle
///     ├── listening(context)
///     ├── analyzing
///     └── showingScore(result)
/// ```
///
/// ## Design Decisions
/// - Associated values carry all context needed for that phase
/// - No separate "isPlaying" / "isListening" booleans - phase IS the truth
/// - Score display includes full breakdown, not just final score
enum PracticeFlow: Equatable, Sendable {
    
    /// Home state - user is browsing in Read Only mode
    case home
    
    /// Read Aloud mode - TTS speaks, user listens
    case readAloud(ReadAloudFlowPhase)
    
    /// Read & Speak mode - TTS speaks, then user repeats
    case readAndSpeak(ReadAndSpeakFlowPhase)
    
    /// Speak Only mode - user speaks without TTS prompt
    case speakOnly(SpeakOnlyFlowPhase)
}

// MARK: - Read Aloud Flow Phase

/// Phases within Read Aloud mode.
///
/// Simple linear flow: idle → playing → complete → (auto-advance)
enum ReadAloudFlowPhase: Equatable, Sendable {
    
    /// Waiting to start TTS playback
    case idle
    
    /// TTS is actively playing
    /// - Parameter progress: Playback progress (0.0 - 1.0)
    case playing(progress: Double)
    
    /// TTS finished, brief pause before auto-advance
    case complete
}

// MARK: - Read And Speak Flow Phase

/// Phases within Read & Speak mode.
///
/// Full interaction cycle with TTS prompt followed by user speech.
enum ReadAndSpeakFlowPhase: Equatable, Sendable {
    
    /// Waiting to start the cycle
    case idle
    
    /// TTS is reading the affirmation
    /// - Parameter progress: Playback progress (0.0 - 1.0)
    case ttsPlaying(progress: Double)
    
    /// TTS finished, waiting for user to begin speaking
    case waitingForUser
    
    /// Actively listening to user's speech
    /// - Parameter context: Live listening metrics
    case listening(ListeningContext)
    
    /// Processing speech and computing score
    case analyzing
    
    /// Displaying the resonance score
    /// - Parameter result: Complete score breakdown
    case showingScore(ScoreResult)
}

// MARK: - Speak Only Flow Phase

/// Phases within Speak Only mode.
///
/// Direct user speech without TTS prompt.
enum SpeakOnlyFlowPhase: Equatable, Sendable {
    
    /// Waiting for user to start speaking
    case idle
    
    /// Actively listening to user's speech
    /// - Parameter context: Live listening metrics
    case listening(ListeningContext)
    
    /// Processing speech and computing score
    case analyzing
    
    /// Displaying the resonance score
    /// - Parameter result: Complete score breakdown
    case showingScore(ScoreResult)
}

// MARK: - Listening Context

/// Real-time context during speech listening.
///
/// Updated continuously while the user is speaking to provide
/// live feedback in the UI (waveform, energy meter, etc.)
struct ListeningContext: Equatable, Sendable {
    
    /// Duration the user has been speaking
    let elapsed: TimeInterval
    
    /// Current audio level (0.0 - 1.0), smoothed for display
    let audioLevel: Double
    
    /// Recognized text so far (may be partial)
    let recognizedText: String
    
    /// Initial state for when listening begins
    static let initial = ListeningContext(
        elapsed: 0,
        audioLevel: 0,
        recognizedText: ""
    )
}

// MARK: - Score Result

/// Complete resonance score with breakdown.
///
/// Contains everything needed to display the score UI and
/// persist the record to SwiftData.
struct ScoreResult: Equatable, Sendable {
    
    /// Final composite score (0.0 - 1.0)
    let score: Double
    
    /// Individual scoring components
    let components: ScoreComponents
    
    /// Duration of the spoken affirmation
    let duration: TimeInterval
    
    /// The session mode used (for persistence)
    let mode: SessionMode
    
    /// Recognized text from speech recognition
    let recognizedText: String
    
    /// Qualitative rating derived from score
    var rating: ResonanceRating {
        ResonanceRating(score: Float(score))
    }
    
    /// Score as integer percentage (0-100)
    var percentScore: Int {
        Int(score * 100)
    }
    
    /// Converts to a ResonanceRecord for persistence
    func toRecord() -> ResonanceRecord {
        ResonanceRecord(
            finalScore: Float(score),
            textAccuracy: Float(components.textAccuracy),
            vocalEnergy: Float(components.vocalEnergy),
            pitchStability: Float(components.pitchStability),
            sessionMode: mode,
            duration: duration
        )
    }
}

// MARK: - Score Components

/// Individual components that make up the resonance score.
///
/// These are kept as separate values for:
/// 1. Displaying breakdown in UI
/// 2. Showing improvement areas
/// 3. Analytics and progress tracking
struct ScoreComponents: Equatable, Sendable {
    
    /// Text accuracy (0.0 - 1.0)
    /// How closely spoken words matched the expected affirmation
    let textAccuracy: Double
    
    /// Vocal energy (0.0 - 1.0)
    /// RMS energy relative to user's calibrated baseline
    let vocalEnergy: Double
    
    /// Pitch stability (0.0 - 1.0)
    /// Consistency of vocal pitch throughout
    let pitchStability: Double
    
    /// Sample components for previews
    static let sample = ScoreComponents(
        textAccuracy: 0.92,
        vocalEnergy: 0.78,
        pitchStability: 0.85
    )
    
    /// Perfect score components
    static let perfect = ScoreComponents(
        textAccuracy: 1.0,
        vocalEnergy: 1.0,
        pitchStability: 1.0
    )
}

// MARK: - Navigation Direction

/// Direction for pager navigation.
///
/// Used for both user-initiated swipes and auto-advance.
enum NavigationDirection: Equatable, Sendable {
    case next
    case previous
}

// MARK: - PracticeFlow Extensions

extension PracticeFlow {
    
    // MARK: - Mode Queries
    
    /// Whether this is the home/browse state
    var isHome: Bool {
        if case .home = self { return true }
        return false
    }
    
    /// Whether this is an active session mode (not home)
    var isActiveMode: Bool {
        !isHome
    }
    
    /// The session mode this flow represents
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
    
    // MARK: - Phase Queries
    
    /// Whether TTS is currently playing
    var isTTSPlaying: Bool {
        switch self {
        case .readAloud(.playing):
            return true
        case .readAndSpeak(.ttsPlaying):
            return true
        default:
            return false
        }
    }
    
    /// Whether we're actively listening to user speech
    var isListening: Bool {
        switch self {
        case .readAndSpeak(.listening):
            return true
        case .speakOnly(.listening):
            return true
        default:
            return false
        }
    }
    
    /// Whether we're analyzing speech
    var isAnalyzing: Bool {
        switch self {
        case .readAndSpeak(.analyzing):
            return true
        case .speakOnly(.analyzing):
            return true
        default:
            return false
        }
    }
    
    /// Whether we're showing a score
    var isShowingScore: Bool {
        switch self {
        case .readAndSpeak(.showingScore):
            return true
        case .speakOnly(.showingScore):
            return true
        default:
            return false
        }
    }
    
    /// Whether we're in an idle phase (ready to start)
    var isIdle: Bool {
        switch self {
        case .home:
            return true
        case .readAloud(.idle):
            return true
        case .readAndSpeak(.idle):
            return true
        case .speakOnly(.idle):
            return true
        default:
            return false
        }
    }
    
    /// Whether navigation should be blocked (during score display)
    var shouldBlockNavigation: Bool {
        isShowingScore
    }
    
    // MARK: - Audio Level Access
    
    /// Current audio level if listening, otherwise nil
    var currentAudioLevel: Double? {
        switch self {
        case .readAndSpeak(.listening(let context)):
            return context.audioLevel
        case .speakOnly(.listening(let context)):
            return context.audioLevel
        default:
            return nil
        }
    }
    
    /// Current listening context if listening, otherwise nil
    var listeningContext: ListeningContext? {
        switch self {
        case .readAndSpeak(.listening(let context)):
            return context
        case .speakOnly(.listening(let context)):
            return context
        default:
            return nil
        }
    }
    
    // MARK: - Score Access
    
    /// Current score result if showing score, otherwise nil
    var scoreResult: ScoreResult? {
        switch self {
        case .readAndSpeak(.showingScore(let result)):
            return result
        case .speakOnly(.showingScore(let result)):
            return result
        default:
            return nil
        }
    }
    
    // MARK: - TTS Progress Access
    
    /// Current TTS playback progress if playing, otherwise nil
    var ttsProgress: Double? {
        switch self {
        case .readAloud(.playing(let progress)):
            return progress
        case .readAndSpeak(.ttsPlaying(let progress)):
            return progress
        default:
            return nil
        }
    }
}

// MARK: - Debug Descriptions

extension PracticeFlow: CustomStringConvertible {
    var description: String {
        switch self {
        case .home:
            return "home"
        case .readAloud(let phase):
            return "readAloud(\(phase))"
        case .readAndSpeak(let phase):
            return "readAndSpeak(\(phase))"
        case .speakOnly(let phase):
            return "speakOnly(\(phase))"
        }
    }
}

extension ReadAloudFlowPhase: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "idle"
        case .playing(let progress): return "playing(\(Int(progress * 100))%)"
        case .complete: return "complete"
        }
    }
}

extension ReadAndSpeakFlowPhase: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "idle"
        case .ttsPlaying(let progress): return "ttsPlaying(\(Int(progress * 100))%)"
        case .waitingForUser: return "waitingForUser"
        case .listening(let ctx): return "listening(\(String(format: "%.1f", ctx.elapsed))s)"
        case .analyzing: return "analyzing"
        case .showingScore(let result): return "showingScore(\(result.percentScore)%)"
        }
    }
}

extension SpeakOnlyFlowPhase: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "idle"
        case .listening(let ctx): return "listening(\(String(format: "%.1f", ctx.elapsed))s)"
        case .analyzing: return "analyzing"
        case .showingScore(let result): return "showingScore(\(result.percentScore)%)"
        }
    }
}
