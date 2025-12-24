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
final class SystemTTSService: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The underlying speech synthesizer
    private let synthesizer: AVSpeechSynthesizer
    
    /// Serial queue for thread-safe state access
    private let stateQueue = DispatchQueue(label: "com.imprint.tts.state")
    
    /// Current speech utterance
    private var currentUtterance: AVSpeechUtterance?
    
    /// Whether speech is currently in progress
    private var _isSpeaking: Bool = false
    var isSpeaking: Bool {
        stateQueue.sync { _isSpeaking }
    }
    
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
    
    // MARK: - Initialization
    
    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
        selectDefaultVoice()
    }
    
    // MARK: - Voice Selection
    
    /// Selects the best available voice
    private func selectDefaultVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Try to find a high-quality English voice
        let preferredVoices = voices.filter { voice in
            voice.language.starts(with: "en") && voice.quality == .enhanced
        }
        
        selectedVoice = preferredVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
    
    /// Sets a specific voice by identifier
    func setVoice(identifier: String) {
        selectedVoice = AVSpeechSynthesisVoice(identifier: identifier)
    }
    
    /// Sets voice by language
    func setVoice(language: String) {
        selectedVoice = AVSpeechSynthesisVoice(language: language)
    }
    
    /// Returns available voices for a language
    func availableVoices(forLanguage language: String = "en") -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: language) }
            .map { VoiceInfo(voice: $0) }
    }
    
    // MARK: - Speech Control
    
    /// Speaks the given text
    func speak(_ text: String) async throws {
        // Stop any current speech
        stopSpeaking()
        
        // Capture Sendable configuration values BEFORE the closure
        let voice = selectedVoice
        let rate = speechRate
        let pitch = pitchMultiplier
        let vol = volume
        let preDelay = preUtteranceDelay
        let postDelay = postUtteranceDelay
        
        // Start speaking and wait for completion
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateQueue.sync {
                speechContinuation = continuation
            }
            
            // Create utterance ON main thread to avoid Sendable capture warning
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: AppError.audioPlaybackFailed(reason: "Service deallocated"))
                    return
                }
                
                // Create utterance here - AVSpeechUtterance is not Sendable
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = rate
                utterance.pitchMultiplier = pitch
                utterance.volume = vol
                utterance.preUtteranceDelay = preDelay
                utterance.postUtteranceDelay = postDelay
                
                self.stateQueue.sync {
                    self.currentUtterance = utterance
                    self._isSpeaking = true
                }
                
                self.synthesizer.speak(utterance)
            }
        }
    }
    
    /// Stops any current speech
    func stopSpeaking() {
        stateQueue.sync {
            _isSpeaking = false
            currentUtterance = nil
            
            // Cancel continuation if waiting
            speechContinuation?.resume(returning: ())
            speechContinuation = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }
    
    /// Pauses speech
    func pauseSpeaking() {
        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.pauseSpeaking(at: .word)
        }
    }
    
    /// Continues paused speech
    func continueSpeaking() {
        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.continueSpeaking()
        }
    }
    
    // MARK: - Synthesis to Audio
    
    /// Synthesizes text to audio data (for caching)
    func synthesizeToData(_ text: String) async throws -> Data {
        // Capture Sendable configuration values BEFORE the closure
        let voice = selectedVoice
        let rate = speechRate
        let pitch = pitchMultiplier
        let vol = volume
        
        return try await withCheckedThrowingContinuation { continuation in
            // Create utterance ON main thread to avoid Sendable capture warning
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: AppError.audioPlaybackFailed(reason: "Service deallocated"))
                    return
                }
                
                // Create utterance here - AVSpeechUtterance is not Sendable
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                utterance.rate = rate
                utterance.pitchMultiplier = pitch
                utterance.volume = vol
                
                var audioBuffers: [AVAudioPCMBuffer] = []
                
                self.synthesizer.write(utterance) { buffer in
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                        if audioBuffers.isEmpty {
                            continuation.resume(throwing: AppError.audioPlaybackFailed(reason: "No audio data generated"))
                        } else {
                            do {
                                let data = try self.combineBuffers(audioBuffers)
                                continuation.resume(returning: data)
                            } catch {
                                continuation.resume(throwing: AppError.audioPlaybackFailed(reason: "Failed to combine audio: \(error.localizedDescription)"))
                            }
                        }
                        return
                    }
                    audioBuffers.append(pcmBuffer)
                }
            }
        }
    }
    
    /// Combines audio buffers into a single Data object
    private func combineBuffers(_ buffers: [AVAudioPCMBuffer]) throws -> Data {
        guard let firstBuffer = buffers.first else {
            throw AppError.audioPlaybackFailed(reason: "No audio buffers to combine")
        }
        
        let format = firstBuffer.format
        var totalFrames: AVAudioFrameCount = 0
        
        for buffer in buffers {
            totalFrames += buffer.frameLength
        }
        
        guard let combinedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw AppError.audioPlaybackFailed(reason: "Failed to create combined buffer")
        }
        
        var offset: AVAudioFrameCount = 0
        
        for buffer in buffers {
            let frameLength = buffer.frameLength
            
            if let srcData = buffer.floatChannelData,
               let dstData = combinedBuffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    memcpy(dstData[channel] + Int(offset), srcData[channel], Int(frameLength) * MemoryLayout<Float>.size)
                }
            }
            offset += frameLength
        }
        
        combinedBuffer.frameLength = totalFrames
        return try bufferToWAVData(combinedBuffer)
    }
    
    /// Converts an audio buffer to WAV data
    private func bufferToWAVData(_ buffer: AVAudioPCMBuffer) throws -> Data {
        let format = buffer.format
        let sampleRate = UInt32(format.sampleRate)
        let channels = UInt16(format.channelCount)
        let bitsPerSample: UInt16 = 32
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
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) })
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
        var continuation: CheckedContinuation<Void, Error>?
        
        stateQueue.sync {
            _isSpeaking = false
            currentUtterance = nil
            continuation = speechContinuation
            speechContinuation = nil
        }
        
        continuation?.resume(returning: ())
        delegate?.ttsDidFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        var continuation: CheckedContinuation<Void, Error>?
        
        stateQueue.sync {
            _isSpeaking = false
            currentUtterance = nil
            continuation = speechContinuation
            speechContinuation = nil
        }
        
        continuation?.resume(returning: ())
        delegate?.ttsDidCancel()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let text = utterance.speechString as NSString
        let word = text.substring(with: characterRange)
        delegate?.ttsWillSpeak(word: word, range: characterRange)
    }
}

// MARK: - VoiceInfo

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

protocol SystemTTSDelegate: AnyObject {
    func ttsDidStart()
    func ttsDidFinish()
    func ttsDidCancel()
    func ttsWillSpeak(word: String, range: NSRange)
}

extension SystemTTSDelegate {
    func ttsDidStart() {}
    func ttsDidFinish() {}
    func ttsDidCancel() {}
    func ttsWillSpeak(word: String, range: NSRange) {}
}
