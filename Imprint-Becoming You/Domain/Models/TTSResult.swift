//
//  TTSResult.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation

// MARK: - TTS Result

/// Result of a text-to-speech synthesis operation.
struct TTSResult: Sendable {
    
    let audioData: Data
    let audioFormat: TTSAudioFormat
    let duration: TimeInterval
    let originalText: String
    let voice: Voice
    let wordTimings: [WordTiming]
    let source: TTSResultSource
    let synthesizedAt: Date
    
    init(
        audioData: Data,
        audioFormat: TTSAudioFormat,
        duration: TimeInterval,
        originalText: String,
        voice: Voice,
        wordTimings: [WordTiming] = [],
        source: TTSResultSource = .synthesized,
        synthesizedAt: Date = Date()
    ) {
        self.audioData = audioData
        self.audioFormat = audioFormat
        self.duration = duration
        self.originalText = originalText
        self.voice = voice
        self.wordTimings = wordTimings
        self.source = source
        self.synthesizedAt = synthesizedAt
    }
}

// MARK: - TTS Audio Format

enum TTSAudioFormat: String, Codable, Sendable {
    case wav
    case mp3
    case aac
    case linearPCM
    
    var mimeType: String {
        switch self {
        case .wav: return "audio/wav"
        case .mp3: return "audio/mpeg"
        case .aac: return "audio/aac"
        case .linearPCM: return "audio/pcm"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .mp3: return "mp3"
        case .aac: return "m4a"
        case .linearPCM: return "pcm"
        }
    }
}

// MARK: - TTS Result Source

enum TTSResultSource: String, Codable, Sendable {
    case synthesized
    case cached
    case pregenerated
}

// MARK: - Word Timing

/// Timing info for word-level sync with audio playback.
struct WordTiming: Codable, Sendable {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let characterRange: Range<Int>
    
    var duration: TimeInterval {
        endTime - startTime
    }
    
    // MARK: - Codable (Range workaround)
    
    enum CodingKeys: String, CodingKey {
        case word, startTime, endTime
        case characterRangeLowerBound, characterRangeUpperBound
    }
    
    init(word: String, startTime: TimeInterval, endTime: TimeInterval, characterRange: Range<Int>) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.characterRange = characterRange
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decode(String.self, forKey: .word)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        let lower = try container.decode(Int.self, forKey: .characterRangeLowerBound)
        let upper = try container.decode(Int.self, forKey: .characterRangeUpperBound)
        characterRange = lower..<upper
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(word, forKey: .word)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(characterRange.lowerBound, forKey: .characterRangeLowerBound)
        try container.encode(characterRange.upperBound, forKey: .characterRangeUpperBound)
    }
}

// MARK: - TTS Error

enum TTSError: LocalizedError, Sendable {
    case voiceNotAvailable(voiceId: String)
    case subscriptionRequired(voice: String, requiredTier: SubscriptionTier)
    case networkUnavailable
    case cloudServiceError(message: String)
    case modelError(message: String)
    case invalidInput(reason: String)
    case cancelled
    case audioEncodingError(message: String)
    case cloningFailed(reason: String)
    case invalidCloneAudio(reason: String)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case unknown(underlyingError: Error?)
    
    var errorDescription: String? {
        switch self {
        case .voiceNotAvailable(let voiceId):
            return "Voice '\(voiceId)' is not available."
        case .subscriptionRequired(let voice, let tier):
            return "'\(voice)' requires a \(tier.displayName) subscription."
        case .networkUnavailable:
            return "Network connection required for this voice."
        case .cloudServiceError(let message):
            return "Cloud service error: \(message)"
        case .modelError(let message):
            return "Voice model error: \(message)"
        case .invalidInput(let reason):
            return "Invalid text: \(reason)"
        case .cancelled:
            return "Speech synthesis was cancelled."
        case .audioEncodingError(let message):
            return "Audio encoding error: \(message)"
        case .cloningFailed(let reason):
            return "Voice cloning failed: \(reason)"
        case .invalidCloneAudio(let reason):
            return "Invalid audio for cloning: \(reason)"
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit exceeded. Try again in \(Int(seconds)) seconds."
            }
            return "Rate limit exceeded. Please try again later."
        case .unknown(let error):
            return error?.localizedDescription ?? "An unknown error occurred."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .voiceNotAvailable:
            return "Try selecting a different voice."
        case .subscriptionRequired:
            return "Upgrade to unlock this voice."
        case .networkUnavailable:
            return "Connect to the internet or choose an offline voice."
        case .cloudServiceError, .modelError:
            return "Try again or select a different voice."
        case .invalidInput:
            return "Check your text and try again."
        case .cancelled:
            return nil
        case .audioEncodingError:
            return "Try again with a different voice."
        case .cloningFailed, .invalidCloneAudio:
            return "Record a new audio sample in a quiet environment."
        case .rateLimitExceeded:
            return "Wait a moment before trying again."
        case .unknown:
            return "Try again or restart the app."
        }
    }
}
