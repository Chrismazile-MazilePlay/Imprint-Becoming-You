//
//  SystemTTSService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation

// MARK: - SystemTTSService

/// Wrapper around AVSpeechSynthesizer for system text-to-speech.
///
/// Used as a fallback when:
/// - User hasn't cloned their voice
/// - Network is unavailable
/// - ElevenLabs API fails
///
/// ## Usage
/// ```swift
/// let tts = SystemTTSService()
/// try await tts.speak("I am confident and capable")
/// ```
final class SystemTTSService: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The underlying speech synthesizer
    private let synthesizer: AVSpeechSynthesizer
    
    /// Current speech utterance
    private var currentUtterance: AVSpeechUtterance?
    
    /// Whether speech is currently in progress
    private(set) var isSpeaking: Bool = false
    
    /// Continuation for async speech completion
    private var speechContinuation: CheckedContinuation<Void, Error>?
    
    /// Delegate for speech events
    weak var delegate: SystemTTSDelegate?
    
    /// Speech rate (0.0 - 1.0, default 0.5)
    var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    
    /// Pitch multiplier (0.5 - 2.0, default 1.0)
    var pitchMultiplier: Float = 1.0
    
    /// Volume (0.0 - 1.0, default 1.0)
    var volume: Float = 1.0
    
    /// Pre/post utterance delay
    var preUtteranceDelay: TimeInterval = 0.0
    var postUtteranceDelay: TimeInterval = 0.0
    
    /// Selected voice (nil uses default)
    private var selectedVoice: AVSpeechSynthesisVoice?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        
        // Select a good default voice
        selectDefaultVoice()
    }
    
    // MARK: - Voice Selection
    
    /// Selects the best available voice
    private func selectDefaultVoice() {
        // Prefer enhanced/premium voices
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Try to find a high-quality English voice
        let preferredVoices = voices.filter { voice in
            voice.language.starts(with: "en") &&
            voice.quality == .enhanced
        }
        
        if let premiumVoice = preferredVoices.first {
            selectedVoice = premiumVoice
        } else {
            // Fallback to default English voice
            selectedVoice = AVSpeechSynthesisVoice(language: "en-US")
        }
    }
    
    /// Sets a specific voice by identifier
    /// - Parameter identifier: Voice identifier
    func setVoice(identifier: String) {
        selectedVoice = AVSpeechSynthesisVoice(identifier: identifier)
    }
    
    /// Sets voice by language
    /// - Parameter language: Language code (e.g., "en-US")
    func setVoice(language: String) {
        selectedVoice = AVSpeechSynthesisVoice(language: language)
    }
    
    /// Returns available voices for a language
    /// - Parameter language: Language code prefix (e.g., "en")
    /// - Returns: Array of available voices
    func availableVoices(forLanguage language: String = "en") -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: language) }
            .map { VoiceInfo(voice: $0) }
    }
    
    // MARK: - Speech Control
    
    /// Speaks the given text
    /// - Parameter text: Text to speak
    /// - Throws: `AppError.audioPlaybackFailed` if speech fails
    func speak(_ text: String) async throws {
        // Stop any current speech
        stopSpeaking()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        utterance.preUtteranceDelay = preUtteranceDelay
        utterance.postUtteranceDelay = postUtteranceDelay
        
        lock.lock()
        currentUtterance = utterance
        isSpeaking = true
        lock.unlock()
        
        // Start speaking and wait for completion
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            speechContinuation = continuation
            lock.unlock()
            
            synthesizer.speak(utterance)
        }
    }
    
    /// Stops any current speech
    func stopSpeaking() {
        lock.lock()
        defer { lock.unlock() }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        isSpeaking = false
        currentUtterance = nil
        
        // Cancel continuation if waiting
        speechContinuation?.resume(returning: ())
        speechContinuation = nil
    }
    
    /// Pauses speech
    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
    }
    
    /// Continues paused speech
    func continueSpeaking() {
        synthesizer.continueSpeaking()
    }
    
    // MARK: - Synthesis to Audio
    
    /// Synthesizes text to audio data (for caching)
    /// - Parameter text: Text to synthesize
    /// - Returns: Audio data
    /// - Throws: `AppError.audioPlaybackFailed` if synthesis fails
    func synthesizeToData(_ text: String) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        
        return try await withCheckedThrowingContinuation { continuation in
            var audioBuffers: [AVAudioBuffer] = []
            
            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    if audioBuffers.isEmpty {
                        continuation.resume(throwing: AppError.audioPlaybackFailed(
                            reason: "No audio data generated"
                        ))
                    } else {
                        // Synthesis complete - combine buffers
                        do {
                            let data = try self.combineBuffers(audioBuffers)
                            continuation.resume(returning: data)
                        } catch {
                            continuation.resume(throwing: AppError.audioPlaybackFailed(
                                reason: "Failed to combine audio: \(error.localizedDescription)"
                            ))
                        }
                    }
                    return
                }
                
                audioBuffers.append(pcmBuffer)
            }
        }
    }
    
    /// Combines audio buffers into a single Data object
    private func combineBuffers(_ buffers: [AVAudioBuffer]) throws -> Data {
        guard let firstBuffer = buffers.first as? AVAudioPCMBuffer else {
            throw AppError.audioPlaybackFailed(reason: "No audio buffers to combine")
        }
        
        let format = firstBuffer.format
        var totalFrames: AVAudioFrameCount = 0
        
        for buffer in buffers {
            guard let pcm = buffer as? AVAudioPCMBuffer else { continue }
            totalFrames += pcm.frameLength
        }
        
        guard let combinedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: totalFrames
        ) else {
            throw AppError.audioPlaybackFailed(reason: "Failed to create combined buffer")
        }
        
        var offset: AVAudioFrameCount = 0
        
        for buffer in buffers {
            guard let pcm = buffer as? AVAudioPCMBuffer else { continue }
            
            let frameLength = pcm.frameLength
            
            if let srcData = pcm.floatChannelData,
               let dstData = combinedBuffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    memcpy(
                        dstData[channel] + Int(offset),
                        srcData[channel],
                        Int(frameLength) * MemoryLayout<Float>.size
                    )
                }
            }
            
            offset += frameLength
        }
        
        combinedBuffer.frameLength = totalFrames
        
        // Convert to WAV data
        return try bufferToWAVData(combinedBuffer)
    }
    
    /// Converts an audio buffer to WAV data
    private func bufferToWAVData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let format = buffer.format
        let sampleRate = UInt32(format.sampleRate)
        let channels = UInt16(format.channelCount)
        let bitsPerSample: UInt16 = 32 // Float32
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(buffer.frameLength) * UInt32(channels) * UInt32(bitsPerSample / 8)
        
        var data = Data()
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // Audio format (IEEE float)
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Audio samples
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(channels) {
                    let sample = channelData[channel][frame]
                    data.append(contentsOf: withUnsafeBytes(of: sample) { Array($0) })
                }
            }
        }
        
        return data
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemTTSService: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        delegate?.ttsDidStart()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        lock.lock()
        isSpeaking = false
        currentUtterance = nil
        let continuation = speechContinuation
        speechContinuation = nil
        lock.unlock()
        
        continuation?.resume(returning: ())
        delegate?.ttsDidFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        lock.lock()
        isSpeaking = false
        currentUtterance = nil
        let continuation = speechContinuation
        speechContinuation = nil
        lock.unlock()
        
        continuation?.resume(returning: ())
        delegate?.ttsDidCancel()
    }
    
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let text = utterance.speechString as NSString
        let word = text.substring(with: characterRange)
        delegate?.ttsWillSpeak(word: word, range: characterRange)
    }
}

// MARK: - VoiceInfo

/// Information about an available voice
struct VoiceInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: String
    
    init(voice: AVSpeechSynthesisVoice) {
        self.id = voice.identifier
        self.name = voice.name
        self.language = voice.language
        self.quality = voice.quality == .enhanced ? "Enhanced" : "Default"
    }
}

// MARK: - SystemTTSDelegate

/// Delegate for TTS events
protocol SystemTTSDelegate: AnyObject, Sendable {
    /// Called when speech starts
    func ttsDidStart()
    
    /// Called when speech finishes
    func ttsDidFinish()
    
    /// Called when speech is cancelled
    func ttsDidCancel()
    
    /// Called for each word being spoken
    func ttsWillSpeak(word: String, range: NSRange)
}

// MARK: - Default Implementation

extension SystemTTSDelegate {
    func ttsDidStart() {}
    func ttsDidFinish() {}
    func ttsDidCancel() {}
    func ttsWillSpeak(word: String, range: NSRange) {}
}
