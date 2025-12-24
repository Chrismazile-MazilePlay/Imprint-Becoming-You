//
//  SpeechRecognitionService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Speech
import AVFoundation

// MARK: - SpeechRecognitionService

/// Wraps Apple's Speech framework for real-time speech recognition.
///
/// Handles:
/// - Speech recognition authorization
/// - Real-time transcription from audio buffers
/// - Final transcription results
///
/// ## Usage
/// ```swift
/// let service = SpeechRecognitionService()
/// try await service.startRecognition()
/// for await result in service.transcriptionStream {
///     print(result.text)
/// }
/// ```
actor SpeechRecognitionService {
    
    // MARK: - Properties
    
    /// Speech recognizer for the device locale
    private let speechRecognizer: SFSpeechRecognizer?
    
    /// Current recognition request
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    /// Current recognition task
    private var recognitionTask: SFSpeechRecognitionTask?
    
    /// Whether recognition is currently active
    private(set) var isRecognizing: Bool = false
    
    /// Most recent transcription result
    private(set) var currentTranscription: String = ""
    
    /// Continuation for transcription stream
    private var transcriptionContinuation: AsyncStream<TranscriptionResult>.Continuation?
    
    /// Stream of transcription results
    private(set) lazy var transcriptionStream: AsyncStream<TranscriptionResult> = {
        AsyncStream { [weak self] continuation in
            Task {
                await self?.setTranscriptionContinuation(continuation)
            }
        }
    }()
    
    // MARK: - Initialization
    
    /// Creates a new speech recognition service
    /// - Parameter locale: Locale for speech recognition (default: device locale)
    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    // MARK: - Authorization
    
    /// Current authorization status
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
    
    /// Whether speech recognition is authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
    
    /// Whether speech recognition is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
    
    /// Requests speech recognition authorization
    /// - Returns: Whether authorization was granted
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    // MARK: - Recognition Control
    
    /// Starts speech recognition
    /// - Throws: `AppError.speechRecognitionDenied` or `AppError.speechRecognitionUnavailable`
    func startRecognition() async throws {
        guard !isRecognizing else { return }
        
        // Check authorization
        guard isAuthorized else {
            throw AppError.speechRecognitionDenied
        }
        
        // Check availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AppError.speechRecognitionUnavailable
        }
        
        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false // Allow cloud for better accuracy
        
        // Add context hints if available (improves accuracy)
        if #available(iOS 17.0, *) {
            request.addsPunctuation = true
        }
        
        recognitionRequest = request
        currentTranscription = ""
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task {
                await self?.handleRecognitionResult(result, error: error)
            }
        }
        
        isRecognizing = true
    }
    
    /// Appends an audio buffer to the recognition request
    /// - Parameter buffer: Audio buffer to process
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    /// Appends audio samples to the recognition request
    /// - Parameters:
    ///   - samples: Audio samples
    ///   - sampleRate: Sample rate in Hz
    func appendAudioSamples(_ samples: [Float], sampleRate: Double) {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else { return }
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }
        
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        if let channelData = buffer.floatChannelData {
            for (index, sample) in samples.enumerated() {
                channelData[0][index] = sample
            }
        }
        
        recognitionRequest?.append(buffer)
    }
    
    /// Stops speech recognition and returns final result
    /// - Returns: Final transcription, or nil if no speech detected
    func stopRecognition() -> String? {
        guard isRecognizing else { return nil }
        
        // End the audio input
        recognitionRequest?.endAudio()
        
        // Clean up
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecognizing = false
        
        transcriptionContinuation?.finish()
        
        return currentTranscription.isEmpty ? nil : currentTranscription
    }
    
    /// Cancels recognition without returning a result
    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecognizing = false
        currentTranscription = ""
        
        transcriptionContinuation?.finish()
    }
    
    // MARK: - Private Methods
    
    /// Sets the transcription continuation
    private func setTranscriptionContinuation(_ continuation: AsyncStream<TranscriptionResult>.Continuation) {
        transcriptionContinuation = continuation
    }
    
    /// Handles recognition results from the Speech framework
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Handle specific errors
            let nsError = error as NSError
            
            // Ignore cancellation errors
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                return
            }
            
            let transcriptionError = TranscriptionResult(
                text: currentTranscription,
                isFinal: true,
                confidence: 0,
                error: error.localizedDescription
            )
            transcriptionContinuation?.yield(transcriptionError)
            return
        }
        
        guard let result = result else { return }
        
        // Get best transcription
        let transcription = result.bestTranscription.formattedString
        currentTranscription = transcription
        
        // Calculate confidence
        let confidence: Float
        if let firstSegment = result.bestTranscription.segments.first {
            confidence = firstSegment.confidence
        } else {
            confidence = 0.5
        }
        
        // Create result
        let transcriptionResult = TranscriptionResult(
            text: transcription,
            isFinal: result.isFinal,
            confidence: confidence,
            error: nil
        )
        
        transcriptionContinuation?.yield(transcriptionResult)
        
        // Finish stream if final
        if result.isFinal {
            transcriptionContinuation?.finish()
        }
    }
}

// MARK: - TranscriptionResult

/// Result from speech recognition
struct TranscriptionResult: Sendable {
    
    /// Recognized text
    let text: String
    
    /// Whether this is the final result
    let isFinal: Bool
    
    /// Confidence level (0.0 - 1.0)
    let confidence: Float
    
    /// Error message if recognition failed
    let error: String?
    
    /// Whether recognition was successful
    var isSuccess: Bool {
        error == nil && !text.isEmpty
    }
}

// MARK: - Speech Recognition Delegate

/// Protocol for receiving speech recognition events
protocol SpeechRecognitionDelegate: AnyObject, Sendable {
    /// Called when transcription is updated
    func speechRecognitionDidUpdate(transcription: String, isFinal: Bool)
    
    /// Called when an error occurs
    func speechRecognitionDidFail(with error: AppError)
}

// MARK: - Default Implementation

extension SpeechRecognitionDelegate {
    func speechRecognitionDidUpdate(transcription: String, isFinal: Bool) {}
    func speechRecognitionDidFail(with error: AppError) {}
}
