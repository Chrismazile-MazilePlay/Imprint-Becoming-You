//
//  SessionState.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 12/20/25.
//

import Foundation
import SwiftData

// MARK: - SessionState

/// Persists the current session state to allow resuming after app closure.
///
/// When the app is terminated or backgrounded, this model stores the user's
/// position in their affirmation session so they can resume exactly where
/// they left off.
@Model
final class SessionState {
    
    // MARK: - Properties
    
    /// Unique identifier for the session state
    @Attribute(.unique)
    var id: UUID
    
    /// Current index within the affirmation batch
    var currentAffirmationIndex: Int
    
    /// ID of the current batch being viewed
    var currentBatchId: UUID?
    
    /// The session mode being used
    var mode: SessionMode
    
    /// When the session was started
    var startedAt: Date
    
    /// Last time the session was active
    var lastActiveAt: Date
    
    /// Whether this is a custom prompt session
    var isCustomPromptSession: Bool
    
    /// ID of the custom prompt (if custom prompt session)
    var customPromptId: UUID?
    
    /// Total affirmations practiced in this session
    var affirmationsPracticed: Int
    
    /// Total time spent in this session (seconds)
    var totalSessionTime: TimeInterval
    
    /// Whether binaural beats were enabled
    var binauralEnabled: Bool
    
    /// Which binaural preset was used
    var binauralPreset: BinauralPreset
    
    // MARK: - Initialization
    
    /// Creates a new session state
    init(
        id: UUID = UUID(),
        currentAffirmationIndex: Int = 0,
        currentBatchId: UUID? = nil,
        mode: SessionMode = .readOnly,
        startedAt: Date = Date(),
        lastActiveAt: Date = Date(),
        isCustomPromptSession: Bool = false,
        customPromptId: UUID? = nil,
        affirmationsPracticed: Int = 0,
        totalSessionTime: TimeInterval = 0,
        binauralEnabled: Bool = false,
        binauralPreset: BinauralPreset = .off
    ) {
        self.id = id
        self.currentAffirmationIndex = currentAffirmationIndex
        self.currentBatchId = currentBatchId
        self.mode = mode
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.isCustomPromptSession = isCustomPromptSession
        self.customPromptId = customPromptId
        self.affirmationsPracticed = affirmationsPracticed
        self.totalSessionTime = totalSessionTime
        self.binauralEnabled = binauralEnabled
        self.binauralPreset = binauralPreset
    }
}

// MARK: - Computed Properties

extension SessionState {
    
    /// Duration since session started
    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
    
    /// Duration since last activity
    var timeSinceLastActive: TimeInterval {
        Date().timeIntervalSince(lastActiveAt)
    }
    
    /// Whether this session is considered stale (> 24 hours old)
    var isStale: Bool {
        timeSinceLastActive > (24 * 60 * 60)
    }
    
    /// Formatted session duration for display
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: totalSessionTime) ?? "0s"
    }
}

// MARK: - Methods

extension SessionState {
    
    /// Updates the last active timestamp
    func markActive() {
        lastActiveAt = Date()
    }
    
    /// Advances to the next affirmation
    func advanceToNext() {
        currentAffirmationIndex += 1
        affirmationsPracticed += 1
        markActive()
    }
    
    /// Moves to a specific affirmation index
    func moveTo(index: Int) {
        currentAffirmationIndex = index
        markActive()
    }
    
    /// Updates the total session time
    func updateSessionTime(_ additionalTime: TimeInterval) {
        totalSessionTime += additionalTime
    }
    
    /// Resets the session to the beginning
    func reset() {
        currentAffirmationIndex = 0
        affirmationsPracticed = 0
        totalSessionTime = 0
        startedAt = Date()
        lastActiveAt = Date()
    }
}

// MARK: - Sample Data

extension SessionState {
    
    /// Sample session state for previews
    static var sample: SessionState {
        SessionState(
            currentAffirmationIndex: 7,
            mode: .readThenSpeak,
            affirmationsPracticed: 7,
            totalSessionTime: 180
        )
    }
}
