//
//  TTSServiceProtocol.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech services (System TTS and ElevenLabs)
///
/// Provides a unified interface for speech synthesis, supporting both
/// on-device system TTS and cloud-based ElevenLabs voice cloning.
///
/// ## Usage
/// ```swift
/// let ttsService: TTSServiceProtocol = TTSService()
///
/// // Synthesize to data (for caching)
/// let audioData = try await ttsService.synthesize(text: "Hello", voiceId: nil)
///
/// // Speak immediately
/// try await ttsService.speakText("Hello world", voiceId: nil)
/// ```
protocol TTSServiceProtocol: AnyObject, Sendable {
    
    /// Synthesizes speech for the given text
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: ElevenLabs voice ID (nil for system TTS)
    /// - Returns: Audio data
    /// - Throws: `AppError.notImplemented` if ElevenLabs is requested but not available
    func synthesize(text: String, voiceId: String?) async throws -> Data
    
    /// Synthesizes and plays speech immediately
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: ElevenLabs voice ID (nil for system TTS)
    /// - Throws: `AppError.notImplemented` if ElevenLabs is requested but not available
    func speakText(_ text: String, voiceId: String?) async throws
    
    /// Stops current speech playback
    func stopSpeaking() async
    
    /// Whether speech is currently playing
    var isSpeaking: Bool { get }
}
