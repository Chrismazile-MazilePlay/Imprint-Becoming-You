//
//  TTSResult.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//
/*
import Foundation

// MARK: - TTS Audio Format

/// Supported audio formats for TTS output.
enum TTSAudioFormat: String, Codable, Sendable {
    case wav
    case mp3
    case m4a
    case pcm
    
    var fileExtension: String {
        rawValue
    }
    
    var mimeType: String {
        switch self {
        case .wav: return "audio/wav"
        case .mp3: return "audio/mpeg"
        case .m4a: return "audio/mp4"
        case .pcm: return "audio/pcm"
        }
    }
}

// MARK: - Word Timing

/// Timing information for a single word in synthesized speech.
struct WordTiming: Codable, Sendable {
    /// The word text
    let word: String
    
    /// Start time in seconds from audio beginning
    let startTime: TimeInterval
    
    /// End time in seconds from audio beginning
    let endTime: TimeInterval
    
    /// Duration of the word
    var duration: TimeInterval {
        endTime - startTime
    }
}

// MARK: - TTS Result

/// Result of a TTS synthesis operation.
struct TTSResult: Sendable {
    /// The synthesized audio data
    let audioData: Data
    
    /// Audio format of the data
    let audioFormat: TTSAudioFormat
    
    /// Original text that was synthesized
    let originalText: String
    
    /// Voice used for synthesis
    let voice: Voice
    
    /// Speech speed multiplier used
    let speed: Float
    
    /// Duration of the audio in seconds
    let duration: TimeInterval
    
    /// Sample rate in Hz
    let sampleRate: Int
    
    /// Word-level timing information (if available)
    let wordTimings: [WordTiming]?
    
    /// When the synthesis was completed
    let synthesizedAt: Date
    
    // MARK: - Initialization
    
    init(
        audioData: Data,
        audioFormat: TTSAudioFormat,
        originalText: String,
        voice: Voice,
        speed: Float = 1.0,
        duration: TimeInterval,
        sampleRate: Int,
        wordTimings: [WordTiming]? = nil,
        synthesizedAt: Date = Date()
    ) {
        self.audioData = audioData
        self.audioFormat = audioFormat
        self.originalText = originalText
        self.voice = voice
        self.speed = speed
        self.duration = duration
        self.sampleRate = sampleRate
        self.wordTimings = wordTimings
        self.synthesizedAt = synthesizedAt
    }
    
    /// Size of the audio data in bytes
    var sizeBytes: Int64 {
        Int64(audioData.count)
    }
}
*/
