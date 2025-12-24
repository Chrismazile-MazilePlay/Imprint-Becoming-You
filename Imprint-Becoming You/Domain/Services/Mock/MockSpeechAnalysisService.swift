//
//  MockSpeechAnalysisService.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/24/25.
//

import Foundation

// MARK: - Mock Speech Analysis Service

/// Mock implementation of speech analysis service for previews and testing.
///
/// Simulates speech recognition and scoring without actual microphone input.
final class MockSpeechAnalysisService: SpeechAnalysisServiceProtocol, @unchecked Sendable {
    
    // MARK: - State
    
    var isAnalyzing: Bool = false
    
    var hasMicrophonePermission: Bool {
        get async { simulatePermissionsGranted }
    }
    
    var hasSpeechRecognitionPermission: Bool {
        get async { simulatePermissionsGranted }
    }
    
    // MARK: - Configuration
    
    /// Whether to simulate permissions as granted
    var simulatePermissionsGranted: Bool = true
    
    /// Number of score updates to emit during analysis
    var scoreUpdateCount: Int = 5
    
    /// Delay between score updates
    var scoreUpdateDelay: Duration = .milliseconds(500)
    
    /// Simulated calibration delay
    var calibrationDelay: Duration = .seconds(2)
    
    // MARK: - Stream Continuations
    
    private var scoreContinuation: AsyncStream<Float>.Continuation?
    private var textContinuation: AsyncStream<String>.Continuation?
    private var silenceContinuation: AsyncStream<Bool>.Continuation?
    
    // MARK: - Streams
    
    lazy var realtimeScoreStream: AsyncStream<Float> = {
        AsyncStream { [weak self] continuation in
            self?.scoreContinuation = continuation
        }
    }()
    
    lazy var recognizedTextStream: AsyncStream<String> = {
        AsyncStream { [weak self] continuation in
            self?.textContinuation = continuation
        }
    }()
    
    lazy var silenceDetectedStream: AsyncStream<Bool> = {
        AsyncStream { [weak self] continuation in
            self?.silenceContinuation = continuation
        }
    }()
    
    // MARK: - SpeechAnalysisServiceProtocol - Permissions
    
    func requestMicrophonePermission() async -> Bool {
        simulatePermissionsGranted
    }
    
    func requestSpeechRecognitionPermission() async -> Bool {
        simulatePermissionsGranted
    }
    
    // MARK: - SpeechAnalysisServiceProtocol - Analysis
    
    func startAnalysis(
        forAffirmation affirmationText: String,
        calibrationData: CalibrationData?
    ) async throws {
        guard simulatePermissionsGranted else {
            throw AppError.microphoneAccessDenied
        }
        
        isAnalyzing = true
        
        // Simulate real-time score updates
        Task { [weak self] in
            guard let self = self else { return }
            
            for i in 1...self.scoreUpdateCount {
                guard self.isAnalyzing else { break }
                
                try? await Task.sleep(for: self.scoreUpdateDelay)
                
                // Generate progressively improving score
                let baseScore: Float = 0.5
                let progress = Float(i) / Float(self.scoreUpdateCount)
                let score = baseScore + (progress * 0.4) + Float.random(in: -0.1...0.1)
                
                self.scoreContinuation?.yield(max(0, min(1, score)))
                
                // Also emit some recognized text
                let words = affirmationText.split(separator: " ")
                let wordCount = min(i * 2, words.count)
                let partialText = words.prefix(wordCount).joined(separator: " ")
                self.textContinuation?.yield(partialText)
            }
        }
    }
    
    func stopAnalysis() async -> ResonanceRecord? {
        isAnalyzing = false
        
        // Return a realistic mock record
        return ResonanceRecord(
            finalScore: Float.random(in: 0.6...0.95),
            textAccuracy: Float.random(in: 0.7...1.0),
            vocalEnergy: Float.random(in: 0.5...0.95),
            pitchStability: Float.random(in: 0.6...0.9),
            sessionMode: .readThenSpeak,
            duration: 3.5
        )
    }
    
    func cancelAnalysis() async {
        isAnalyzing = false
    }
    
    // MARK: - SpeechAnalysisServiceProtocol - Calibration
    
    func performCalibration(with sampleAffirmations: [String]) async throws -> CalibrationData {
        guard simulatePermissionsGranted else {
            throw AppError.microphoneAccessDenied
        }
        
        try await Task.sleep(for: calibrationDelay)
        
        return CalibrationData(
            baselineRMS: 0.3,
            pitchMin: 85,
            pitchMax: 255,
            volumeMin: -30,
            volumeMax: -10
        )
    }
}
