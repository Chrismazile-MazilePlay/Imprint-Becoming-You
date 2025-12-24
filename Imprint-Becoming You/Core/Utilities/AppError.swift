//
//  AppError.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation

// MARK: - AppError

/// Centralized error type for the Imprint application.
///
/// All errors in the app should be mapped to an `AppError` case to ensure
/// consistent error handling and user-facing messaging.
///
/// ## Usage
/// ```swift
/// do {
///     try await audioService.startRecording()
/// } catch {
///     let appError = AppError.from(error)
///     await errorHandler.handle(appError)
/// }
/// ```
enum AppError: Error, Equatable, Sendable {
    
    // MARK: - Audio Errors
    
    /// Failed to initialize the audio engine
    case audioEngineInitializationFailed(reason: String)
    
    /// Audio session configuration failed
    case audioSessionConfigurationFailed(reason: String)
    
    /// Microphone access was denied or restricted
    case microphoneAccessDenied
    
    /// Audio file playback failed
    case audioPlaybackFailed(reason: String)
    
    /// Audio recording failed
    case audioRecordingFailed(reason: String)
    
    /// Binaural beat generation failed
    case binauralGenerationFailed(reason: String)
    
    // MARK: - Speech Errors
    
    /// Speech recognition authorization denied
    case speechRecognitionDenied
    
    /// Speech recognition not available on this device
    case speechRecognitionUnavailable
    
    /// Speech recognition failed during processing
    case speechRecognitionFailed(reason: String)
    
    /// Voice calibration failed
    case calibrationFailed(reason: String)
    
    // MARK: - Network Errors
    
    /// No network connection available
    case networkUnavailable
    
    /// Request timed out
    case requestTimeout
    
    /// Server returned an error
    case serverError(statusCode: Int, message: String)
    
    /// Failed to parse server response
    case invalidServerResponse(reason: String)
    
    /// Rate limit exceeded
    case rateLimitExceeded(retryAfter: TimeInterval?)
    
    /// Cloud sync failed
    case syncFailed(reason: String)
    
    // MARK: - API Errors
    
    /// OpenAI API error
    case openAIError(reason: String)
    
    /// ElevenLabs API error
    case elevenLabsError(reason: String)
    
    /// TTS generation failed
    case ttsGenerationFailed(reason: String)
    
    /// Firebase error
    case firebaseError(reason: String)
    
    /// Voice cloning failed
    case voiceCloningFailed(reason: String)
    
    /// Affirmation generation failed
    case affirmationGenerationFailed(reason: String)
    
    // MARK: - Data Errors
    
    /// Failed to save data
    case saveFailed(reason: String)
    
    /// Failed to load data
    case loadFailed(reason: String)
    
    /// Data corruption detected
    case dataCorrupted(reason: String)
    
    /// Cache operation failed
    case cacheError(reason: String)
    
    /// SwiftData model context error
    case modelContextError(reason: String)
    
    // MARK: - Authentication Errors
    
    /// User is not authenticated
    case notAuthenticated
    
    /// Authentication failed
    case authenticationFailed(reason: String)
    
    /// Sign out failed
    case signOutFailed(reason: String)
    
    /// Account deletion failed
    case accountDeletionFailed(reason: String)
    
    // MARK: - Subscription Errors
    
    /// Purchase failed
    case purchaseFailed(reason: String)
    
    /// Purchase was cancelled by user
    case purchaseCancelled
    
    /// Failed to restore purchases
    case restoreFailed(reason: String)
    
    /// Feature requires premium subscription
    case premiumRequired(feature: String)
    
    // MARK: - Permission Errors
    
    /// Required permission was denied
    case permissionDenied(permission: PermissionType)
    
    /// Permission status is restricted (parental controls, MDM)
    case permissionRestricted(permission: PermissionType)
    
    // MARK: - Validation Errors
    
    /// Input validation failed
    case validationFailed(field: String, reason: String)
    
    /// Goal selection limit exceeded
    case goalLimitExceeded(maximum: Int)
    
    /// Prompt limit exceeded (free tier)
    case promptLimitExceeded(maximum: Int)
    
    /// Goals are locked for modification
    case goalsLocked(unlockDate: Date)
    
    // MARK: - General Errors
    
    /// An unexpected error occurred
    case unexpected(reason: String)
    
    /// Operation was cancelled
    case cancelled
    
    /// Feature not yet implemented
    case notImplemented(feature: String)
}

// MARK: - PermissionType

/// Types of permissions the app may request
enum PermissionType: String, Sendable {
    case microphone = "Microphone"
    case speechRecognition = "Speech Recognition"
    case notifications = "Notifications"
}

// MARK: - LocalizedError Conformance

extension AppError: LocalizedError {
    
    var errorDescription: String? {
        switch self {
        // Audio Errors
        case .audioEngineInitializationFailed(let reason):
            return "Unable to initialize audio: \(reason)"
        case .audioSessionConfigurationFailed(let reason):
            return "Audio configuration failed: \(reason)"
        case .microphoneAccessDenied:
            return "Microphone access is required to practice affirmations aloud."
        case .audioPlaybackFailed(let reason):
            return "Unable to play audio: \(reason)"
        case .audioRecordingFailed(let reason):
            return "Unable to record audio: \(reason)"
        case .binauralGenerationFailed(let reason):
            return "Unable to generate binaural beats: \(reason)"
            
        // Speech Errors
        case .speechRecognitionDenied:
            return "Speech recognition access is required for resonance scoring."
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device."
        case .speechRecognitionFailed(let reason):
            return "Speech recognition failed: \(reason)"
        case .calibrationFailed(let reason):
            return "Voice calibration failed: \(reason)"
            
        // Network Errors
        case .networkUnavailable:
            return "No internet connection. Some features require network access."
        case .requestTimeout:
            return "The request timed out. Please try again."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .invalidServerResponse(let reason):
            return "Invalid server response: \(reason)"
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please wait \(Int(seconds)) seconds."
            }
            return "Too many requests. Please try again later."
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
            
        // API Errors
        case .openAIError(let reason):
            return "AI service error: \(reason)"
        case .elevenLabsError(let reason):
            return "Voice service error: \(reason)"
        case .ttsGenerationFailed(let reason):
            return "Text-to-speech failed: \(reason)"
        case .firebaseError(let reason):
            return "Cloud service error: \(reason)"
        case .voiceCloningFailed(let reason):
            return "Voice cloning failed: \(reason)"
        case .affirmationGenerationFailed(let reason):
            return "Unable to generate affirmations: \(reason)"
            
        // Data Errors
        case .saveFailed(let reason):
            return "Unable to save: \(reason)"
        case .loadFailed(let reason):
            return "Unable to load data: \(reason)"
        case .dataCorrupted(let reason):
            return "Data appears corrupted: \(reason)"
        case .cacheError(let reason):
            return "Cache error: \(reason)"
        case .modelContextError(let reason):
            return "Data error: \(reason)"
            
        // Authentication Errors
        case .notAuthenticated:
            return "Please sign in to continue."
        case .authenticationFailed(let reason):
            return "Sign in failed: \(reason)"
        case .signOutFailed(let reason):
            return "Sign out failed: \(reason)"
        case .accountDeletionFailed(let reason):
            return "Account deletion failed: \(reason)"
            
        // Subscription Errors
        case .purchaseFailed(let reason):
            return "Purchase failed: \(reason)"
        case .purchaseCancelled:
            return "Purchase was cancelled."
        case .restoreFailed(let reason):
            return "Unable to restore purchases: \(reason)"
        case .premiumRequired(let feature):
            return "\(feature) requires a premium subscription."
            
        // Permission Errors
        case .permissionDenied(let permission):
            return "\(permission.rawValue) access was denied. Please enable in Settings."
        case .permissionRestricted(let permission):
            return "\(permission.rawValue) access is restricted on this device."
            
        // Validation Errors
        case .validationFailed(let field, let reason):
            return "\(field): \(reason)"
        case .goalLimitExceeded(let maximum):
            return "You can select up to \(maximum) goals."
        case .promptLimitExceeded(let maximum):
            return "Free accounts are limited to \(maximum) saved prompts. Upgrade to Premium for unlimited prompts."
        case .goalsLocked(let unlockDate):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Goals can be changed after \(formatter.string(from: unlockDate))."
            
        // General Errors
        case .unexpected(let reason):
            return "An unexpected error occurred: \(reason)"
        case .cancelled:
            return "Operation was cancelled."
        case .notImplemented(let feature):
            return "\(feature) is coming soon."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .microphoneAccessDenied, .speechRecognitionDenied:
            return "Open Settings and enable access for Imprint."
        case .networkUnavailable, .syncFailed:
            return "Check your internet connection and try again."
        case .requestTimeout:
            return "Check your connection and try again."
        case .rateLimitExceeded:
            return "Please wait a moment before trying again."
        case .premiumRequired:
            return "Tap to learn about Premium."
        case .goalsLocked:
            return "Upgrade to Premium for unlimited goal changes."
        default:
            return nil
        }
    }
}

// MARK: - Error Conversion

extension AppError {
    
    /// Converts any error to an AppError
    /// - Parameter error: The source error
    /// - Returns: An appropriate AppError representation
    static func from(_ error: Error) -> AppError {
        // If already an AppError, return as-is
        if let appError = error as? AppError {
            return appError
        }
        
        // Handle URLError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .timedOut:
                return .requestTimeout
            case .cancelled:
                return .cancelled
            default:
                return .serverError(statusCode: urlError.errorCode, message: urlError.localizedDescription)
            }
        }
        
        // Handle NSError
        let nsError = error as NSError
        
        // Handle common error domains
        switch nsError.domain {
        case "com.apple.coreaudio.avfaudio":
            return .audioEngineInitializationFailed(reason: nsError.localizedDescription)
        case "kAFAssistantErrorDomain":
            return .speechRecognitionFailed(reason: nsError.localizedDescription)
        default:
            return .unexpected(reason: error.localizedDescription)
        }
    }
}

// MARK: - Error Severity

extension AppError {
    
    /// Indicates whether the error is recoverable by the user
    var isRecoverable: Bool {
        switch self {
        case .cancelled, .purchaseCancelled:
            return true
        case .networkUnavailable, .requestTimeout, .rateLimitExceeded, .syncFailed:
            return true
        case .permissionDenied, .permissionRestricted:
            return true
        case .premiumRequired, .goalLimitExceeded, .promptLimitExceeded, .goalsLocked:
            return true
        case .validationFailed:
            return true
        default:
            return false
        }
    }
    
    /// Indicates whether the error should be logged for debugging
    var shouldLog: Bool {
        switch self {
        case .cancelled, .purchaseCancelled:
            return false
        default:
            return true
        }
    }
}
