//
//  AudioDuckingCoordinator.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/15/26.
//

import Foundation
import os.log

// MARK: - Logger

private let duckingLog = Logger(subsystem: "com.imprint.audio", category: "AudioDuckingCoordinator")

// MARK: - AudioDuckingCoordinator

/// Manages smooth volume transitions on background music to mask audio
/// pipeline glitches during speech recognition task creation.
///
/// ## Architecture
/// `SFSpeechRecognizer.recognitionTask(with:)` causes a brief (~20-80ms)
/// audio disruption as the Speech framework's internal pipeline initializes.
/// This coordinator smoothly ducks the music volume before the task is
/// created and restores it afterward, making the glitch imperceptible.
///
/// ## Usage
/// ```swift
/// // Before creating recognition task
/// await duckingCoordinator.duckDown()
/// try await startCapturePipeline()
/// // After capture is active
/// await duckingCoordinator.restoreUp()
/// ```
///
/// ## Thread Safety
/// All methods are `@MainActor` isolated. Volume changes are applied via
/// `BackgroundMusicService.setVolume()` which directly sets
/// `AVAudioPlayerNode.volume` — a thread-safe Core Audio property.
@MainActor
final class AudioDuckingCoordinator {

    // MARK: - Properties

    /// The background music service whose volume we control.
    private let musicService: BackgroundMusicService

    /// The user's chosen volume level (restored after ducking).
    ///
    /// Updated via ``setTargetVolume(_:)`` when the user adjusts the
    /// music volume slider. The coordinator always restores to this value.
    private var targetVolume: Float

    /// Currently active ramp task (cancelled on new ramp to prevent overlap).
    private var rampTask: Task<Void, Never>?

    /// Whether the music is currently in a ducked state.
    private(set) var isDucked: Bool = false

    // MARK: - Constants

    /// Volume floor during ducking — low enough to mask audio glitches
    /// but audible enough that the user perceives continuous music.
    private let duckedVolume: Float = 0.08

    /// Duration of the fade-down ramp in milliseconds.
    private let fadeDownDurationMs: Int = 200

    /// Duration of the fade-up ramp in milliseconds — slightly longer
    /// for a smoother, more natural restoration.
    private let fadeUpDurationMs: Int = 300

    /// Interval between volume steps in milliseconds (~60fps).
    private let stepIntervalMs: Int = 16

    // MARK: - Initialization

    /// Creates a new ducking coordinator.
    ///
    /// - Parameters:
    ///   - musicService: The background music service to control.
    ///   - initialVolume: The user's current music volume.
    init(musicService: BackgroundMusicService, initialVolume: Float) {
        self.musicService = musicService
        self.targetVolume = initialVolume
    }

    // MARK: - Public API

    /// Smoothly fades music volume down to the ducked level.
    ///
    /// Cancels any in-progress ramp. Returns after the fade completes
    /// (~200ms). Safe to call when already ducked — fast-paths to avoid
    /// redundant ramping.
    func duckDown() async {
        guard musicService.isPlaying else { return }

        // Cancel any in-progress ramp
        rampTask?.cancel()

        let startVolume = musicService.volume
        guard startVolume > duckedVolume else {
            isDucked = true
            return
        }

        #if DEBUG
        duckingLog.debug("🔉 Ducking music: \(startVolume, format: .fixed(precision: 2)) → \(self.duckedVolume, format: .fixed(precision: 2)) over \(self.fadeDownDurationMs)ms")
        #endif

        isDucked = true
        await rampVolume(from: startVolume, to: duckedVolume, durationMs: fadeDownDurationMs)
    }

    /// Smoothly restores music volume to the user's target level.
    ///
    /// Cancels any in-progress ramp. Returns after the fade completes
    /// (~300ms). Safe to call when not ducked — fast-paths to avoid
    /// redundant ramping.
    func restoreUp() async {
        guard musicService.isPlaying else {
            isDucked = false
            return
        }

        // Cancel any in-progress ramp
        rampTask?.cancel()

        let startVolume = musicService.volume
        let endVolume = targetVolume

        guard startVolume < endVolume else {
            isDucked = false
            return
        }

        #if DEBUG
        duckingLog.debug("🔊 Restoring music: \(startVolume, format: .fixed(precision: 2)) → \(endVolume, format: .fixed(precision: 2)) over \(self.fadeUpDurationMs)ms")
        #endif

        await rampVolume(from: startVolume, to: endVolume, durationMs: fadeUpDurationMs)
        isDucked = false
    }

    /// Updates the target volume when the user adjusts the music slider.
    ///
    /// If not currently ducked, also applies the volume immediately.
    /// If ducked, the new target is used on the next ``restoreUp()`` call.
    ///
    /// - Parameter volume: The user's new volume level (0.0–1.0).
    func setTargetVolume(_ volume: Float) {
        targetVolume = max(0, min(1, volume))

        if !isDucked {
            musicService.setVolume(targetVolume)
        }
    }

    // MARK: - Private

    /// Linearly interpolates the music volume from `start` to `end` over `durationMs`.
    ///
    /// Uses `Task.sleep` at ~60fps intervals for smooth animation.
    /// Cancellation-safe — the ramp stops cleanly if the task is cancelled.
    private func rampVolume(from start: Float, to end: Float, durationMs: Int) async {
        let steps = max(1, durationMs / stepIntervalMs)
        let delta = (end - start) / Float(steps)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            for step in 1...steps {
                // Check cancellation at each step
                if Task.isCancelled { return }

                let progress = Float(step) / Float(steps)
                let volume = start + (end - start) * progress
                self.musicService.setVolume(volume)

                if step < steps {
                    try? await Task.sleep(for: .milliseconds(self.stepIntervalMs))
                }
            }

            // Ensure we land exactly on the target
            self.musicService.setVolume(end)
        }

        rampTask = task
        await task.value
    }
}
