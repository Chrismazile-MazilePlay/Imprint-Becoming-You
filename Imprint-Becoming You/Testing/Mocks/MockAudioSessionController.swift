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

    // MARK: - Reactive State

    private(set) var isInterrupted: Bool = false
    private(set) var isSessionActive: Bool = false
    private(set) var currentCategory: AVAudioSession.Category?
    private(set) var currentMode: AVAudioSession.Mode?

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

    var onEngineRestartedAfterFullStop: (() -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?

    // MARK: - Call Tracking

    private(set) var transitionCallCount: Int = 0
    private(set) var lastTransitionCategory: AVAudioSession.Category?
    private(set) var lastTransitionMode: AVAudioSession.Mode?

    // MARK: - Stubs

    var stubTransitionError: Error?

    // MARK: - Session Transitions

    func transition(
        to category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions,
        engineAction: AudioSessionController.EngineAction
    ) async throws {
        transitionCallCount += 1
        lastTransitionCategory = category
        lastTransitionMode = mode

        if let error = stubTransitionError { throw error }

        currentCategory = category
        currentMode = mode
        isSessionActive = true
    }

    func deactivateSession(notifyOthers: Bool) {
        isSessionActive = false
    }

    func resetTracking() {
        currentCategory = nil
        currentMode = nil
    }

    // MARK: - Engine

    func registerEngine(_ engine: AVAudioEngine) {
        // No-op for mock
    }
}
