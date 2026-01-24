//
//  VoiceCloneServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Voice Clone Service Protocol

/// Protocol for voice cloning via Qwen DashScope API.
///
/// ## Cloning Flow
/// 1. User records audio (3+ seconds via VoiceCalibrationService)
/// 2. Validate with `validateAudio(_:)`
/// 3. Preview during onboarding with `previewClone(audioData:sampleText:)`
/// 4. Create permanent clone with `createClone(from:name:)` after subscription
///
/// ## Usage
/// ```swift
/// // Validate audio
/// let validation = await service.validateAudio(calibrationAudio)
/// guard validation.isValid else { return }
///
/// // Preview (onboarding)
/// let preview = try await service.previewClone(
///     audioData: calibrationAudio,
///     sampleText: "I am confident and capable."
/// )
///
/// // Create permanent clone (requires premium)
/// let voice = try await service.createClone(from: calibrationAudio, name: "My Voice")
/// ```
protocol VoiceCloneServiceProtocol: AnyObject, Sendable {
    
    // MARK: - Clone Creation
    
    /// Creates a permanent voice clone from audio.
    ///
    /// Requires premium subscription. Processing takes 5-15 seconds.
    ///
    /// - Parameters:
    ///   - audioData: Audio sample (minimum 3 seconds)
    ///   - name: Display name for the clone
    ///   - languageCode: BCP 47 language code
    /// - Returns: Voice configured to use the clone
    /// - Throws: `TTSError.cloningFailed` if creation fails
    func createClone(
        from audioData: Data,
        name: String,
        languageCode: String
    ) async throws -> Voice
    
    /// Generates a preview without creating a permanent clone.
    ///
    /// Used during onboarding to demonstrate voice cloning.
    ///
    /// - Parameters:
    ///   - audioData: Audio sample
    ///   - sampleText: Text to synthesize for preview
    /// - Returns: TTS result with preview audio
    /// - Throws: `TTSError.cloningFailed` if preview fails
    func previewClone(audioData: Data, sampleText: String) async throws -> TTSResult
    
    // MARK: - Clone Management
    
    /// Deletes a voice clone.
    func deleteClone(voiceId: String) async throws
    
    /// Gets clone status.
    func getCloneStatus(voiceId: String) async throws -> VoiceCloneStatus
    
    /// Lists all user clones.
    func listClones() async throws -> [Voice]
    
    // MARK: - Audio Validation
    
    /// Validates audio for cloning suitability.
    func validateAudio(_ audioData: Data) async -> CloneAudioValidation
}

// MARK: - Default Implementations

extension VoiceCloneServiceProtocol {
    
    func createClone(from audioData: Data, name: String = "My Voice") async throws -> Voice {
        try await createClone(from: audioData, name: name, languageCode: "en-US")
    }
}

// MARK: - Voice Clone Status

enum VoiceCloneStatus: String, Codable, Sendable {
    case processing
    case ready
    case failed
    case deleted
    case expired
    
    var isUsable: Bool { self == .ready }
    
    var displayMessage: String {
        switch self {
        case .processing: return "Creating your voice clone..."
        case .ready: return "Your voice clone is ready"
        case .failed: return "Voice clone creation failed"
        case .deleted: return "Voice clone was deleted"
        case .expired: return "Voice clone expired"
        }
    }
}

// MARK: - Clone Audio Validation

struct CloneAudioValidation: Sendable {
    let isValid: Bool
    let duration: TimeInterval
    let qualityScore: Float
    let issues: [CloneAudioIssue]
    let suggestions: [String]
    
    var canProceedWithWarnings: Bool {
        issues.allSatisfy { $0.severity != .error }
    }
    
    static func valid(duration: TimeInterval, qualityScore: Float = 0.8) -> CloneAudioValidation {
        CloneAudioValidation(
            isValid: true,
            duration: duration,
            qualityScore: qualityScore,
            issues: [],
            suggestions: []
        )
    }
    
    static func invalid(duration: TimeInterval, issues: [CloneAudioIssue]) -> CloneAudioValidation {
        CloneAudioValidation(
            isValid: false,
            duration: duration,
            qualityScore: 0.0,
            issues: issues,
            suggestions: issues.map { $0.suggestion }
        )
    }
}

// MARK: - Clone Audio Issue

struct CloneAudioIssue: Sendable {
    let type: CloneAudioIssueType
    let severity: CloneAudioIssueSeverity
    let message: String
    
    var suggestion: String {
        switch type {
        case .tooShort: return "Record at least 3 seconds of audio"
        case .tooLong: return "Audio will be trimmed to 60 seconds"
        case .backgroundNoise: return "Find a quieter environment"
        case .lowVolume: return "Speak louder or move closer to the microphone"
        case .clipping: return "Speak softer to avoid distortion"
        case .multipleSpeakers: return "Ensure only one person is speaking"
        case .unsupportedFormat: return "Use M4A, WAV, or MP3 format"
        case .corruptedAudio: return "Try recording again"
        }
    }
}

enum CloneAudioIssueType: String, Sendable {
    case tooShort
    case tooLong
    case backgroundNoise
    case lowVolume
    case clipping
    case multipleSpeakers
    case unsupportedFormat
    case corruptedAudio
}

enum CloneAudioIssueSeverity: String, Sendable {
    case error    // Prevents cloning
    case warning  // May reduce quality
    case info     // Informational
}

// MARK: - Clone Configuration

enum VoiceCloneConfiguration {
    static let minimumDuration: TimeInterval = 3.0
    static let recommendedDuration: TimeInterval = 10.0
    static let maximumDuration: TimeInterval = 60.0
    static let supportedFormats: Set<String> = ["m4a", "wav", "mp3", "aac"]
    static let minimumQualityScore: Float = 0.5
    
    static func isDurationValid(_ duration: TimeInterval) -> Bool {
        duration >= minimumDuration && duration <= maximumDuration
    }
}
