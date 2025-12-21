//
//  AudioSessionManager.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import AVFoundation
import Combine

// MARK: - AudioSessionManager

/// Manages the AVAudioSession lifecycle and handles audio interruptions.
///
/// This actor ensures thread-safe audio session configuration and provides
/// a centralized point for handling system audio events like phone calls,
/// alarms, and other interruptions.
///
/// ## Usage
/// ```swift
/// let manager = AudioSessionManager.shared
/// try await manager.configureForPlaybackAndRecording()
/// ```
actor AudioSessionManager {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide audio session management
    static let shared = AudioSessionManager()
    
    // MARK: - Properties
    
    /// The underlying AVAudioSession
    private let audioSession = AVAudioSession.sharedInstance()
    
    /// Current audio session category
    private(set) var currentCategory: AVAudioSession.Category?
    
    /// Whether the audio session is currently active
    private(set) var isActive: Bool = false
    
    /// Notification observer for interruptions
    private var interruptionObserver: NSObjectProtocol?
    
    /// Notification observer for route changes
    private var routeChangeObserver: NSObjectProtocol?
    
    /// Delegate for receiving audio session events
    weak var delegate: AudioSessionDelegate?
    
    /// Continuation for interruption stream
    private var interruptionContinuation: AsyncStream<AudioInterruptionEvent>.Continuation?
    
    /// Stream of audio interruption events
    lazy var interruptionStream: AsyncStream<AudioInterruptionEvent> = {
        AsyncStream { continuation in
            self.interruptionContinuation = continuation
        }
    }()
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationObservers()
    }
    
    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Configuration
    
    /// Configures the audio session for playback only (binaural beats, TTS)
    /// - Throws: `AppError.audioSessionConfigurationFailed` if configuration fails
    func configureForPlayback() async throws {
        do {
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            currentCategory = .playback
        } catch {
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to set playback category: \(error.localizedDescription)"
            )
        }
    }
    
    /// Configures the audio session for both playback and recording
    /// - Throws: `AppError.audioSessionConfigurationFailed` if configuration fails
    func configureForPlaybackAndRecording() async throws {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            currentCategory = .playAndRecord
        } catch {
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to set playAndRecord category: \(error.localizedDescription)"
            )
        }
    }
    
    /// Configures the audio session for recording only (voice cloning)
    /// - Throws: `AppError.audioSessionConfigurationFailed` if configuration fails
    func configureForRecording() async throws {
        do {
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: []
            )
            currentCategory = .record
        } catch {
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to set record category: \(error.localizedDescription)"
            )
        }
    }
    
    /// Activates the audio session
    /// - Throws: `AppError.audioSessionConfigurationFailed` if activation fails
    func activate() async throws {
        guard !isActive else { return }
        
        do {
            try audioSession.setActive(true, options: [])
            isActive = true
        } catch {
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to activate audio session: \(error.localizedDescription)"
            )
        }
    }
    
    /// Deactivates the audio session
    /// - Parameter notifyOthers: Whether to notify other apps they can resume audio
    func deactivate(notifyOthers: Bool = true) async {
        guard isActive else { return }
        
        do {
            let options: AVAudioSession.SetActiveOptions = notifyOthers ? [.notifyOthersOnDeactivation] : []
            try audioSession.setActive(false, options: options)
            isActive = false
        } catch {
            // Log but don't throw - deactivation failure is usually non-critical
            print("⚠️ Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Permissions
    
    /// Checks if microphone permission has been granted
    var hasMicrophonePermission: Bool {
        audioSession.recordPermission == .granted
    }
    
    /// Requests microphone permission
    /// - Returns: Whether permission was granted
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Audio Route
    
    /// Current audio output route description
    var currentRoute: String {
        audioSession.currentRoute.outputs
            .map { $0.portName }
            .joined(separator: ", ")
    }
    
    /// Whether headphones are connected
    var headphonesConnected: Bool {
        audioSession.currentRoute.outputs.contains { output in
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
                .contains(output.portType)
        }
    }
    
    // MARK: - Sample Rate
    
    /// Current hardware sample rate
    var sampleRate: Double {
        audioSession.sampleRate
    }
    
    /// Preferred sample rate for the app
    func setPreferredSampleRate(_ rate: Double) async throws {
        do {
            try audioSession.setPreferredSampleRate(rate)
        } catch {
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to set sample rate: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Buffer Duration
    
    /// Sets the preferred I/O buffer duration
    /// - Parameter duration: Desired buffer duration in seconds
    func setPreferredIOBufferDuration(_ duration: TimeInterval) async throws {
        do {
            try audioSession.setPreferredIOBufferDuration(duration)
        } catch {
            throw AppError.audioSessionConfigurationFailed(
                reason: "Failed to set buffer duration: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Private Methods
    
    /// Sets up notification observers for audio session events
    private func setupNotificationObservers() {
        // Interruption notifications
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleInterruption(notification)
            }
        }
        
        // Route change notifications
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleRouteChange(notification)
            }
        }
    }
    
    /// Handles audio session interruption notifications
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            isActive = false
            let event = AudioInterruptionEvent.began
            interruptionContinuation?.yield(event)
            delegate?.audioSessionWasInterrupted()
            
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                let shouldResume = options.contains(.shouldResume)
                let event = AudioInterruptionEvent.ended(shouldResume: shouldResume)
                interruptionContinuation?.yield(event)
                
                if shouldResume {
                    delegate?.audioSessionInterruptionEnded(shouldResume: true)
                }
            }
            
        @unknown default:
            break
        }
    }
    
    /// Handles audio route change notifications
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause playback
            delegate?.audioRouteChanged(reason: .deviceDisconnected)
            
        case .newDeviceAvailable:
            // New device connected
            delegate?.audioRouteChanged(reason: .deviceConnected)
            
        case .categoryChange:
            delegate?.audioRouteChanged(reason: .categoryChanged)
            
        default:
            break
        }
    }
}

// MARK: - AudioInterruptionEvent

/// Events representing audio session interruptions
enum AudioInterruptionEvent: Sendable {
    /// Interruption began (e.g., phone call)
    case began
    /// Interruption ended
    case ended(shouldResume: Bool)
}

// MARK: - AudioRouteChangeReason

/// Reasons for audio route changes
enum AudioRouteChangeReason: Sendable {
    case deviceConnected
    case deviceDisconnected
    case categoryChanged
}

// MARK: - AudioSessionDelegate

/// Delegate protocol for receiving audio session events
protocol AudioSessionDelegate: AnyObject, Sendable {
    /// Called when audio session is interrupted
    func audioSessionWasInterrupted()
    
    /// Called when audio session interruption ends
    func audioSessionInterruptionEnded(shouldResume: Bool)
    
    /// Called when audio route changes
    func audioRouteChanged(reason: AudioRouteChangeReason)
}

// MARK: - Default Delegate Implementation

extension AudioSessionDelegate {
    func audioSessionWasInterrupted() {}
    func audioSessionInterruptionEnded(shouldResume: Bool) {}
    func audioRouteChanged(reason: AudioRouteChangeReason) {}
}
