//
//  TTSError.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation

// MARK: - TTS Error

/// Errors that can occur during TTS operations.
enum TTSError: Error, LocalizedError {
    case synthesisFailedError(message: String)
    case audioEncodingError(message: String)
    case voiceNotFound(voiceId: String)
    case textTooLong(maxLength: Int)
    case networkError(underlying: Error)
    case cacheError(message: String)
    case engineNotReady
    
    var errorDescription: String? {
        switch self {
        case .synthesisFailedError(let message):
            return "Speech synthesis failed: \(message)"
        case .audioEncodingError(let message):
            return "Audio encoding failed: \(message)"
        case .voiceNotFound(let voiceId):
            return "Voice not found: \(voiceId)"
        case .textTooLong(let maxLength):
            return "Text exceeds maximum length of \(maxLength) characters"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .engineNotReady:
            return "TTS engine is not ready"
        }
    }
}
