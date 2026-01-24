//
//  MockVoiceCloneService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Voice Clone Service

/// Mock implementation of VoiceCloneServiceProtocol for testing and previews.
final class MockVoiceCloneService: VoiceCloneServiceProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var clones: [String: Voice] = [:]
    private var cloneStatus: [String: VoiceCloneStatus] = [:]
    
    // Test hooks
    var shouldFailOnCreate: Bool = false
    var shouldFailOnPreview: Bool = false
    var createDelay: TimeInterval = 0.5
    var previewDelay: TimeInterval = 0.2
    
    // MARK: - Clone Creation
    
    func createClone(
        from audioData: Data,
        name: String,
        languageCode: String
    ) async throws -> Voice {
        if shouldFailOnCreate {
            throw TTSError.cloningFailed(reason: "Mock clone creation failure")
        }
        
        if createDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(createDelay * 1_000_000_000))
        }
        
        let cloneId = UUID().uuidString
        let voice = Voice.clonedVoice(
            cloneId: cloneId,
            name: name,
            sourceURL: URL(fileURLWithPath: "/mock/audio.m4a"),
            qwenSpeakerId: "mock_speaker_\(cloneId)",
            languageCode: languageCode
        )
        
        clones[voice.id] = voice
        cloneStatus[voice.id] = .ready
        
        return voice
    }
    
    func previewClone(audioData: Data, sampleText: String) async throws -> TTSResult {
        if shouldFailOnPreview {
            throw TTSError.cloningFailed(reason: "Mock preview failure")
        }
        
        if previewDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(previewDelay * 1_000_000_000))
        }
        
        // Create a temporary preview voice
        let previewVoice = Voice.clonedVoice(
            cloneId: "preview",
            name: "Preview Voice",
            sourceURL: URL(fileURLWithPath: "/mock/preview.m4a"),
            qwenSpeakerId: "mock_preview_speaker"
        )
        
        // Generate mock audio
        let duration = Double(sampleText.count) * 0.05
        let mockAudioData = Data(repeating: 0, count: Int(duration * 24000 * 2))
        
        return TTSResult(
            audioData: mockAudioData,
            audioFormat: .wav,
            duration: duration,
            originalText: sampleText,
            voice: previewVoice,
            wordTimings: [],
            source: .synthesized
        )
    }
    
    // MARK: - Clone Management
    
    func deleteClone(voiceId: String) async throws {
        clones.removeValue(forKey: voiceId)
        cloneStatus[voiceId] = .deleted
    }
    
    func getCloneStatus(voiceId: String) async throws -> VoiceCloneStatus {
        guard let status = cloneStatus[voiceId] else {
            throw TTSError.voiceNotAvailable(voiceId: voiceId)
        }
        return status
    }
    
    func listClones() async throws -> [Voice] {
        Array(clones.values)
    }
    
    // MARK: - Audio Validation
    
    func validateAudio(_ audioData: Data) async -> CloneAudioValidation {
        // Estimate duration from data size (rough: 16kHz mono 16-bit = 32KB/sec)
        let estimatedDuration = Double(audioData.count) / 32000.0
        
        var issues: [CloneAudioIssue] = []
        
        if estimatedDuration < VoiceCloneConfiguration.minimumDuration {
            issues.append(CloneAudioIssue(
                type: .tooShort,
                severity: .error,
                message: "Audio must be at least 3 seconds"
            ))
        }
        
        if estimatedDuration > VoiceCloneConfiguration.maximumDuration {
            issues.append(CloneAudioIssue(
                type: .tooLong,
                severity: .warning,
                message: "Audio will be trimmed to 60 seconds"
            ))
        }
        
        let isValid = !issues.contains { $0.severity == .error }
        
        return CloneAudioValidation(
            isValid: isValid,
            duration: estimatedDuration,
            qualityScore: isValid ? 0.8 : 0.0,
            issues: issues,
            suggestions: issues.map { $0.suggestion }
        )
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        clones.removeAll()
        cloneStatus.removeAll()
        shouldFailOnCreate = false
        shouldFailOnPreview = false
    }
    
    func seedClone(_ voice: Voice, status: VoiceCloneStatus = .ready) {
        clones[voice.id] = voice
        cloneStatus[voice.id] = status
    }
}
