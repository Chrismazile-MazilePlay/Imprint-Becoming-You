//
//  MockAudioSessionController.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/14/26.
//

import AVFoundation

// MARK: - MockAudioSessionController

/// Mock implementation of `AudioSessionControllerProtocol` for previews and testing.
///
/// Simulates audio session state without actual `AVAudioSession` calls.
/// Provides configurable stubs for permissions and session behavior.
@MainActor
final class MockAudioSessionController: AudioSessionControllerProtocol {

    // MARK: - State

    private(set) var isInterrupted: Bool = false
    private(set) var isSessionActive: Bool = false

    // MARK: - Permission Stubs

    var stubHasMicrophonePermission: Bool = true
    var stubHasSpeechRecognitionPermission: Bool = true
    var stubRequestMicPermissionResult: Bool = true
    var stubRequestSpeechPermissionResult: Bool = true

    var hasMicrophonePermission: Bool { stubHasMicrophonePermission }
    var hasSpeechRecognitionPermission: Bool { stubHasSpeechRecognitionPermission }

    func requestMicrophonePermission() async -> Bool {
        stubRequestMicPermissionResult
    }

    func requestSpeechRecognitionPermission() async -> Bool {
        stubRequestSpeechPermissionResult
    }

    // MARK: - Route Info

    var headphonesConnected: Bool = false

    // MARK: - Callbacks

    var onEngineRestarted: (() -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?

    // MARK: - Call Tracking

    private(set) var configureCallCount: Int = 0

    // MARK: - Stubs

    var stubConfigureError: Error?

    // MARK: - Configuration

    func configure() async throws {
        configureCallCount += 1
        if let error = stubConfigureError { throw error }
        isSessionActive = true
    }

    func deactivateSession(notifyOthers: Bool) {
        isSessionActive = false
    }

    // MARK: - Engine

    func registerEngine(_ engine: AVAudioEngine) {
        // No-op for mock
    }
}
